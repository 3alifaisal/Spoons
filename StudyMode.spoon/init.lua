--- === StudyMode ===
---
--- Focus mode Spoon for Hammerspoon.
--- Starts a non-resettable focus session with a floating canvas countdown timer,
--- and blocks distracting websites (YouTube, Chess, Gemini AI) via a system hosts helper.
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "StudyMode"
obj.version = "1.0"
obj.author = "Ali Faisal Awada"
obj.homepage = "https://github.com/3alifaisal/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration
obj.duration = 45 * 60 -- 45 minutes default
obj.helperPath = "/Library/HammerspoonStudyMode/study-mode-hosts"
obj.settingsKey = "hammerspoon.studyMode.deadline"
obj.overlayWidth = 188
obj.overlayHeight = 56
obj.screenMargin = 16
obj.defaultHotkey = { { "cmd", "alt", "ctrl" }, "S" }

-- Internal state
local active = false
local pending = false
local deadline = nil
local ticker = nil
local overlay = nil
local helperTask = nil
local cleanupRetry = nil
local lastHotkeyTime = 0
local keyTapWatcher = nil
local screenWatcher = nil

local function trim(text)
  return (text or ""):gsub("%s+$", "")
end

local function formatRemaining(totalSeconds)
  local seconds = math.max(0, math.ceil(totalSeconds))
  return string.format("STUDY  %02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function remainingSeconds()
  if not active or not deadline then return 0 end
  return math.max(0, deadline - hs.timer.secondsSinceEpoch())
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
    {
      type = "rectangle",
      action = "strokeAndFill",
      fillColor = { red = 0.055, green = 0.071, blue = 0.063, alpha = 0.94 },
      strokeColor = { red = 0.30, green = 0.86, blue = 0.56, alpha = 0.90 },
      strokeWidth = 1.2,
      roundedRectRadii = { xRadius = 14, yRadius = 14 },
    },
    {
      type = "text",
      text = "STUDY  45:00",
      textAlignment = "center",
      textColor = { red = 0.88, green = 1.00, blue = 0.92, alpha = 1.0 },
      textSize = 20,
      frame = { x = 8, y = 15, w = obj.overlayWidth - 16, h = 30 },
    }
  )
  overlay:level("status")
  overlay:behavior({ "canJoinAllSpaces", "stationary" })
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

local function runHelper(action, callback)
  if helperTask and helperTask:isRunning() then
    callback(false, "The site-blocking helper is busy.")
    return
  end

  if not hs.fs.attributes(obj.helperPath) then
    callback(
      false,
      "Missing helper at " .. obj.helperPath .. ".\nRun the installer script: ~/.hammerspoon/Spoons/StudyMode.spoon/install.sh"
    )
    return
  end

  local ok, task = pcall(function()
    return hs.task.new(
      "/usr/bin/sudo",
      function(exitCode, stdOut, stdErr)
        helperTask = nil
        local message = trim((stdErr and stdErr ~= "") and stdErr or stdOut)
        callback(exitCode == 0, message)
      end,
      nil,
      { "-n", obj.helperPath, action }
    )
  end)

  if not ok or not task or not task:start() then
    helperTask = nil
    callback(false, "Could not launch the site-blocking helper.")
  else
    helperTask = task
  end
end

local function unblockWithRetry(attempt, callback)
  runHelper("off", function(ok, message)
    if ok then
      hs.settings.set(obj.settingsKey, nil)
      callback(true, "")
      return
    end

    if attempt < 3 then
      cleanupRetry = hs.timer.doAfter(attempt * 2, function()
        cleanupRetry = nil
        unblockWithRetry(attempt + 1, callback)
      end)
    else
      callback(false, message)
    end
  end)
end

local function finishStudyMode(showCompletionNotification)
  if not active or pending then return end

  active = false
  pending = true
  deadline = nil
  stopTicker()
  hideOverlay()

  hs.settings.set(obj.settingsKey, hs.timer.secondsSinceEpoch() - 1)

  unblockWithRetry(1, function(ok, message)
    pending = false
    if ok then
      if showCompletionNotification then
        hs.notify.new({
          title = "Study Mode complete! 🎉",
          informativeText = string.format("%d minutes finished. YouTube, Chess, & Gemini are available again.", math.floor(obj.duration / 60)),
          soundName = "Glass",
        }):send()
      else
        hs.alert.show("Study Mode ended")
      end
    else
      hs.alert.show(
        "Timer ended, but the site block could not be removed.\nRun in Terminal: sudo " .. obj.helperPath .. " off\n" .. message,
        8
      )
    end
  end)
end

local function updateOverlay()
  if not active or not deadline then return end

  local seconds = remainingSeconds()
  ensureOverlay()
  if overlay then
    overlay:elementAttribute(2, "text", formatRemaining(seconds))
  end

  if seconds <= 0 then
    finishStudyMode(true)
  end
end

local function activateUntil(untilTime)
  active = true
  pending = false
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
  if pending then
    hs.alert.show("Study Mode is updating website blocking…")
    return
  end

  if active then
    hs.alert.show(formatRemaining(remainingSeconds()) .. " remaining")
    return
  end

  pending = true
  hs.alert.show("Starting Study Mode…")

  runHelper("on", function(ok, message)
    if not ok then
      pending = false
      hs.alert.show("Study Mode could not start.\n" .. message, 7)
      return
    end

    activateUntil(hs.timer.secondsSinceEpoch() + obj.duration)
    hs.alert.show(
      string.format("Study Mode active (%d:00)\nYouTube, Chess, & Gemini blocked.", math.floor(obj.duration / 60)),
      3
    )
  end)
end

--- StudyMode:stop()
--- Manually stops an active Study Mode session (Console/Emergency Hatch).
function obj:stop()
  if pending then
    hs.alert.show("Study Mode is updating website blocking…")
    return
  end
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
    hs.alert.show(formatRemaining(remainingSeconds()) .. " remaining")
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
--- Binds hotkeys for StudyMode.
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
--- Initializes the Spoon and sets up screen watchers & key tap handlers.
function obj:init()
  -- Event tap handler for fn + S
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

  -- Screen watcher for multi-monitor layout changes
  if not screenWatcher then
    screenWatcher = hs.screen.watcher.new(function()
      if overlay then
        hs.timer.doAfter(0.1, positionOverlay)
      end
    end)
    screenWatcher:start()
  end

  -- Recovery after Hammerspoon config reload
  local savedDeadline = hs.settings.get(obj.settingsKey)
  if type(savedDeadline) == "number" then
    if savedDeadline > hs.timer.secondsSinceEpoch() then
      pending = true
      runHelper("on", function(ok, message)
        if ok then
          activateUntil(savedDeadline)
        else
          pending = false
          hs.alert.show("Study Mode recovery failed.\n" .. message, 7)
        end
      end)
    else
      pending = true
      unblockWithRetry(1, function(ok, message)
        pending = false
        if not ok then
          hs.alert.show("Could not clean up expired Study Mode block.\n" .. message, 7)
        end
      end)
    end
  end

  return self
end

return obj
