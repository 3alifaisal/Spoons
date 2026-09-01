--- === StudyMode ===
---
--- Focus mode Spoon for Hammerspoon.
--- Cycles between Study sessions (blocking sites) and Break sessions (unblocking sites).
--- Includes Hardcore Mode (activated by pressing fn+S 3 times rapidly):
---   - 40 min Study / 20 min Break
---   - Cannot be stopped manually (Console/Hotkey stop requests are denied)
---   - Automatically ends only after 5 consecutive study sessions complete.
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "StudyMode"
obj.version = "3.0"
obj.author = "Ali Faisal Awada"
obj.homepage = "https://github.com/3alifaisal/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration
obj.studyDuration = 45 * 60 -- 45 minutes normal study
obj.breakDuration = 15 * 60 -- 15 minutes normal break
obj.hardcoreStudyDuration = 40 * 60 -- 40 minutes hardcore study
obj.hardcoreBreakDuration = 20 * 60 -- 20 minutes hardcore break
obj.hardcoreTotalSessions = 5       -- 5 consecutive sessions

obj.helperPath = "/Library/HammerspoonStudyMode/study-mode-hosts"
obj.settingsKeyDeadline = "hammerspoon.studyMode.deadline"
obj.settingsKeyMode = "hammerspoon.studyMode.mode"
obj.settingsKeyHardcore = "hammerspoon.studyMode.hardcore"
obj.settingsKeySessionCount = "hammerspoon.studyMode.sessionCount"

obj.overlayWidth = 152
obj.overlayHeight = 36
obj.screenMargin = 12
obj.soundFile = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/Crystals.m4r"
obj.defaultHotkey = { { "cmd", "alt", "ctrl" }, "S" }

-- Internal state
local mode = "INACTIVE" -- "STUDY", "BREAK", "ALARM", "INACTIVE"
local isHardcore = false
local currentSession = 1
local deadline = nil
local ticker = nil
local alarmTimer = nil
local overlay = nil
local keyTapWatcher = nil
local screenWatcher = nil
local lastHotkeyTime = 0
local pressCount = 0
local pressTimer = nil
local alarmSound = nil

local BLOCKED_HOSTS_BLOCK = [[
# BEGIN HAMMERSPOON STUDY MODE
127.0.0.1 youtube.com www.youtube.com m.youtube.com music.youtube.com
127.0.0.1 studio.youtube.com kids.youtube.com tv.youtube.com gaming.youtube.com
127.0.0.1 youtu.be www.youtu.be youtube-nocookie.com www.youtube-nocookie.com
127.0.0.1 googlevideo.com www.googlevideo.com redirector.googlevideo.com
127.0.0.1 ytimg.com www.ytimg.com s.ytimg.com i.ytimg.com yt3.ggpht.com
127.0.0.1 youtubei.googleapis.com youtube.googleapis.com
127.0.0.1 chess.com www.chess.com v3.chess.com lichess.org www.lichess.org api.lichess.org en.lichess.org
0.0.0.0 youtube.com www.youtube.com m.youtube.com music.youtube.com
0.0.0.0 studio.youtube.com kids.youtube.com tv.youtube.com gaming.youtube.com
0.0.0.0 youtu.be www.youtu.be youtube-nocookie.com www.youtube-nocookie.com
0.0.0.0 googlevideo.com www.googlevideo.com redirector.googlevideo.com
0.0.0.0 ytimg.com www.ytimg.com s.ytimg.com i.ytimg.com yt3.ggpht.com
0.0.0.0 youtubei.googleapis.com youtube.googleapis.com
0.0.0.0 chess.com www.chess.com v3.chess.com lichess.org www.lichess.org api.lichess.org en.lichess.org
::1 youtube.com www.youtube.com m.youtube.com music.youtube.com
::1 studio.youtube.com kids.youtube.com tv.youtube.com gaming.youtube.com
::1 youtu.be www.youtu.be youtube-nocookie.com www.youtube-nocookie.com
::1 googlevideo.com www.googlevideo.com redirector.googlevideo.com
::1 ytimg.com www.ytimg.com s.ytimg.com i.ytimg.com yt3.ggpht.com
::1 youtubei.googleapis.com youtube.googleapis.com
::1 chess.com www.chess.com v3.chess.com lichess.org www.lichess.org api.lichess.org en.lichess.org
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

-- Execute hosts edit asynchronously/safely without blocking UI
local function applyHostsBlock(enable)
  pcall(function()
    if hs.fs.attributes(obj.helperPath) then
      local cmd = enable and "on" or "off"
      local output, status, type, rc = hs.execute(string.format("sudo -n %s %s", obj.helperPath, cmd))
      if rc == 0 then return end
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
    hs.osascript.applescript(appleScript)
  end)
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
  local screen = hs.screen.mainScreen() or hs.screen.primaryScreen()
  if not screen then return end

  local frame = screen:frame()
  overlay:frame({
    x = frame.x + frame.w - obj.overlayWidth - obj.screenMargin,
    y = frame.y + obj.screenMargin,
    w = obj.overlayWidth,
    h = obj.overlayHeight,
  })
end

-- Forward declaration
local handleAlarmClick

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
    -- 3. Label ("STUDY" / "BREAK" / "🔥 1/5")
    {
      type = "text",
      text = "STUDY",
      textColor = { red = 0.55, green = 0.65, blue = 0.60, alpha = 1.0 },
      textSize = 11,
      textFont = ".SFNS-Medium",
      frame = { x = 28, y = 10, w = 56, h = 18 },
    },
    -- 4. Timer text ("40:00")
    {
      type = "text",
      text = "45:00",
      textAlignment = "right",
      textColor = { red = 0.92, green = 0.98, blue = 0.94, alpha = 1.0 },
      textSize = 14,
      textFont = ".SFNS-Bold",
      frame = { x = 74, y = 9, w = 64, h = 18 },
    }
  )

  overlay:level(hs.drawing.windowLevels.overlay)
  overlay:behavior({ "canJoinAllSpaces", "stationary" })
  overlay:canvasMouseEvents(true)
  overlay:mouseCallback(function(canvas, event, id, x, y)
    if event == "mouseDown" then
      if mode == "ALARM" then
        handleAlarmClick()
      elseif mode == "BREAK" then
        local tag = isHardcore and string.format("🔥 Hardcore Break (%d/5)", currentSession) or "Break"
        hs.alert.show(tag .. " active (" .. formatRemaining(remainingSeconds()) .. " left)")
      elseif mode == "STUDY" then
        local tag = isHardcore and string.format("🔥 Hardcore Study (%d/5)", currentSession) or "Study"
        hs.alert.show(tag .. " active (" .. formatRemaining(remainingSeconds()) .. " left)")
      end
    end
  end)

  positionOverlay()
  overlay:show()
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
    if isHardcore then
      overlay:elementAttribute(1, "strokeColor", { red = 1.00, green = 0.25, blue = 0.25, alpha = 0.95 })
      overlay:elementAttribute(2, "fillColor", { red = 1.00, green = 0.30, blue = 0.30, alpha = 1.0 })
      overlay:elementAttribute(3, "text", string.format("🔥 %d/%d", currentSession, obj.hardcoreTotalSessions))
      overlay:elementAttribute(3, "textColor", { red = 1.00, green = 0.60, blue = 0.60, alpha = 1.0 })
    else
      overlay:elementAttribute(1, "strokeColor", { red = 0.20, green = 0.85, blue = 0.55, alpha = 0.90 })
      overlay:elementAttribute(2, "fillColor", { red = 0.22, green = 0.90, blue = 0.55, alpha = 1.0 })
      overlay:elementAttribute(3, "text", "STUDY")
      overlay:elementAttribute(3, "textColor", { red = 0.55, green = 0.65, blue = 0.60, alpha = 1.0 })
    end
    overlay:elementAttribute(4, "text", formatRemaining(remainingSeconds()))

  elseif mode == "BREAK" then
    if isHardcore then
      overlay:elementAttribute(1, "strokeColor", { red = 1.00, green = 0.55, blue = 0.20, alpha = 0.95 })
      overlay:elementAttribute(2, "fillColor", { red = 1.00, green = 0.60, blue = 0.25, alpha = 1.0 })
      overlay:elementAttribute(3, "text", string.format("☕ %d/%d", currentSession, obj.hardcoreTotalSessions))
      overlay:elementAttribute(3, "textColor", { red = 1.00, green = 0.75, blue = 0.45, alpha = 1.0 })
    else
      overlay:elementAttribute(1, "strokeColor", { red = 0.95, green = 0.65, blue = 0.20, alpha = 0.90 })
      overlay:elementAttribute(2, "fillColor", { red = 0.98, green = 0.70, blue = 0.25, alpha = 1.0 })
      overlay:elementAttribute(3, "text", "BREAK")
      overlay:elementAttribute(3, "textColor", { red = 0.90, green = 0.75, blue = 0.50, alpha = 1.0 })
    end
    overlay:elementAttribute(4, "text", formatRemaining(remainingSeconds()))

  elseif mode == "ALARM" then
    overlay:elementAttribute(1, "strokeColor", { red = 1.00, green = 0.30, blue = 0.30, alpha = 1.0 })
    overlay:elementAttribute(2, "fillColor", { red = 1.00, green = 0.35, blue = 0.35, alpha = 1.0 })
    if isHardcore then
      overlay:elementAttribute(3, "text", string.format("🔔 %d/%d", currentSession, obj.hardcoreTotalSessions))
    else
      overlay:elementAttribute(3, "text", "🔔 START")
    end
    overlay:elementAttribute(3, "textColor", { red = 1.00, green = 0.50, blue = 0.50, alpha = 1.0 })
    overlay:elementAttribute(4, "text", "STUDY")
  end
end

local function saveState()
  hs.settings.set(obj.settingsKeyMode, mode)
  hs.settings.set(obj.settingsKeyDeadline, deadline)
  hs.settings.set(obj.settingsKeyHardcore, isHardcore)
  hs.settings.set(obj.settingsKeySessionCount, currentSession)
end

-- Forward declarations of phase functions
local startBreakPhase
local startAlarmPhase
local startStudyPhase

local function updateLoop()
  if mode == "STUDY" or mode == "BREAK" then
    local seconds = remainingSeconds()
    updateOverlayUI()

    if seconds <= 0 then
      if mode == "STUDY" then
        startBreakPhase()
      elseif mode == "BREAK" then
        startAlarmPhase()
      end
    end
  end
end

handleAlarmClick = function()
  if isHardcore then
    if currentSession < obj.hardcoreTotalSessions then
      currentSession = currentSession + 1
      saveState()
      startStudyPhase()
    else
      -- 5th session finished! Hardcore mode ends on its own.
      isHardcore = false
      currentSession = 1
      mode = "INACTIVE"
      deadline = nil
      stopTicker()
      stopAlarmSound()
      hideOverlay()

      hs.settings.set(obj.settingsKeyMode, nil)
      hs.settings.set(obj.settingsKeyDeadline, nil)
      hs.settings.set(obj.settingsKeyHardcore, nil)
      hs.settings.set(obj.settingsKeySessionCount, nil)

      hs.timer.doAfter(0.01, function()
        applyHostsBlock(false)
      end)

      hs.notify.new({
        title = "🎉 HARDCORE MODE COMPLETE! 🏆",
        informativeText = "5 consecutive 40-minute study sessions finished on its own! Incredible job!",
        soundName = "Glass",
      }):send()

      hs.alert.show("🎉 HARDCORE MODE COMPLETE!\nAll 5 sessions finished on its own!", 5)
    end
  else
    startStudyPhase()
  end
end

startAlarmPhase = function()
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

  local infoText = isHardcore
    and string.format("Hardcore Session %d/%d break over! Click timer or press fn+S to start next session.", currentSession, obj.hardcoreTotalSessions)
    or "Click the top-right timer or press fn+S to start your next 45-minute study session."

  hs.notify.new({
    title = "Break is over! 🔔",
    informativeText = infoText,
    soundName = "Crystals",
  }):send()
end

startBreakPhase = function()
  mode = "BREAK"
  local breakDur = isHardcore and obj.hardcoreBreakDuration or obj.breakDuration
  deadline = hs.timer.secondsSinceEpoch() + breakDur
  stopAlarmSound()
  saveState()

  ensureOverlay()
  updateOverlayUI()

  stopTicker()
  ticker = hs.timer.doEvery(1, updateLoop)

  hs.timer.doAfter(0.01, function()
    applyHostsBlock(false)
  end)

  local titleMsg = isHardcore
    and string.format("🔥 Hardcore Session %d/%d Study Complete! ☕", currentSession, obj.hardcoreTotalSessions)
    ["45-Minute Study Session Complete! ☕"]

  local breakMsg = isHardcore
    and string.format("20-Minute Break started (Session %d/%d) ☕\nSites unblocked.", currentSession, obj.hardcoreTotalSessions)
    or "15-Minute Break started ☕\nSites unblocked."

  hs.notify.new({
    title = isHardcore and string.format("🔥 Hardcore Session %d/%d Complete! ☕", currentSession, obj.hardcoreTotalSessions) or "45-Minute Study Session Complete! ☕",
    informativeText = isHardcore and "20-minute break started. YouTube & Chess are available." or "15-minute break started. YouTube & Chess are available.",
    soundName = "Glass",
  }):send()

  hs.alert.show(breakMsg, 3)
end

startStudyPhase = function()
  stopAlarmSound()

  mode = "STUDY"
  local studyDur = isHardcore and obj.hardcoreStudyDuration or obj.studyDuration
  deadline = hs.timer.secondsSinceEpoch() + studyDur
  saveState()

  ensureOverlay()
  updateOverlayUI()

  stopTicker()
  ticker = hs.timer.doEvery(1, updateLoop)

  hs.timer.doAfter(0.01, function()
    applyHostsBlock(true)
  end)

  local alertMsg = isHardcore
    and string.format("🔥 HARDCORE MODE: Session %d/%d (%d:00)\nYouTube & Chess blocked.", currentSession, obj.hardcoreTotalSessions, math.floor(studyDur / 60))
    or string.format("Study Session active (%d:00)\nYouTube & Chess blocked.", math.floor(studyDur / 60))

  hs.alert.show(alertMsg, 3)
end

function obj:startStudyPhase()
  startStudyPhase()
end

function obj:startBreakPhase()
  startBreakPhase()
end

function obj:startAlarmPhase()
  startAlarmPhase()
end

--- StudyMode:activateHardcoreMode()
--- Activates Hardcore Mode: 5 consecutive sessions (40m Study / 20m Break), non-removable.
--- Overrides normal Study Mode if already running.
function obj:activateHardcoreMode()
  if isHardcore then
    hs.alert.show(
      string.format("🔥 HARDCORE MODE ALREADY ACTIVE (%d/%d sessions)", currentSession, obj.hardcoreTotalSessions),
      4
    )
    return
  end

  -- Stop previous active tickers and override with Hardcore Mode!
  stopTicker()
  stopAlarmSound()

  isHardcore = true
  currentSession = 1
  saveState()

  hs.notify.new({
    title = "🔥 HARDCORE MODE ACTIVATED!",
    informativeText = "5 consecutive sessions (40m Study / 20m Break).\nCANNOT be stopped manually!",
    soundName = "Hero",
  }):send()

  hs.alert.show(
    "🔥 HARDCORE MODE ACTIVATED!\nOverriding Study Mode!\n5 Sessions: 40m Study / 20m Break\nCANNOT BE STOPPED MANUALLY.",
    5
  )

  startStudyPhase()
end

--- StudyMode:start()
function obj:start()
  if mode == "ALARM" then
    handleAlarmClick()
  elseif mode == "STUDY" then
    local tag = isHardcore and string.format("🔥 Hardcore Session %d/%d", currentSession, obj.hardcoreTotalSessions) or "Study Session"
    hs.alert.show(tag .. " active: " .. formatRemaining(remainingSeconds()) .. " remaining")
  elseif mode == "BREAK" then
    local tag = isHardcore and string.format("🔥 Hardcore Break %d/%d", currentSession, obj.hardcoreTotalSessions) or "Break"
    hs.alert.show(tag .. " active: " .. formatRemaining(remainingSeconds()) .. " remaining")
  else
    startStudyPhase()
  end
end

--- StudyMode:stop()
--- Emergency stop request. Blocked during Hardcore Mode!
function obj:stop()
  if isHardcore then
    hs.alert.show(
      string.format("🔥 HARDCORE MODE IS ACTIVE (%d/%d)\nCannot be stopped until 5 sessions complete!", currentSession, obj.hardcoreTotalSessions),
      5
    )
    print("🔥 Hardcore Mode is active. Stop request denied.")
    return false
  end

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
  hs.settings.set(obj.settingsKeyHardcore, nil)
  hs.settings.set(obj.settingsKeySessionCount, nil)

  hs.timer.doAfter(0.01, function()
    applyHostsBlock(false)
  end)

  hs.alert.show("Study Mode stopped")
end

--- StudyMode:toggle()
function obj:toggle()
  if mode == "ALARM" then
    handleAlarmClick()
  elseif mode == "INACTIVE" then
    startStudyPhase()
  else
    local tag = isHardcore and string.format("🔥 Hardcore %s (%d/%d)", mode, currentSession, obj.hardcoreTotalSessions) or mode
    hs.alert.show(string.format("%s active: %s left", tag, formatRemaining(remainingSeconds())))
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
    local isHoldingFnS = false
    local holdTimer = nil

    keyTapWatcher = hs.eventtap.new(
      { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp },
      function(event)
        local flags = event:getFlags()
        local isStudyKey = (event:getKeyCode() == hs.keycodes.map.s)
        local isFnS = isStudyKey and flags.fn and not flags.cmd and not flags.alt and not flags.ctrl and not flags.shift
        local eventType = event:getType()

        if eventType == hs.eventtap.event.types.keyUp and isStudyKey then
          if isHoldingFnS then
            isHoldingFnS = false
            if holdTimer then
              holdTimer:stop()
              holdTimer = nil
              hs.timer.doAfter(0, function() obj:toggle() end)
            end
            return true
          end
          return false
        end

        if not isFnS then return false end

        if eventType == hs.eventtap.event.types.keyDown then
          if not isHoldingFnS then
            isHoldingFnS = true
            if holdTimer then holdTimer:stop() end

            holdTimer = hs.timer.doAfter(3.0, function()
              holdTimer = nil
              isHoldingFnS = false
              hs.timer.doAfter(0, function() obj:activateHardcoreMode() end)
            end)
          end
          return true
        end

        return false
      end
    )
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

  -- Recovery on config reload / restart
  local savedMode = hs.settings.get(obj.settingsKeyMode)
  local savedDeadline = hs.settings.get(obj.settingsKeyDeadline)
  local savedHardcore = hs.settings.get(obj.settingsKeyHardcore)
  local savedCount = hs.settings.get(obj.settingsKeySessionCount)

  if savedHardcore == true then
    isHardcore = true
    currentSession = type(savedCount) == "number" and savedCount or 1
  end

  if savedMode == "STUDY" and type(savedDeadline) == "number" then
    if savedDeadline > hs.timer.secondsSinceEpoch() then
      mode = "STUDY"
      deadline = savedDeadline
      ensureOverlay()
      updateOverlayUI()
      stopTicker()
      ticker = hs.timer.doEvery(1, updateLoop)
      hs.timer.doAfter(0.01, function() applyHostsBlock(true) end)
    else
      startBreakPhase()
    end
  elseif savedMode == "BREAK" and type(savedDeadline) == "number" then
    if savedDeadline > hs.timer.secondsSinceEpoch() then
      mode = "BREAK"
      deadline = savedDeadline
      ensureOverlay()
      updateOverlayUI()
      stopTicker()
      ticker = hs.timer.doEvery(1, updateLoop)
      hs.timer.doAfter(0.01, function() applyHostsBlock(false) end)
    else
      startAlarmPhase()
    end
  elseif savedMode == "ALARM" then
    startAlarmPhase()
  end

  return self
end

return obj
