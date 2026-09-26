--- === GermanStudyReminder ===
---
--- Daily German Study Reminder Spoon for Hammerspoon.
--- Schedules a daily alarm at 23:00 to learn German.
--- Rings the 'Crystals' alarm at 23:00 and displays "🇩🇪 ZEIT FÜR DEUTSCH!".
--- Clicking the timer or pressing hotkey starts a 45-minute German study session (blocking YouTube & Chess).
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "GermanStudyReminder"
obj.version = "1.0"
obj.author = "Ali Faisal Awada"
obj.homepage = "https://github.com/3alifaisal/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration
obj.reminderTime = "23:00" -- 11:00 PM daily
obj.studyDuration = 45 * 60 -- 45 minutes
obj.soundFile = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/Crystals.m4r"
obj.defaultHotkey = { { "cmd", "alt", "ctrl" }, "G" }

-- Internal state
local dailyTimer = nil

--- GermanStudyReminder:trigger()
--- Immediately triggers the German Study alarm.
function obj:trigger()
  hs.notify.new({
    title = "🇩🇪 ZEIT FÜR DEUTSCH!",
    informativeText = "It is 23:00! Time to start your 45-minute German study session.",
    soundName = "Crystals",
  }):send()

  hs.alert.show("🇩🇪 ZEIT FÜR DEUTSCH!\nTime for German Study Session!", 4)

  if spoon.StudyMode then
    spoon.StudyMode:startAlarmPhase()
  else
    local studyMode = hs.loadSpoon("StudyMode")
    if studyMode then
      studyMode:init()
      studyMode:startAlarmPhase()
    end
  end
end

--- GermanStudyReminder:bindHotkeys(mapping)
function obj:bindHotkeys(mapping)
  local spec = {
    trigger = hs.fnutils.partial(self.trigger, self),
  }
  hs.spoons.bindHotkeysToSpec(spec, mapping)
  return self
end

--- GermanStudyReminder:init()
--- Schedules the daily 23:00 timer.
function obj:init()
  if dailyTimer then
    dailyTimer:stop()
    dailyTimer = nil
  end

  dailyTimer = hs.timer.doAt(obj.reminderTime, "1d", function()
    obj:trigger()
  end)

  print(string.format("[GermanStudyReminder] Daily reminder scheduled for %s.", obj.reminderTime))
  return self
end

return obj
