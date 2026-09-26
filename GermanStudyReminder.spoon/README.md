# 🇩🇪 GermanStudyReminder.spoon

> A daily scheduled reminder Spoon for Hammerspoon that triggers at **23:00 every day** to study German. Immediately starts in Alarm Mode ringing the **Crystals** sound until clicked, launching a 45-minute focus session (blocking YouTube & Chess).

---

## 🇩🇪 Features

1. ⏰ **23:00 Daily Schedule**: Automatically triggers every day at 11:00 PM (`23:00`).
2. 🔔 **Starts Directly in Alarm Phase**: Rings the continuous **Crystals** alarm and shows notification: `🇩🇪 ZEIT FÜR DEUTSCH!`.
3. 📚 **Focus Study Session**: Clicking the HUD pill or pressing hotkey launches a 45-minute German study session (blocking YouTube & Chess).

---

## 📦 Installation & Setup

Add to your `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("StudyMode")
spoon.StudyMode:init()

hs.loadSpoon("GermanStudyReminder")
spoon.GermanStudyReminder:init()

-- Optional custom hotkey to trigger manually (Cmd + Alt + Ctrl + G)
spoon.GermanStudyReminder:bindHotkeys({
    trigger = {{"cmd", "alt", "ctrl"}, "G"}
})
```

Reload Hammerspoon config (`Cmd + Alt + Ctrl + R`).

---

## ⚙️ Customization

```lua
hs.loadSpoon("GermanStudyReminder")

-- Change reminder time (24h format)
spoon.GermanStudyReminder.reminderTime = "23:00"

spoon.GermanStudyReminder:init()
```

---

## 📄 License

MIT License.
