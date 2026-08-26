# 🎯 StudyMode.spoon

> An automated Pomodoro focus Spoon for Hammerspoon that cycles between **45-minute Study sessions** (blocking YouTube, Chess, and Gemini AI) and **15-minute Break sessions** (unblocking sites). Rings the macOS **Crystals** alarm when the break ends until clicked.

---

## 🔄 How the Cycle Works

1. 📚 **45-Minute Study Phase**:
   - **Sites BLOCKED**: YouTube, Chess (`chess.com` & `lichess.org`), and Gemini AI (`gemini.google.com`).
   - **HUD**: Emerald top-right floating pill (`[ 🟢 STUDY  44:59 ]`).
   - When timer reaches `00:00`, it automatically transitions to Break mode.

2. ☕ **15-Minute Break Phase**:
   - **Sites UNBLOCKED**: YouTube, Chess, and Gemini AI are fully accessible.
   - **HUD**: Warm amber floating pill (`[ ☕ BREAK  14:59 ]`).
   - When timer reaches `00:00`, it automatically transitions to Alarm mode.

3. 🔔 **Break Over Alarm ("Crystals")**:
   - **Ringing**: Plays the macOS **Crystals** ringtone continuously every 2.5 seconds.
   - **HUD**: Flashing pulsing red pill (`[ 🔔 START STUDY ]`).
   - **Interactive Trigger**: Simply **click the top-right overlay pill** (or press `fn + S`) to stop the ringing and immediately launch your next 45-minute Study session!

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

-- Change study or break duration (in seconds)
spoon.StudyMode.studyDuration = 45 * 60 -- 45 minutes
spoon.StudyMode.breakDuration = 15 * 60 -- 15 minutes

spoon.StudyMode:init()
```

---

## 📄 License

MIT License.
