--- === StudyMode ===
---
--- Focus mode Spoon for Hammerspoon.
--- Cycles between Study sessions (blocking sites) and Break sessions (unblocking sites).
--- Includes Daily 16:00 Study Session:
---   - Starts automatically every day at 16:00.
---   - 45m Study 1/2 -> 15m Break -> 45m Study 2/2 -> Finished (no second break).
--- Includes Hardcore Mode (activated by holding fn+S for 3 seconds):
---   - 40 min Study / 10 min Break
---   - Cannot be stopped manually (Console/Hotkey stop requests are denied)
---   - Automatically ends only after 5 consecutive study sessions complete.
--- Includes Daily German Focus Mode:
---   - Sits in the top-right corner as a "GERMAN" panel every day.
---   - Clicking it starts an untimed study session (sites blocked, no countdown timer).
---   - Only stops when explicitly typed in console: StudyMode.German:stop()
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "StudyMode"
obj.version = "3.6"
obj.author = "Ali Faisal Awada"
obj.homepage = "https://github.com/3alifaisal/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration
obj.studyDuration = 45 * 60         -- 45 minutes normal study
obj.breakDuration = 15 * 60         -- 15 minutes normal break
obj.hardcoreStudyDuration = 40 * 60 -- 40 minutes hardcore study
obj.hardcoreBreakDuration = 10 * 60 -- 10 minutes hardcore break (reduced from 20m)
obj.hardcoreTotalSessions = 5       -- 5 consecutive sessions
obj.inactivityTimeout = 3 * 60      -- 180 seconds (3 minutes) inactivity threshold
obj.enableInactivityAlarm = true    -- Enable inactivity alarm during standard study sessions

-- Daily 16:00 Study Session Configuration
obj.daily16Time = "16:00"           -- 16:00 daily
obj.enableDaily16 = true            -- Enable daily 16:00 session
obj.daily16StudyDuration = 45 * 60  -- 45 minutes
obj.daily16BreakDuration = 15 * 60  -- 15 minutes
obj.settingsKeyDaily16Session = "hammerspoon.studyMode.daily16Session"
obj.settingsKeyDaily16Step = "hammerspoon.studyMode.daily16Step"
obj.settingsKeyDaily16LastRunDate = "hammerspoon.studyMode.daily16LastRunDate"

-- German daily reminder configuration
obj.germanStartDate = "2026-10-17"
obj.settingsKeyGermanDoneDate = "hammerspoon.studyMode.germanDoneDate"
obj.settingsKeyGermanStartTime = "hammerspoon.studyMode.germanStartTime"

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
local mode = "INACTIVE" -- "STUDY", "BREAK", "ALARM", "GERMAN_PENDING", "GERMAN_STUDY", "INACTIVE"
local isHardcore = false
local currentSession = 1
local isDaily16Session = false
local daily16Step = 0 -- 1 = Study 1, 2 = Break, 3 = Study 2
local deadline = nil
local germanStartTime = nil
local ticker = nil
local alarmTimer = nil
local scheduleCheckTimer = nil
local sleepWakeWatcher = nil
local overlay = nil
local keyTapWatcher = nil
local screenWatcher = nil
local lastHotkeyTime = 0
local alarmSound = nil
local isIdleRinging = false

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

local function isGermanPending()
  local today = os.date("%Y-%m-%d")
  if today < obj.germanStartDate then
    return false
  end
  local lastDone = hs.settings.get(obj.settingsKeyGermanDoneDate)
  if lastDone == today then
    return false
  end
  return (mode == "INACTIVE" or mode == "GERMAN_PENDING")
end

-- Execute hosts edit asynchronously/safely without blocking UI
local function applyHostsBlock(enable)
  pcall(function()
    if hs.fs.attributes(obj.helperPath) then
      local cmd = enable and "on" or "off"
      local output, status, type, rc = hs.execute(string.format("/usr/bin/sudo -n %s %s", obj.helperPath, cmd), true)
      if status == true or rc == 0 then return end
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

-- Forward declarations
local handleAlarmClick
local startGermanStudy
local stopGerman
local checkGermanPrompt
local checkDaily16Schedule
local updateOverlayUI

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
    -- 3. Label ("STUDY" / "BREAK" / "GERMAN" / "🔥 1/5" / "📚 1/2")
    {
      type = "text",
      text = "STUDY",
      textColor = { red = 0.55, green = 0.65, blue = 0.60, alpha = 1.0 },
      textSize = 11,
      textFont = ".SFNS-Medium",
      frame = { x = 28, y = 10, w = 58, h = 18 },
    },
    -- 4. Timer / Action text ("45:00" / "START")
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
      if mode == "GERMAN_PENDING" then
        startGermanStudy()
      elseif mode == "GERMAN_STUDY" then
        local elapsed = germanStartTime and math.max(0, hs.timer.secondsSinceEpoch() - germanStartTime) or 0
        hs.alert.show(
          string.format("🇩🇪 German Study active (%s elapsed)\nNo timer. Sites blocked.\nTo stop, run in console:\nStudyMode.German:stop()", formatRemaining(elapsed)),
          4
        )
      elseif mode == "ALARM" then
        handleAlarmClick()
      elseif mode == "BREAK" then
        if isDaily16Session then
          hs.alert.show(string.format("☕ 16:00 Break active (%s left)\nStudy Session 2/2 will follow.", formatRemaining(remainingSeconds())))
        else
          local tag = isHardcore and string.format("🔥 Hardcore Break (%d/5)", currentSession) or "Break"
          hs.alert.show(tag .. " active (" .. formatRemaining(remainingSeconds()) .. " left)")
        end
      elseif mode == "STUDY" then
        if isDaily16Session then
          local stepNum = (daily16Step == 3 and 2 or 1)
          hs.alert.show(string.format("📚 16:00 Study (%d/2) active (%s left)", stepNum, formatRemaining(remainingSeconds())))
        else
          local tag = isHardcore and string.format("🔥 Hardcore Study (%d/5)", currentSession) or "Study"
          hs.alert.show(tag .. " active (" .. formatRemaining(remainingSeconds()) .. " left)")
        end
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

updateOverlayUI = function()
  ensureOverlay()
  if not overlay then return end

  if mode == "GERMAN_PENDING" then
    overlay:elementAttribute(1, "strokeColor", { red = 0.95, green = 0.75, blue = 0.20, alpha = 0.95 })
    overlay:elementAttribute(2, "fillColor", { red = 0.95, green = 0.75, blue = 0.20, alpha = 1.0 })
    overlay:elementAttribute(3, "text", "GERMAN")
    overlay:elementAttribute(3, "textColor", { red = 0.95, green = 0.85, blue = 0.40, alpha = 1.0 })
    overlay:elementAttribute(4, "text", "START")
    overlay:elementAttribute(4, "textColor", { red = 1.00, green = 1.00, blue = 1.00, alpha = 0.95 })

  elseif mode == "GERMAN_STUDY" then
    local elapsed = germanStartTime and math.max(0, hs.timer.secondsSinceEpoch() - germanStartTime) or 0
    overlay:elementAttribute(1, "strokeColor", { red = 0.95, green = 0.75, blue = 0.20, alpha = 0.95 })
    overlay:elementAttribute(2, "fillColor", { red = 0.95, green = 0.75, blue = 0.20, alpha = 1.0 })
    overlay:elementAttribute(3, "text", "GERMAN")
    overlay:elementAttribute(3, "textColor", { red = 0.95, green = 0.85, blue = 0.40, alpha = 1.0 })
    overlay:elementAttribute(4, "text", formatRemaining(elapsed))
    overlay:elementAttribute(4, "textColor", { red = 0.92, green = 0.98, blue = 0.94, alpha = 1.0 })

  elseif mode == "STUDY" then
    if isDaily16Session then
      overlay:elementAttribute(1, "strokeColor", { red = 0.20, green = 0.70, blue = 0.95, alpha = 0.90 })
      overlay:elementAttribute(2, "fillColor", { red = 0.30, green = 0.80, blue = 1.00, alpha = 1.0 })
      overlay:elementAttribute(3, "text", string.format("📚 %d/2", daily16Step == 3 and 2 or 1))
      overlay:elementAttribute(3, "textColor", { red = 0.40, green = 0.85, blue = 1.00, alpha = 1.0 })
    elseif isHardcore then
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
    overlay:elementAttribute(4, "textColor", { red = 0.92, green = 0.98, blue = 0.94, alpha = 1.0 })

  elseif mode == "BREAK" then
    if isDaily16Session then
      overlay:elementAttribute(1, "strokeColor", { red = 0.95, green = 0.65, blue = 0.20, alpha = 0.90 })
      overlay:elementAttribute(2, "fillColor", { red = 0.98, green = 0.70, blue = 0.25, alpha = 1.0 })
      overlay:elementAttribute(3, "text", "☕ 1/2")
      overlay:elementAttribute(3, "textColor", { red = 0.90, green = 0.75, blue = 0.50, alpha = 1.0 })
    elseif isHardcore then
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
    overlay:elementAttribute(4, "textColor", { red = 0.92, green = 0.98, blue = 0.94, alpha = 1.0 })

  elseif mode == "ALARM" then
    overlay:elementAttribute(1, "strokeColor", { red = 1.00, green = 0.30, blue = 0.30, alpha = 1.0 })
    overlay:elementAttribute(2, "fillColor", { red = 1.00, green = 0.35, blue = 0.35, alpha = 1.0 })
    if isDaily16Session then
      overlay:elementAttribute(3, "text", "🔔 2/2")
    elseif isHardcore then
      overlay:elementAttribute(3, "text", string.format("🔔 %d/%d", currentSession, obj.hardcoreTotalSessions))
    else
      overlay:elementAttribute(3, "text", "🔔 START")
    end
    overlay:elementAttribute(3, "textColor", { red = 1.00, green = 0.50, blue = 0.50, alpha = 1.0 })
    overlay:elementAttribute(4, "text", "STUDY")
    overlay:elementAttribute(4, "textColor", { red = 0.92, green = 0.98, blue = 0.94, alpha = 1.0 })
  end
end

local function saveState()
  hs.settings.set(obj.settingsKeyMode, mode)
  hs.settings.set(obj.settingsKeyDeadline, deadline)
  hs.settings.set(obj.settingsKeyHardcore, isHardcore)
  hs.settings.set(obj.settingsKeySessionCount, currentSession)
  hs.settings.set(obj.settingsKeyGermanStartTime, germanStartTime)
  hs.settings.set(obj.settingsKeyDaily16Session, isDaily16Session)
  hs.settings.set(obj.settingsKeyDaily16Step, daily16Step)
end

checkGermanPrompt = function()
  if mode == "INACTIVE" or mode == "GERMAN_PENDING" then
    if isGermanPending() then
      mode = "GERMAN_PENDING"
      ensureOverlay()
      updateOverlayUI()
    else
      if mode == "GERMAN_PENDING" then
        mode = "INACTIVE"
      end
      hideOverlay()
    end
  end
end

checkDaily16Schedule = function()
  if not obj.enableDaily16 then return end
  local now = os.date("*t")
  local today = string.format("%04d-%02d-%02d", now.year, now.month, now.day)
  local lastRunDate = hs.settings.get(obj.settingsKeyDaily16LastRunDate)

  if lastRunDate == today then return end

  local targetHour, targetMin = obj.daily16Time:match("^(%d+):(%d+)$")
  targetHour = tonumber(targetHour) or 16
  targetMin = tonumber(targetMin) or 0

  -- Only trigger if within the target window (16:00 to 16:05)
  if now.hour == targetHour and now.min >= targetMin and now.min <= (targetMin + 5) then
    hs.settings.set(obj.settingsKeyDaily16LastRunDate, today)
    if mode == "INACTIVE" or mode == "GERMAN_PENDING" then
      obj:startDaily16Session()
    elseif mode == "GERMAN_STUDY" then
      -- User is currently studying German; do not interrupt and do not trigger late!
      hs.notify.new({
        title = "📚 16:00 Study Block",
        informativeText = "It is 16:00, but German study is currently active. 16:00 session will not interrupt.",
        soundName = "Glass",
      }):send()
    else
      hs.notify.new({
        title = "📚 16:00 Study Reminder",
        informativeText = string.format("It is 16:00! Currently in %s mode. Finish or stop to start the 16:00 session.", mode),
        soundName = "Glass",
      }):send()
    end
  elseif now.hour > targetHour or (now.hour == targetHour and now.min > (targetMin + 5)) then
    -- Current time is past the target window (e.g. 23:00 after waking up).
    -- Mark today so it NEVER triggers late at 23:00!
    if lastRunDate ~= today then
      hs.settings.set(obj.settingsKeyDaily16LastRunDate, today)
      print(string.format("[StudyMode] 16:00 window passed for today (current time %02d:%02d). Skipping.", now.hour, now.min))
    end
  end
end

-- Forward declarations of phase functions
local startBreakPhase
local startAlarmPhase
local startStudyPhase

local function updateLoop()
  if mode == "GERMAN_STUDY" then
    updateOverlayUI()
  elseif mode == "STUDY" or mode == "BREAK" then
    local seconds = remainingSeconds()
    updateOverlayUI()

    -- Inactivity detection during normal STUDY phase (no mouse/key/scroll input for 3 mins)
    if mode == "STUDY" and obj.enableInactivityAlarm then
      local idleSecs = hs.host.idleTime()
      if idleSecs >= obj.inactivityTimeout then
        if not isIdleRinging then
          isIdleRinging = true
          playCrystalsRing()
          hs.alert.show("⚠️ INACTIVITY DETECTED!\nNo input for 3 mins — back to studying!", 4)
        end
      else
        if isIdleRinging then
          isIdleRinging = false
          stopAlarmSound()
        end
      end
    end

    if seconds <= 0 then
      if isIdleRinging then
        isIdleRinging = false
        stopAlarmSound()
      end

      if mode == "STUDY" then
        if isDaily16Session and daily16Step == 3 then
          -- Second 45-minute study session completed! No second break. Stops cleanly.
          isDaily16Session = false
          daily16Step = 0
          mode = "INACTIVE"
          deadline = nil
          stopTicker()
          stopAlarmSound()
          saveState()

          hs.timer.doAfter(0.01, function()
            applyHostsBlock(false)
          end)

          hs.notify.new({
            title = "🎉 16:00 Study Session Complete! 🏆",
            informativeText = "Both 45-minute study sessions finished! No second break needed. Great work!",
            soundName = "Glass",
          }):send()

          hs.alert.show("🎉 16:00 STUDY SESSION COMPLETE!\nBoth 45-min sessions finished. Sites unblocked.", 5)
          checkGermanPrompt()
        else
          if isDaily16Session and daily16Step == 1 then
            daily16Step = 2
            saveState()
          end
          startBreakPhase()
        end
      elseif mode == "BREAK" then
        startAlarmPhase()
      end
    end
  end
end

startGermanStudy = function()
  stopAlarmSound()
  stopTicker()

  mode = "GERMAN_STUDY"
  germanStartTime = hs.timer.secondsSinceEpoch()
  deadline = nil -- Untimed study session!
  saveState()

  ensureOverlay()
  updateOverlayUI()

  ticker = hs.timer.doEvery(1, updateLoop)

  hs.timer.doAfter(0.01, function()
    applyHostsBlock(true)
  end)

  hs.alert.show(
    "🇩🇪 GERMAN STUDY ACTIVE\nSites blocked. No timer.\nTo stop, run in console:\nStudyMode.German:stop()",
    5
  )
end

stopGerman = function()
  if mode ~= "GERMAN_STUDY" and mode ~= "GERMAN_PENDING" then
    hs.alert.show("German Study is not active")
    return
  end

  mode = "INACTIVE"
  deadline = nil
  germanStartTime = nil
  stopTicker()
  stopAlarmSound()

  local today = os.date("%Y-%m-%d")
  hs.settings.set(obj.settingsKeyGermanDoneDate, today)
  hs.settings.set(obj.settingsKeyGermanStartTime, nil)
  hs.settings.set(obj.settingsKeyMode, nil)
  hs.settings.set(obj.settingsKeyDeadline, nil)

  hideOverlay()

  hs.timer.doAfter(0.01, function()
    applyHostsBlock(false)
  end)

  hs.alert.show("🇩🇪 German Study session stopped!\nGreat work! Sites unblocked.", 4)
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
        informativeText = "5 consecutive study sessions finished on its own! Incredible job!",
        soundName = "Glass",
      }):send()

      hs.alert.show("🎉 HARDCORE MODE COMPLETE!\nAll 5 sessions finished on its own!", 5)
      checkGermanPrompt()
    end
  elseif isDaily16Session and daily16Step == 2 then
    -- Transitioning from Break to Study 2/2
    daily16Step = 3
    saveState()
    startStudyPhase()
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

  local infoText
  if isDaily16Session then
    infoText = "Break over! Click timer or press fn+S to start Study Session 2/2."
  elseif isHardcore then
    infoText = string.format("Hardcore Session %d/%d break over! Click timer or press fn+S to start next session.", currentSession, obj.hardcoreTotalSessions)
  else
    infoText = "Click the top-right timer or press fn+S to start your next 45-minute study session."
  end

  hs.notify.new({
    title = "Break is over! 🔔",
    informativeText = infoText,
    soundName = "Crystals",
  }):send()
end

startBreakPhase = function()
  mode = "BREAK"
  local breakDur
  if isDaily16Session then
    breakDur = obj.daily16BreakDuration
  elseif isHardcore then
    breakDur = obj.hardcoreBreakDuration
  else
    breakDur = obj.breakDuration
  end

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

  local breakMinutes = math.floor(breakDur / 60)
  local breakMsg
  local notifyTitle
  local notifyText

  if isDaily16Session then
    breakMsg = string.format("%d-Minute Break started ☕\nSites unblocked. Study 2/2 will follow.", breakMinutes)
    notifyTitle = "45-Minute Study Session 1/2 Complete! ☕"
    notifyText = string.format("%d-minute break started. YouTube & Chess are available.", breakMinutes)
  elseif isHardcore then
    breakMsg = string.format("%d-Minute Break started (Session %d/%d) ☕\nSites unblocked.", breakMinutes, currentSession, obj.hardcoreTotalSessions)
    notifyTitle = string.format("🔥 Hardcore Session %d/%d Complete! ☕", currentSession, obj.hardcoreTotalSessions)
    notifyText = string.format("%d-minute break started. YouTube & Chess are available.", breakMinutes)
  else
    breakMsg = string.format("%d-Minute Break started ☕\nSites unblocked.", breakMinutes)
    notifyTitle = "45-Minute Study Session Complete! ☕"
    notifyText = string.format("%d-minute break started. YouTube & Chess are available.", breakMinutes)
  end

  hs.notify.new({
    title = notifyTitle,
    informativeText = notifyText,
    soundName = "Glass",
  }):send()

  hs.alert.show(breakMsg, 3)
end

startStudyPhase = function()
  stopAlarmSound()

  mode = "STUDY"
  local studyDur
  if isDaily16Session then
    studyDur = obj.daily16StudyDuration
  elseif isHardcore then
    studyDur = obj.hardcoreStudyDuration
  else
    studyDur = obj.studyDuration
  end

  deadline = hs.timer.secondsSinceEpoch() + studyDur
  saveState()

  ensureOverlay()
  updateOverlayUI()

  stopTicker()
  ticker = hs.timer.doEvery(1, updateLoop)

  hs.timer.doAfter(0.01, function()
    applyHostsBlock(true)
  end)

  local studyMinutes = math.floor(studyDur / 60)
  local alertMsg

  if isDaily16Session then
    local stepNum = (daily16Step == 3 and 2 or 1)
    alertMsg = string.format("📚 16:00 Study Session (%d/2) (%d:00)\nYouTube & Chess blocked.", stepNum, studyMinutes)
  elseif isHardcore then
    alertMsg = string.format("🔥 HARDCORE MODE: Session %d/%d (%d:00)\nYouTube & Chess blocked.", currentSession, obj.hardcoreTotalSessions, studyMinutes)
  else
    alertMsg = string.format("Study Session active (%d:00)\nYouTube & Chess blocked.", studyMinutes)
  end

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

--- StudyMode:startDaily16Session()
--- Starts the 16:00 two-phase study session (45m study -> 15m break -> 45m study -> stop).
function obj:startDaily16Session()
  if isHardcore then
    hs.alert.show("🔥 Hardcore Mode is active. Complete it first!", 4)
    return
  end
  if mode == "GERMAN_STUDY" then
    hs.alert.show("🇩🇪 German Study is active. Stop it first via StudyMode.German:stop()", 4)
    return
  end

  stopTicker()
  stopAlarmSound()

  isDaily16Session = true
  daily16Step = 1
  saveState()

  hs.notify.new({
    title = "📚 16:00 Study Session Started! 🎯",
    informativeText = "45m Study (1/2) -> 15m Break -> 45m Study (2/2). No second break.",
    soundName = "Hero",
  }):send()

  startStudyPhase()
end

--- StudyMode:activateHardcoreMode()
--- Activates Hardcore Mode: 5 consecutive sessions (40m Study / 10m Break), non-removable.
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

  isDaily16Session = false
  daily16Step = 0
  isHardcore = true
  currentSession = 1
  saveState()

  hs.notify.new({
    title = "🔥 HARDCORE MODE ACTIVATED!",
    informativeText = string.format("5 consecutive sessions (%dm Study / %dm Break).\nCANNOT be stopped manually!", math.floor(obj.hardcoreStudyDuration / 60), math.floor(obj.hardcoreBreakDuration / 60)),
    soundName = "Hero",
  }):send()

  hs.alert.show(
    string.format("🔥 HARDCORE MODE ACTIVATED!\nOverriding Study Mode!\n5 Sessions: %dm Study / %dm Break\nCANNOT BE STOPPED MANUALLY.", math.floor(obj.hardcoreStudyDuration / 60), math.floor(obj.hardcoreBreakDuration / 60)),
    5
  )

  startStudyPhase()
end

--- StudyMode:start()
function obj:start()
  if mode == "GERMAN_PENDING" then
    startGermanStudy()
  elseif mode == "GERMAN_STUDY" then
    local elapsed = germanStartTime and math.max(0, hs.timer.secondsSinceEpoch() - germanStartTime) or 0
    hs.alert.show(string.format("🇩🇪 German Study active (%s elapsed)\nStop with: StudyMode.German:stop()", formatRemaining(elapsed)))
  elseif mode == "ALARM" then
    handleAlarmClick()
  elseif mode == "STUDY" then
    if isDaily16Session then
      local stepNum = (daily16Step == 3 and 2 or 1)
      hs.alert.show(string.format("📚 16:00 Study (%d/2) active: %s remaining", stepNum, formatRemaining(remainingSeconds())))
    else
      local tag = isHardcore and string.format("🔥 Hardcore Session %d/%d", currentSession, obj.hardcoreTotalSessions) or "Study Session"
      hs.alert.show(tag .. " active: " .. formatRemaining(remainingSeconds()) .. " remaining")
    end
  elseif mode == "BREAK" then
    if isDaily16Session then
      hs.alert.show(string.format("☕ 16:00 Break active: %s remaining", formatRemaining(remainingSeconds())))
    else
      local tag = isHardcore and string.format("🔥 Hardcore Break %d/%d", currentSession, obj.hardcoreTotalSessions) or "Break"
      hs.alert.show(tag .. " active: " .. formatRemaining(remainingSeconds()) .. " remaining")
    end
  else
    startStudyPhase()
  end
end

--- StudyMode:stop()
--- Normal stop request. Denied during Hardcore Mode and German Study (unless force is true).
function obj.stop(...)
  local args = { ... }
  local force = false
  for _, a in ipairs(args) do
    if a == true then force = true end
  end

  if isHardcore and not force then
    hs.alert.show(
      string.format("🔥 HARDCORE MODE IS ACTIVE (%d/%d)\nTo emergency stop, run:\nStudyMode:forceStop()", currentSession, obj.hardcoreTotalSessions),
      5
    )
    print("🔥 Hardcore Mode is active. Run StudyMode:forceStop() to override.")
    return false
  end

  if mode == "GERMAN_STUDY" and not force then
    hs.alert.show("🇩🇪 GERMAN STUDY IS ACTIVE!\nTo stop, run in console:\nStudyMode.German:stop()", 4)
    print("🇩🇪 German Study is active. Use StudyMode.German:stop() to stop.")
    return false
  end

  if mode == "INACTIVE" and not isGermanPending() and not force then
    hs.alert.show("Study Mode is not active")
    return
  end

  mode = "INACTIVE"
  deadline = nil
  isDaily16Session = false
  daily16Step = 0
  if force then
    isHardcore = false
    germanStartTime = nil
  end
  stopTicker()
  stopAlarmSound()

  hs.settings.set(obj.settingsKeyMode, nil)
  hs.settings.set(obj.settingsKeyDeadline, nil)
  hs.settings.set(obj.settingsKeyHardcore, nil)
  hs.settings.set(obj.settingsKeySessionCount, nil)
  hs.settings.set(obj.settingsKeyDaily16Session, nil)
  hs.settings.set(obj.settingsKeyDaily16Step, nil)
  if force then
    hs.settings.set(obj.settingsKeyGermanStartTime, nil)
  end

  hs.timer.doAfter(0.01, function()
    applyHostsBlock(false)
  end)

  checkGermanPrompt()
  hs.alert.show("Study Mode stopped")
  return true
end

--- StudyMode:forceStop()
--- Emergency stop for Hardcore Mode and any active study sessions.
function obj.forceStop(...)
  return obj.stop(true)
end

obj.emergencyStop = obj.forceStop

--- StudyMode:toggle()
function obj:toggle()
  if mode == "GERMAN_STUDY" then
    local elapsed = germanStartTime and math.max(0, hs.timer.secondsSinceEpoch() - germanStartTime) or 0
    hs.alert.show(string.format("🇩🇪 German Study active (%s elapsed)\nStop with: StudyMode.German:stop()", formatRemaining(elapsed)))
  elseif mode == "ALARM" then
    handleAlarmClick()
  elseif mode == "INACTIVE" or mode == "GERMAN_PENDING" then
    startStudyPhase()
  else
    local tag
    if isDaily16Session then
      local stepNum = (daily16Step == 3 and 2 or 1)
      tag = string.format("📚 16:00 %s (%d/2)", mode, stepNum)
    elseif isHardcore then
      tag = string.format("🔥 Hardcore %s (%d/%d)", mode, currentSession, obj.hardcoreTotalSessions)
    else
      tag = mode
    end
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

-- =========================================================================
-- German Study Mode API & Console Commands
-- Supports:
--   StudyMode.German:stop()
--   StudyMode.German.stop()
--   StudyMode:germanStop()
--   StudyMode:GermanStop()
--   StudyMode:stopGerman()
-- =========================================================================

obj.German = {}
setmetatable(obj.German, {
  __call = function(t, ...)
    return t
  end,
  __index = function(t, k)
    if k == "stop" then
      return function(...) return stopGerman() end
    elseif k == "start" then
      return function(...) return startGermanStudy() end
    elseif k == "reset" then
      return function(...) return obj.German:reset() end
    end
  end
})

function obj.German:stop()
  return stopGerman()
end

function obj.German:start()
  return startGermanStudy()
end

function obj.German:reset()
  hs.settings.set(obj.settingsKeyGermanDoneDate, nil)
  checkGermanPrompt()
  hs.alert.show("🇩🇪 German daily completion reset!", 3)
end

function obj.German:enableToday()
  obj.germanStartDate = os.date("%Y-%m-%d")
  hs.settings.set(obj.settingsKeyGermanDoneDate, nil)
  checkGermanPrompt()
  hs.alert.show("🇩🇪 German panel enabled for today!", 3)
end

function obj.German:skip()
  local today = os.date("%Y-%m-%d")
  hs.settings.set(obj.settingsKeyGermanDoneDate, today)
  if mode == "GERMAN_STUDY" or mode == "GERMAN_PENDING" then
    stopGerman()
    hs.alert.show("🇩🇪 German session skipped for today!", 3)
  else
    checkGermanPrompt()
    hs.alert.show("🇩🇪 German session skipped for today!", 3)
  end
  return true
end

function obj:startGerman()
  startGermanStudy()
end

function obj:stopGerman()
  stopGerman()
end

obj.germanStop = function(self) return stopGerman() end
obj.germanStart = function(self) return startGermanStudy() end
obj.GermanStop = function(self) return stopGerman() end
obj.skipGerman = function(...) return obj.German:skip(...) end

--- StudyMode:skipDaily16()
--- Skips today's 16:00 session. If already running, stops it immediately.
function obj.skipDaily16(...)
  local today = os.date("%Y-%m-%d")
  hs.settings.set(obj.settingsKeyDaily16LastRunDate, today)

  if isDaily16Session or mode == "STUDY" or mode == "BREAK" then
    obj.stop(true)
    hs.alert.show("📚 16:00 Study session skipped for today!\nSites unblocked.", 4)
  else
    hs.alert.show("📚 16:00 Study session skipped for today!\nWill not start at 16:00.", 4)
  end
  return true
end

obj.skip16 = obj.skipDaily16
obj.skip = obj.skipDaily16

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

  -- Sleep / Wake watcher to handle schedule accurately across Mac sleeps
  if sleepWakeWatcher then
    sleepWakeWatcher:stop()
    sleepWakeWatcher = nil
  end
  sleepWakeWatcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake or event == hs.caffeinate.watcher.screensDidUnlock then
      checkDaily16Schedule()
      checkGermanPrompt()
    end
  end)
  sleepWakeWatcher:start()

  -- Periodic check (every 20s) for German panel and 16:00 schedule
  if scheduleCheckTimer then
    scheduleCheckTimer:stop()
    scheduleCheckTimer = nil
  end
  scheduleCheckTimer = hs.timer.doEvery(20, function()
    checkDaily16Schedule()
    checkGermanPrompt()
  end)

  -- Run check immediately on init
  checkDaily16Schedule()

  -- Recovery on config reload / restart
  local savedMode = hs.settings.get(obj.settingsKeyMode)
  local savedDeadline = hs.settings.get(obj.settingsKeyDeadline)
  local savedHardcore = hs.settings.get(obj.settingsKeyHardcore)
  local savedCount = hs.settings.get(obj.settingsKeySessionCount)
  local savedGermanStart = hs.settings.get(obj.settingsKeyGermanStartTime)
  local savedDaily16 = hs.settings.get(obj.settingsKeyDaily16Session)
  local savedDaily16Step = hs.settings.get(obj.settingsKeyDaily16Step)

  if savedHardcore == true then
    isHardcore = true
    currentSession = type(savedCount) == "number" and savedCount or 1
  end

  if savedDaily16 == true then
    isDaily16Session = true
    daily16Step = type(savedDaily16Step) == "number" and savedDaily16Step or 1
  end

  if savedMode == "GERMAN_STUDY" then
    mode = "GERMAN_STUDY"
    germanStartTime = savedGermanStart or hs.timer.secondsSinceEpoch()
    ensureOverlay()
    updateOverlayUI()
    stopTicker()
    ticker = hs.timer.doEvery(1, updateLoop)
    hs.timer.doAfter(0.01, function() applyHostsBlock(true) end)
  elseif savedMode == "STUDY" and type(savedDeadline) == "number" then
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
  else
    -- INACTIVE state: check if German pending panel should sit in the corner
    checkGermanPrompt()
  end

  _G.StudyMode = obj
  _G.studymode = obj

  return self
end

_G.StudyMode = obj
_G.studymode = obj

return obj
