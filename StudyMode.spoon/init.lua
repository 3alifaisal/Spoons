--- === StudyMode ===
---
--- Focus mode Spoon for Hammerspoon.
--- Displays a persistent floating top-right timer and blocks distracting sites (YouTube, Chess, Gemini AI).
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "StudyMode"
obj.version = "1.2"
obj.author = "Ali Faisal Awada"
obj.homepage = "https://github.com/3alifaisal/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration
obj.duration = 45 * 60 -- 45 minutes default
obj.helperPath = "/Library/HammerspoonStudyMode/study-mode-hosts"
obj.settingsKey = "hammerspoon.studyMode.deadline"
obj.overlayWidth = 138
obj.overlayHeight = 36
obj.screenMargin = 12
obj.defaultHotkey = { { "cmd", "alt", "ctrl" }, "S" }

-- Internal state
local active = false
local deadline = nil
local ticker = nil
local overlay = nil
local keyTapWatcher = nil
local screenWatcher = nil
local lastHotkeyTime = 0

local BLOCKED_HOSTS_BLOCK = [[
# BEGIN HAMMERSPOON STUDY MODE
127.0.0.1 youtube.com www.youtube.com m.youtube.com music.youtube.com studio.youtube.com kids.youtube.com tv.youtube.com gaming.youtube.com youtu.be www.youtu.be youtube-nocookie.com www.youtube-nocookie.com
127.0.0.1 chess.com www.chess.com v3.chess.com lichess.org www.lichess.org api.lichess.org en.lichess.org
127.0.0.1 gemini.google.com bard.google.com aistudio.google.com
::1 youtube.com www.youtube.com m.youtube.com music.youtube.com studio.youtube.com kids.youtube.com tv.youtube.com gaming.youtube.com youtu.be www.youtu.be youtube-nocookie.com www.youtube-nocookie.com
::1 chess.com www.chess.com v3.chess.com lichess.org www.lichess.org api.lichess.org en.lichess.org
::1 gemini.google.com bard.google.com aistudio.google.com
# END HAMMERSPOON STUDY MODE
]]

local function formatRemaining(totalSeconds)
  local seconds = math.max(0, math.ceil(totalSeconds))
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function remainingSeconds()
  if not active or not deadline then return 0 end
  return math.max(0, deadline - hs.timer.secondsSinceEpoch())
end

-- Execute hosts edit via helper or direct fallback
local function applyHostsBlock(enable)
  -- 1. Try helper script if present and executable
  if hs.fs.attributes(obj.helperPath) then
    local cmd = enable and "on" or "off"
    local output, status, type, rc = hs.execute(string.format("sudo -n %s %s", obj.helperPath, cmd))
    if rc == 0 then return true end
  end

  -- 2. Direct /etc/hosts modification fallback
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

  local escapedSh = shScript:gsub('"', '\\"')
  local output, status, type, rc = hs.execute(string.format('sudo -n /bin/sh -c "%s"', escapedSh))
  if rc == 0 then return true end

  -- 3. Fallback to AppleScript with password prompt if sudo -n is not configured yet
  local appleScript = string.format([[do shell script %s with administrator privileges]], hs.inspect(shScript))
  local ok, res = hs.osascript.applescript(appleScript)
  return ok
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
    -- Outer background pill
    {
      type = "rectangle",
      action = "strokeAndFill",
      fillColor = { red = 0.08, green = 0.09, blue = 0.12, alpha = 0.94 },
      strokeColor = { red = 0.20, green = 0.85, blue = 0.55, alpha = 0.90 },
      strokeWidth = 1.4,
      roundedRectRadii = { xRadius = 18, yRadius = 18 },
    },
    -- Pulse dot indicator
    {
      type = "circle",
      action = "fill",
      fillColor = { red = 0.22, green = 0.90, blue = 0.55, alpha = 1.0 },
      center = { x = 18, y = 18 },
      radius = 4,
    },
    -- Label "STUDY"
    {
      type = "text",
      text = "STUDY",
      textColor = { red = 0.55, green = 0.65, blue = 0.60, alpha = 1.0 },
      textSize = 11,
      textFont = ".SFNS-Medium",
      frame = { x = 28, y = 10, w = 48, h = 18 },
    },
    -- Countdown text "45:00"
    {
      type = "text",
      text = "45:00",
      textAlignment = "right",
      textColor = { red = 0.92, green = 0.98, blue = 0.94, alpha = 1.0 },
      textSize = 14,
      textFont = ".SFNS-Bold",
      frame = { x = 68, y = 9, w = 56, h = 18 },
    }
  )

  -- Topmost window level floating over all websites and spaces
  overlay:level(hs.canvas.windowLevels.screenSaver)
  overlay:behavior({ "canJoinAllSpaces", "stationary", "ignoresCycle" })
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

local function finishStudyMode(showCompletionNotification)
  if not active then return end

  active = false
  deadline = nil
  stopTicker()
  hideOverlay()

  hs.settings.set(obj.settingsKey, nil)
  applyHostsBlock(false)

  if showCompletionNotification then
    hs.notify.new({
      title = "Study Mode complete! 🎉",
      informativeText = string.format("%d minutes finished. YouTube, Chess, & Gemini are unblocked.", math.floor(obj.duration / 60)),
      soundName = "Glass",
    }):send()
  else
    hs.alert.show("Study Mode ended")
  end
end

local function updateOverlay()
  if not active or not deadline then return end

  local seconds = remainingSeconds()
  ensureOverlay()
  if overlay then
    overlay:elementAttribute(4, "text", formatRemaining(seconds))
  end

  if seconds <= 0 then
    finishStudyMode(true)
  end
end

local function activateUntil(untilTime)
  active = true
  deadline = untilTime
  hs.settings.set(obj.settingsKey, deadline)

  stopTicker()
  ensureOverlay()
  ticker = hs.timer.doEvery(1, updateOverlay)
  updateOverlay()
end

--- StudyMode:start()
--- Starts a new Study Mode focus session.
function obj:start()
  if active then
    hs.alert.show("Study Mode active: " .. formatRemaining(remainingSeconds()) .. " remaining")
    return
  end

  local ok = applyHostsBlock(true)
  if not ok then
    hs.alert.show("Study Mode could not update /etc/hosts.", 5)
    return
  end

  activateUntil(hs.timer.secondsSinceEpoch() + obj.duration)
  hs.alert.show(
    string.format("Study Mode active (%d:00)\nYouTube, Chess, & Gemini blocked.", math.floor(obj.duration / 60)),
    3
  )
end

--- StudyMode:stop()
--- Manually stops an active Study Mode session.
function obj:stop()
  if not active then
    hs.alert.show("Study Mode is not active")
    return
  end
  finishStudyMode(false)
end

--- StudyMode:toggle()
--- Starts Study Mode if inactive, or shows remaining time if active.
function obj:toggle()
  if active then
    hs.alert.show("Study Mode active: " .. formatRemaining(remainingSeconds()) .. " remaining")
  else
    self:start()
  end
end

--- StudyMode:remaining()
--- Returns remaining seconds in current session.
function obj:remaining()
  return math.ceil(remainingSeconds())
end

--- StudyMode:bindHotkeys(mapping)
--- Example: spoon.StudyMode:bindHotkeys({ start = {{"cmd", "alt", "ctrl"}, "S"} })
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
  -- Key tap for fn + S
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
        hs.timer.doAfter(0, function() obj:start() end)
      end
      return true
    end)
    keyTapWatcher:start()
  end

  -- Screen watcher for multi-monitor / space changes
  if not screenWatcher then
    screenWatcher = hs.screen.watcher.new(function()
      if overlay then
        hs.timer.doAfter(0.1, positionOverlay)
      end
    end)
    screenWatcher:start()
  end

  -- Recovery on config reload
  local savedDeadline = hs.settings.get(obj.settingsKey)
  if type(savedDeadline) == "number" then
    if savedDeadline > hs.timer.secondsSinceEpoch() then
      applyHostsBlock(true)
      activateUntil(savedDeadline)
    else
      hs.settings.set(obj.settingsKey, nil)
      applyHostsBlock(false)
    end
  end

  return self
end

return obj
