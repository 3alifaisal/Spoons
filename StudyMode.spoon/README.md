# 🎯 StudyMode.spoon

> An automated Pomodoro focus Spoon for Hammerspoon that cycles between Study sessions (blocking YouTube and Chess) and Break sessions (unblocking sites). Includes **📅 Daily 16:00 Study Sessions**, **🔥 Hardcore Mode**, **⚠️ Inactivity Detection**, and **🇩🇪 Daily German Focus Mode**.

---

## 🔄 How the Cycles Work

### 1. Standard Mode (`fn + S` Short Press)
- 📚 **45-Minute Study**: YouTube & Chess **BLOCKED**. HUD: `[ 🟢 STUDY  44:59 ]`.
- ☕ **15-Minute Break**: YouTube & Chess **UNBLOCKED**. HUD: `[ ☕ BREAK  14:59 ]`.
- 🔔 **Break Over Alarm**: Rings macOS **Crystals** sound continuously until clicked or `fn + S` pressed.

---

### 2. 📅 Daily 16:00 Study Block (Two 45m Sessions + 1 Break)
Starts automatically every day at **16:00 (4:00 PM)**:
- 📚 **Part 1 (45 mins)**: YouTube & Chess **BLOCKED**. HUD: `[ 📚 1/2  44:59 ]`.
- ☕ **Break (15 mins)**: YouTube & Chess **UNBLOCKED**. HUD: `[ ☕ 1/2  14:59 ]`. Rings Crystals when finished.
- 📚 **Part 2 (45 mins)**: YouTube & Chess **BLOCKED**. HUD: `[ 📚 2/2  44:59 ]`.
- 🏁 **Automatic Finish**: When the second 45-minute session is done, it **stops automatically** (no second break needed). Sites are unblocked.

---

### 3. 🇩🇪 Daily German Focus Mode (Corner Panel)
Starting every day, the top-right corner panel sits showing: `[ 🇩🇪 GERMAN  START ]`.

- 🖱️ **One-Click Start**: Click the panel to immediately switch to Study Mode.
- ⏳ **No Timer / Untimed**: Websites (YouTube & Chess) are blocked with **no countdown timer**, allowing open-ended focus.
- 🔒 **Console Stop Command Only**: It will not stop on its own or via normal hotkeys. To stop and unblock sites, run this command in the Hammerspoon console:
  ```lua
  StudyMode.German:stop()
  ```
  *(or `spoon.StudyMode.German:stop()` / `StudyMode:germanStop()`)*
- ✅ **Once-a-day completion**: Stopping marks German study completed for the day and hides the panel until the next day.

---

### 4. ⚠️ Inactivity / Slacking Detection (3 Minutes)
During a standard Study Session:
- **3-Minute Idle Threshold**: If no user input (mouse move, click, scrolling, key press) occurs for **3 minutes (180s)**, the **Crystals** alarm rings to wake you up!
- **Alert Banner**: Displays `⚠️ INACTIVITY DETECTED! No input for 3 mins — back to studying!`.
- **Instant Silence**: Moving your mouse, scrolling, or pressing any key immediately silences the alarm.
- Disabled automatically during Break sessions.

---

### 5. 🔥 Hardcore Mode (Hold `fn + S` for 3 Seconds)
Triggered by **holding `fn + S` continuously for 3 seconds** (overrides standard Study Mode if already running):

- ⏱️ **40-Minute Study / 10-Minute Break**: 40 mins study (sites blocked), 10 mins break (sites unblocked).
- ⚡ **Override Capability**: If normal Study Mode is running, holding `fn + S` for 3 seconds immediately upgrades/replaces it with Hardcore Mode.
- 🔒 **Non-Removable**: Cannot be stopped manually via Console (`spoon.StudyMode:stop()`) or hotkeys.
- 🔁 **5 Consecutive Sessions**: Automatically ends only after completing 5 full study sessions on its own.
- 🎨 **HUD Badging**: Displays glowing red theme with session progress `[ 🔥 1/5  39:59 ]`.

---

## 📦 Installation & Setup

Add to your `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("StudyMode")
spoon.StudyMode:init()

-- Optional custom hotkey (fn + S works by default)
spoon.StudyMode:bindHotkeys({
    start = {{"cmd", "alt", "ctrl"}, "S"}
})
```

Reload Hammerspoon config (`Cmd + Alt + Ctrl + R`).

---

## ⚙️ Customization

```lua
hs.loadSpoon("StudyMode")

-- Standard durations
spoon.StudyMode.studyDuration = 45 * 60 -- 45 minutes
spoon.StudyMode.breakDuration = 15 * 60 -- 15 minutes

-- 16:00 Session settings
spoon.StudyMode.daily16Time = "16:00"          -- Scheduled time
spoon.StudyMode.enableDaily16 = true           -- Enable/disable daily 16:00 block
spoon.StudyMode.daily16StudyDuration = 45 * 60 -- 45 minutes
spoon.StudyMode.daily16BreakDuration = 15 * 60 -- 15 minutes

-- Inactivity alarm settings
spoon.StudyMode.inactivityTimeout = 3 * 60   -- 3 minutes idle threshold
spoon.StudyMode.enableInactivityAlarm = true -- Enable/disable idle alarm

-- Hardcore mode durations
spoon.StudyMode.hardcoreStudyDuration = 40 * 60 -- 40 minutes
spoon.StudyMode.hardcoreBreakDuration = 10 * 60 -- 10 minutes
spoon.StudyMode.hardcoreTotalSessions = 5       -- 5 sessions

spoon.StudyMode:init()
```

---

## 📄 License

MIT License.
