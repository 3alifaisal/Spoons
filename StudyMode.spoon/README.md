# 🎯 StudyMode.spoon

> An automated Pomodoro focus Spoon for Hammerspoon that cycles between Study sessions (blocking YouTube and Chess) and Break sessions (unblocking sites). Includes **🔥 Hardcore Mode** and **⚠️ Inactivity Detection**.

---

## 🔄 How the Cycles Work

### 1. Standard Mode (`fn + S` Short Press)
- 📚 **45-Minute Study**: YouTube & Chess **BLOCKED**. HUD: `[ 🟢 STUDY  44:59 ]`.
- ☕ **15-Minute Break**: YouTube & Chess **UNBLOCKED**. HUD: `[ ☕ BREAK  14:59 ]`.
- 🔔 **Break Over Alarm**: Rings macOS **Crystals** sound continuously until clicked or `fn + S` pressed.

---

### 2. ⚠️ Inactivity / Slacking Detection (1 Minute)
During a Study Session (in both Standard & Hardcore Mode):
- **1-Minute Idle Threshold**: If no user input (mouse move, click, scrolling, key press) occurs for **60 seconds**, the **Crystals** alarm rings to wake you up!
- **Alert Banner**: Displays `⚠️ INACTIVITY DETECTED! No input for 60s — back to studying!`.
- **Instant Silence**: Simply moving your mouse, scrolling, or pressing any key immediately silences the alarm.
- Disabled automatically during Break sessions.

---

### 3. 🔥 Hardcore Mode (Hold `fn + S` for 3 Seconds)
Triggered by **holding `fn + S` continuously for 3 seconds** (overrides standard Study Mode if already running):

- ⏱️ **40-Minute Study / 20-Minute Break**: 40 mins study (sites blocked), 20 mins break (sites unblocked).
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

-- Inactivity alarm settings
spoon.StudyMode.inactivityTimeout = 60       -- 60 seconds idle threshold
spoon.StudyMode.enableInactivityAlarm = true  -- Enable/disable idle alarm

-- Hardcore mode durations
spoon.StudyMode.hardcoreStudyDuration = 40 * 60 -- 40 minutes
spoon.StudyMode.hardcoreBreakDuration = 20 * 60 -- 20 minutes
spoon.StudyMode.hardcoreTotalSessions = 5       -- 5 sessions

spoon.StudyMode:init()
```

---

## 📄 License

MIT License.
