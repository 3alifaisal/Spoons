# 🎯 StudyMode.spoon

> An automated Pomodoro focus Spoon for Hammerspoon that cycles between Study sessions (blocking YouTube and Chess) and Break sessions (unblocking sites). Includes a **🔥 Hardcore Mode** triggered by pressing `fn + S` 3 times rapidly.

---

## 🔄 How the Cycles Work

### 1. Standard Mode
- 📚 **45-Minute Study**: YouTube & Chess **BLOCKED**. HUD: `[ 🟢 STUDY  44:59 ]`.
- ☕ **15-Minute Break**: YouTube & Chess **UNBLOCKED**. HUD: `[ ☕ BREAK  14:59 ]`.
- 🔔 **Break Over Alarm**: Rings macOS **Crystals** sound continuously until clicked or `fn + S` pressed.

---

### 2. 🔥 Hardcore Mode (`fn + S` 3 Times)
Triggered by pressing **`fn + S` 3 times in rapid succession** (within 1.5 seconds):

- ⏱️ **40-Minute Study / 20-Minute Break**: 40 mins study (sites blocked), 20 mins break (sites unblocked).
- 🔒 **Non-Removable**: Cannot be stopped manually via Console (`spoon.StudyMode:stop()`) or hotkeys.
- 🔁 **5 Consecutive Sessions**: Automatically ends only after completing 5 full study sessions.
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

-- Hardcore mode durations
spoon.StudyMode.hardcoreStudyDuration = 40 * 60 -- 40 minutes
spoon.StudyMode.hardcoreBreakDuration = 20 * 60 -- 20 minutes
spoon.StudyMode.hardcoreTotalSessions = 5       -- 5 sessions

spoon.StudyMode:init()
```

---

## 📄 License

MIT License.
