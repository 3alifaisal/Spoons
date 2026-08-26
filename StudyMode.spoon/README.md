# 🎯 StudyMode.spoon

> A focused 45-minute study session Spoon for Hammerspoon that blocks distracting websites (**YouTube**, **Chess.com**, **Lichess**, and **Gemini AI**) and displays a non-resettable floating countdown timer.

---

## 🚀 Features

- ⏱️ **45-Minute Focus Session**: Floating canvas countdown timer anchored in the top-right corner of your screen.
- 🚫 **Distraction Blocking**: Automatically blocks:
  - **YouTube** (`youtube.com`, `youtu.be`, `music.youtube.com`, etc.)
  - **Chess** (`chess.com` and `lichess.org`)
  - **Gemini AI** (`gemini.google.com`, `bard.google.com`, `aistudio.google.com`)
- 🔒 **Non-Resettable by Design**: `fn + S` will show the remaining time, but will not cancel or restart an active session. Emergency stop is available via `spoon.StudyMode:stop()` in the Hammerspoon Console.
- 🔄 **Auto-Recovery**: If Hammerspoon reloads or restarts during a session, StudyMode automatically resumes the timer and site blocking.
- ⌨️ **Flexible Hotkeys**: Trigger via `fn + S` or configure custom shortcuts.

---

## 📦 Installation & Setup

### Step 1: Run the Helper Installer

StudyMode uses a lightweight helper script to modify `/etc/hosts` passwordlessly during your session.

Open Terminal and run:
```bash
bash ~/.hammerspoon/Spoons/StudyMode.spoon/install.sh
```
*(You will be prompted for your macOS admin password once to configure `/etc/sudoers.d/hammerspoon-study-mode`)*.

---

### Step 2: Load in Hammerspoon `init.lua`

Add the following lines to your `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("StudyMode")
spoon.StudyMode:init()

-- Optional: Bind a custom hotkey (e.g. Cmd+Alt+Ctrl+S) in addition to fn + S
spoon.StudyMode:bindHotkeys({
    start = {{"cmd", "alt", "ctrl"}, "S"}
})
```

Reload your Hammerspoon config (`Cmd + Alt + Ctrl + R`).

---

## ⚙️ Configuration Options

You can customize session settings before calling `:init()`:

```lua
hs.loadSpoon("StudyMode")

-- Change session length (default: 45 minutes)
spoon.StudyMode.duration = 30 * 60 -- 30 minutes

-- Change screen margin or overlay dimensions
spoon.StudyMode.screenMargin = 20

spoon.StudyMode:init()
```

---

## 📄 License

MIT License.
