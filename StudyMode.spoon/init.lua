--- === StudyMode ===
---
--- Focus mode Spoon for Hammerspoon.
--- Cycles between a 45-minute Study phase (blocking sites) and a 15-minute Break phase (unblocking sites).
--- When the break ends, it continuously rings the 'Crystals' sound until clicked or triggered to start a new cycle.
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "StudyMode"
obj.version = "2.4"
obj.author = "Ali Faisal Awada"
obj.homepage = "https://github.com/3alifaisal/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration
obj.studyDuration = 45 * 60 -- 45 minutes study
obj.breakDuration = 15 * 60 -- 15 minutes break
obj.helperPath = "/Library/HammerspoonStudyMode/study-mode-hosts"
obj.settingsKeyDeadline = "hammerspoon.studyMode.deadline"
obj.settingsKeyMode = "hammerspoon.studyMode.mode"
obj.overlayWidth = 144
obj.overlayHeight = 36
obj.screenMargin = 12
obj.soundFile = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/Crystals.m4r"
obj.defaultHotkey = { { "cmd", "alt", "ctrl" }, "S" }

-- Internal state
local mode = "INACTIVE" -- "STUDY", "BREAK", "ALARM", "INACTIVE"
local deadline = nil
local ticker = nil
local alarmTimer = nil
local overlay = nil
local keyTapWatcher = nil
local screenWatcher = nil
local lastHotkeyTime = 0
local alarmSound = nil

local BLOCKED_HOSTS_BLOCK = [[
# BEGIN HAMMERSPOON STUDY MODE
127.0.0.1 youtube.com www.youtube.com m.youtube.com music.youtube.com studio.youtube.com kids.youtube.com tv.youtube.com gaming.youtube.com youtu.be www.youtu.be youtube-nocookie.com www.youtube-nocookie.com googlevideo.com www.googlevideo.com redirector.googlevideo.com ytimg.com www.ytimg.com s.ytimg.com i.ytimg.com yt3.ggpht.com youtubei.googleapis.com youtube.googleapis.com
127.0.0.1 chess.com www.chess.com v3.chess.com lichess.org www.lichess.org api.lichess.org en.lichess.org
127.0.0.1 gemini.google.com bard.google.com aistudio.google.com
0.0.0.0 youtube.com www.youtube.com m.youtube.com music.youtube.com studio.youtube.com kids.youtube.com tv.youtube.com gaming.youtube.com youtu.be www.youtu.be youtube-nocookie.com www.youtube-nocookie.com googlevideo.com www.googlevideo.com redirector.googlevideo.com ytimg.com www.ytimg.com s.ytimg.com i.ytimg.com yt3.ggpht.com youtubei.googleapis.com youtube.googleapis.com
0.0.0.0 chess.com www.chess.com v3.chess.com lichess.org www.lichess.org api.lichess.org en.lichess.org
0.0.0.0 gemini.google.com bard.google.com aistudio.google.com
::1 youtube.com www.youtube.com m.youtube.com music.youtube.com studio.youtube.com kids.youtube.com tv.youtube.com gaming.youtube.com youtu.be www.youtu.be youtube-nocookie.com www.youtube-nocookie.com googlevideo.com www.googlevideo.com redirector.googlevideo.com ytimg.com www.ytimg.com s.ytimg.com i.ytimg.com yt3.ggpht.com youtubei.googleapis.com youtube.googleapis.com
::1 chess.com www.chess.com v3.chess.com lichess.org www.lichess.org api.lichess.org en.lichess.org
::1 gemini.google.com bard.google.com aistudio.google.com
# END HAMMERSPOON STUDY MODE
]]

local function formatRemaining(totalSeconds)
  local seconds = math.max(0, math.ceil(totalSeconds))
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function remainingSeconds()
  if not deadline then return 0 end
  return math.max(0, deadline - hs.timer.secondsSinceEpoch())
end

-- Execute hosts edit via helper or direct fallback
local function applyHostsBlock(enable)
  if hs.fs.attributes(obj.helperPath) then
    local cmd = enable and "on" or "off"
    local output, status, type, rc = hs.execute(string.format("sudo -n %s %s", obj.helperPath, cmd))
    if rc == 0 then return true end
  end

  local shScript
  if enable then
    shScript = string.format([[
      /usr/bin/sed -i '' '/# BEGIN HAMMERSPOON STUDY MODE/,/# END HAMMERSPOON STUDY MODE/d' /etc/hosts
      /bin/cat << 'EOF' >> /etc/hosts
%sEOF
      /usr/bin/dscacheutil -flushcache
      /usr/bin/killall -HUP mDNSResponder 2>/dev/null || true
    ]], BLOCKED_HOSTS_BLOCK)
  else
    shScript = [[
      /usr/bin/sed -i '' '/# BEGIN HAMMERSPOON STUDY MODE/,/# END HAMMERSPOON STUDY MODE/d' /etc/hosts
      /usr/bin/dscacheutil -flushcache
      /usr/bin/killall -HUP mDNSResponder 2>/dev/null || true
    ]]
  end

  local appleScript = string.format([[do shell script %s with administrator privileges]], hs.inspect(shScript))
  local ok, res = hs.osascript.applescript(appleScript)
  return ok
end

local function stopAlarmSound()
  if alarmTimer then
    alarmTimer:stop()
    alarmTimer = nil
  end
  if alarmSound then
    pcall(function() alarmSound:stop() end)
    alarmSound = nil
  end
end

local function playCrystalsRing()
  if not alarmSound then
    alarmSound = hs.sound.getByFile(obj.soundFile) or hs.sound.getByName("Crystals") or hs.sound.getByName("Glass")
  end
  if alarmSound then
    pcall(function()
      alarmSound:stop()
      alarmSound:play()
    end)
  end
end

local function positionOverlay()
  if not overlay then return end
  local screen = hs.screen.mainScreen()
  if not screen then return end

  local frame = screen:frame()
  overlay:frame({
    x = frame.x + frame.w - obj.overlayWidth - obj.screenMargin,
    y = frame.y + obj.screenMargin,
    w = obj.overlayWidth,
    h = obj.overlayHeight,
  })
end

local function ensureOverlay()
  if overlay then return end

  overlay = hs.canvas.new({ x = 0, y = 0, w = obj.overlayWidth, h = obj.overlayHeight })
  overlay:appendElements(
    -- 1. Outer background pill
    {
      type = "rectangle",
      action = "strokeAndFill",
      fillColor = { red = 0.08, green = 0.09, blue = 0.12, alpha = 0.94 },
      strokeColor = { red = 0.20, green = 0.85, blue = 0.55, alpha = 0.90 },
      strokeWidth = 1.4,
      roundedRectRadii = { xRadius = 18, yRadius = 18 },
    },
    -- 2. Dot indicator
    {
      type = "circle",
      action = "fill",
      fillColor = { red = 0.22, green = 0.90, blue = 0.55, alpha = 1.0 },
      center = { x = 18, y = 18 },
      radius = 4,
    },
    -- 3. Label ("STUDY" / "BREAK" / "🔔 START")
    {
      type = "text",
      text = "STUDY",
      textColor = { red = 0.55, green = 0.65, blue = 0.60, alpha = 1.0 },
      textSize = 11,
      textFont = ".SFNS-Medium",
      frame = { x = 28, y = 10, w = 50, h = 18 },
    },
    -- 4. Timer text ("45:00")
    {
      type = "text",
      text = "45:00",
      textAlignment = "right",
      textColor = { red = 0.92, green = 0.98, blue = 0.94, alpha = 1.0 },
      textSize = 14,
      textFont = ".SFNS-Bold",
      frame = { x = 70, y = 9, w = 60, h = 18 },
    }
  )

  overlay:level(hs.canvas.windowLevels.screenSaver)
  overlay:behavior({ "canJoinAllSpaces", "stationary", "ignoresCycle" })
  overlay:canvasMouseEvents({ mouseDown = true })
  overlay:mouseCallback(function(canvas, event, id, x, y)
    if event == "mouseDown" then
      if mode == "ALARM" then
        obj:startStudyPhase()
      elseif mode == "BREAK" then
        hs.alert.show("Break active (" .. formatRemaining(remainingSeconds()) .. " left)")
      elseif mode == "STUDY" then
        hs.alert.show("Study active (" .. formatRemaining(remainingSeconds()) .. " left)")
      end
    end
  end)

  positionOverlay()
  overlay:show(0.15)
end

local function hideOverlay()
  if overlay then
    pcall(function() overlay:delete(0.15) end)
    overlay = nil
  end
end

local function stopTicker()
  if ticker then
    ticker:stop()
    ticker = nil
  end
end

local function updateOverlayUI()
  ensureOverlay()
  if not overlay then return end

  if mode == "STUDY" then
    overlay:elementAttribute(1, "strokeColor", { red = 0.20, green = 0.85, blue = 0.55, alpha = 0.90 })
    overlay:elementAttribute(2, "fillColor", { red = 0.22, green = 0.90, blue = 0.55, alpha = 1.0 })
    overlay:elementAttribute(3, "text", "STUDY")
    overlay:elementAttribute(3, "textColor", { red = 0.55, green = 0.65, blue = 0.60, alpha = 1.0 })
    overlay:elementAttribute(4, "text", formatRemaining(remainingSeconds()))

  elseif mode == "BREAK" then
    overlay:elementAttribute(1, "strokeColor", { red = 0.95, green = 0.65, blue = 0.20, alpha = 0.90 })
    overlay:elementAttribute(2, "fillColor", { red = 0.98, green = 0.70, blue = 0.25, alpha = 1.0 })
    overlay:elementAttribute(3, "text", "BREAK")
    overlay:elementAttribute(3, "textColor", { red = 0.90, green = 0.75, blue = 0.50, alpha = 1.0 })
    overlay:elementAttribute(4, "text", formatRemaining(remainingSeconds()))

  elseif mode == "ALARM" then
    overlay:elementAttribute(1, "strokeColor", { red = 1.00, green = 0.30, blue = 0.30, alpha = 1.0 })
    overlay:elementAttribute(2, "fillColor", { red = 1.00, green = 0.35, blue = 0.35, alpha = 1.0 })
    overlay:elementAttribute(3, "text", "🔔 START")
    overlay:elementAttribute(3, "textColor", { red = 1.00, green = 0.50, blue = 0.50, alpha = 1.0 })
    overlay:elementAttribute(4, "text", "STUDY")
  end
end

local function saveState()
  hs.settings.set(obj.settingsKeyMode, mode)
  hs.settings.set(obj.settingsKeyDeadline, deadline)
end

-- Forward declaration
local updateLoop

--- StudyMode:startAlarmPhase()
function obj:startAlarmPhase()
  mode = "ALARM"
  deadline = nil
  stopTicker()
  saveState()

  updateOverlayUI()
  playCrystalsRing()

  stopAlarmSound()
  alarmTimer = hs.timer.doEvery(2.5, function()
    if mode == "ALARM" then
      playCrystalsRing()
    else
      stopAlarmSound()
    end
  end)

  hs.notify.new({
    title = "Break is over! 🔔",
    informativeText = "Click the top-right timer or press fn+S to start your next 45-minute study session.",
    soundName = "Crystals",
  }):send()
end

--- StudyMode:startBreakPhase()
function obj:startBreakPhase()
  mode = "BREAK"
  deadline = hs.timer.secondsSinceEpoch() + obj.breakDuration
  stopAlarmSound()
  saveState()

  applyHostsBlock(false)
  ensureOverlay()
  updateOverlayUI()

  stopTicker()
  ticker = hs.timer.doEvery(1, updateLoop)

  hs.notify.new({
    title = "45-Minute Study Session Complete! ☕",
    informativeText = "15-minute break started. YouTube, Chess, & Gemini are available.",
    soundName = "Glass",
  }):send()

  hs.alert.show("15-Minute Break started ☕\nSites unblocked.", 3)
end

--- StudyMode:startStudyPhase()
function obj:startStudyPhase()
  stopAlarmSound()

  mode = "STUDY"
  deadline = hs.timer.secondsSinceEpoch() + obj.studyDuration
  saveState()

  ensureOverlay()
  updateOverlayUI()

  stopTicker()
  ticker = hs.timer.doEvery(1, updateLoop)

  applyHostsBlock(true)

  hs.alert.show(
    string.format("Study Session active (%d:00)\nYouTube, Chess, & Gemini blocked.", math.floor(obj.studyDuration / 60)),
    3
  )
end

updateLoop = function()
  if mode == "STUDY" or mode == "BREAK" then
    local seconds = remainingSeconds()
    updateOverlayUI()

    if seconds <= 0 then
      if mode == "STUDY" then
        obj:startBreakPhase()
      elseif mode == "BREAK" then
        obj:startAlarmPhase()
      end
    end
  end
end

--- StudyMode:start()
function obj:start()
  if mode == "ALARM" then
    self:startStudyPhase()
  elseif mode == "STUDY" then
    hs.alert.show("Study Session active: " .. formatRemaining(remainingSeconds()) .. " remaining")
  elseif mode == "BREAK" then
    hs.alert.show("Break active: " .. formatRemaining(remainingSeconds()) .. " remaining")
  else
    self:startStudyPhase()
  end
end

--- StudyMode:stop()
function obj:stop()
  if mode == "INACTIVE" then
    hs.alert.show("Study Mode is not active")
    return
  end

  mode = "INACTIVE"
  deadline = nil
  stopTicker()
  stopAlarmSound()
  hideOverlay()

  hs.settings.set(obj.settingsKeyMode, nil)
  hs.settings.set(obj.settingsKeyDeadline, nil)
  applyHostsBlock(false)

  hs.alert.show("Study Mode stopped")
end

--- StudyMode:toggle()
function obj:toggle()
  if mode == "ALARM" then
    self:startStudyPhase()
  elseif mode == "INACTIVE" then
    self:startStudyPhase()
  else
    hs.alert.show(string.format("%s active: %s left", mode, formatRemaining(remainingSeconds())))
  end
end

--- StudyMode:bindHotkeys(mapping)
function obj:bindHotkeys(mapping)
  local spec = {
    start = hs.fnutils.partial(self.start, self),
    stop = hs.fnutils.partial(self.stop, self),
    toggle = hs.fnutils.partial(self.toggle, self),
  }
  hs.spoons.bindHotkeysToSpec(spec, mapping)
  return self
end

--- StudyMode:init()
function obj:init()
  if not keyTapWatcher then
    keyTapWatcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
      local flags = event:getFlags()
      local isStudyShortcut = event:getKeyCode() == hs.keycodes.map.s
        and flags.fn
        and not flags.cmd
        and not flags.alt
        and not flags.ctrl
        and not flags.shift

      if not isStudyShortcut then return false end

      local now = hs.timer.secondsSinceEpoch()
      if now - lastHotkeyTime > 0.5 then
        lastHotkeyTime = now
        hs.timer.doAfter(0, function() obj:toggle() end)
      end
      return true
    end)
    keyTapWatcher:start()
  end

  if not screenWatcher then
    screenWatcher = hs.screen.watcher.new(function()
      if overlay then
        hs.timer.doAfter(0.1, positionOverlay)
      end
    end)
    screenWatcher:start()
  end

  local savedMode = hs.settings.get(obj.settingsKeyMode)
  local savedDeadline = hs.settings.get(obj.settingsKeyDeadline)

  if savedMode == "STUDY" and type(savedDeadline) == "number" then
    if savedDeadline > hs.timer.secondsSinceEpoch() then
      mode = "STUDY"
      deadline = savedDeadline
      applyHostsBlock(true)
      ensureOverlay()
      updateOverlayUI()
      stopTicker()
      ticker = hs.timer.doEvery(1, updateLoop)
    else
      obj:startBreakPhase()
    end
  elseif savedMode == "BREAK" and type(savedDeadline) == "number" then
    if savedDeadline > hs.timer.secondsSinceEpoch() then
      mode = "BREAK"
      deadline = savedDeadline
      applyHostsBlock(false)
      ensureOverlay()
      updateOverlayUI()
      stopTicker()
      ticker = hs.timer.doEvery(1, updateLoop)
    else
      obj:startAlarmPhase()
    end
  elseif savedMode == "ALARM" then
    obj:startAlarmPhase()
  end

  return self
end

return obj
