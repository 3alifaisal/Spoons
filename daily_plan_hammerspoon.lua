-- Daily Plan popup for Hammerspoon + Apple Notes — snappy version
-- Main speed improvements:
--   1. Preloads today's note and WebView after Hammerspoon starts.
--   2. Keeps the hidden WebView alive instead of recreating it every time.
--   3. Uses almost no hover/show/focus animation delay.
--   4. Hides first, then saves when closing.

-- ---------- Clean up an older loaded copy ----------
if DailyPlan then
    local function safe(method, object)
        if object then pcall(function() object[method](object) end) end
    end
    safe("stop", DailyPlan.mouseWatcher)
    safe("stop", DailyPlan.clickWatcher)
    safe("stop", DailyPlan.hoverTimer)
    safe("stop", DailyPlan.preloadTimer)
    safe("delete", DailyPlan.hotkey)
    safe("delete", DailyPlan.popup)
end

DailyPlan = {
    popup = nil,
    popupVisible = false,
    preparing = false,
    showWhenReady = false,
    loadedTitle = nil,
}

-- ---------- Settings ----------
local config = {
    notesAccount = "iCloud",
    notesFolder = "Daily Plans",

    width = 520,
    height = 620,
    margin = 14,

    triggerSize = 14,
    hoverDelay = 0.04,  -- change to 0 for truly instant activation
    focusDelay = 0.01,

    fallbackHotkey = {{"cmd", "shift"}, "P"},
}

local template = [[TODAY'S 3 PRIORITIES

☐ 
☐ 
☐ 


SCHEDULE

09:00 — 
10:00 — 
11:00 — 
12:00 — 
13:00 — 
14:00 — 
15:00 — 
16:00 — 


OTHER TASKS

☐ 
☐ 
☐ 


NOTES

]]

local function todayTitle()
    return os.date("%Y-%m-%d")
end

local function todayHeading()
    return os.date("%A, %d %B")
end

local function htmlEscape(text)
    return (tostring(text or "")
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;"))
end

local function jsString(text)
    text = tostring(text or "")
    text = text
        :gsub("\\", "\\\\")
        :gsub("%z", "\\u0000")
        :gsub("\b", "\\b")
        :gsub("\f", "\\f")
        :gsub("\r", "\\r")
        :gsub("\n", "\\n")
        :gsub("\t", "\\t")
        :gsub('"', '\\"')
        :gsub("<", "\\u003C")
        :gsub(">", "\\u003E")
        :gsub("&", "\\u0026")
        :gsub("\226\128\168", "\\u2028")
        :gsub("\226\128\169", "\\u2029")
    return '"' .. text .. '"'
end

local function decodeHTMLEntities(text)
    return (text
        :gsub("&nbsp;", " ")
        :gsub("&quot;", '"')
        :gsub("&#39;", "'")
        :gsub("&lt;", "<")
        :gsub("&gt;", ">")
        :gsub("&amp;", "&"))
end

local function textToNoteHTML(title, text)
    local body = htmlEscape(text):gsub("\n", "<br>")
    return "<h1>" .. htmlEscape(title) .. "</h1><div>" .. body .. "</div>"
end

local function removeTitleAndMarkup(raw, title)
    local text = tostring(raw or "")
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    if text:find("<[%a!/][^>]*>") then
        text = text
            :gsub("<br%s*/?>", "\n")
            :gsub("</div>", "\n")
            :gsub("</p>", "\n")
            :gsub("</h%d>", "\n")
            :gsub("<[^>]->", "")
        text = decodeHTMLEntities(text)
    end

    local firstLine, rest = text:match("^([^\n]*)\n?(.*)$")
    if firstLine and firstLine:gsub("^%s+", ""):gsub("%s+$", "") == title then
        text = rest or ""
    end

    return text:gsub("^\n+", "")
end

-- AppleScript receives Base64 strings to avoid quote/newline issues.
local function runNotesScript(mode, title, html)
    local account64 = hs.base64.encode(config.notesAccount)
    local folder64 = hs.base64.encode(config.notesFolder)
    local mode64 = hs.base64.encode(mode)
    local title64 = hs.base64.encode(title)
    local body64 = hs.base64.encode(html or "")

    local script = [[
on decode64(encodedText)
    return do shell script "printf %s " & quoted form of encodedText & " | /usr/bin/base64 -D"
end decode64

set accountName to my decode64("]] .. account64 .. [[")
set folderName to my decode64("]] .. folder64 .. [[")
set operationName to my decode64("]] .. mode64 .. [[")
set noteTitle to my decode64("]] .. title64 .. [[")
set noteBody to my decode64("]] .. body64 .. [[")

tell application "Notes"
    set targetAccount to first account whose name is accountName
    set targetFolder to first folder of targetAccount whose name is folderName
    set matchingNotes to every note of targetFolder whose name is noteTitle

    if operationName is "read" then
        if (count of matchingNotes) is 0 then return "__MISSING__"
        set targetNote to item 1 of matchingNotes
        try
            return plaintext of targetNote
        on error
            return body of targetNote
        end try
    end if

    if operationName is "write" then
        if (count of matchingNotes) is 0 then
            make new note at targetFolder with properties {body:noteBody}
        else
            set body of item 1 of matchingNotes to noteBody
        end if
        return "ok"
    end if
end tell
]]

    return hs.osascript.applescript(script)
end

local function popupFrame()
    local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
    local frame = screen:frame()

    return {
        x = frame.x + frame.w - config.width - config.margin,
        y = frame.y + frame.h - config.height - config.margin,
        w = config.width,
        h = config.height,
    }
end

local function setSaveStatus(ok, message)
    if not DailyPlan.popup then return end
    local js = "window.setSaveStatus(" ..
        (ok and "true" or "false") .. "," ..
        jsString(message or "") .. ");"
    DailyPlan.popup:evaluateJavaScript(js)
end

local function saveText(text, title)
    title = title or DailyPlan.loadedTitle or todayTitle()
    local html = textToNoteHTML(title, text)
    local ok, _, errorInfo = runNotesScript("write", title, html)

    if ok then
        setSaveStatus(true, "Saved")
    else
        setSaveStatus(false, "Save failed")
        print("Daily Plan save error:")
        print(hs.inspect(errorInfo))
    end
    return ok
end

local function hidePopupImmediately()
    if not DailyPlan.popup or not DailyPlan.popupVisible then return end
    DailyPlan.popupVisible = false
    DailyPlan.popup:hide(0)
end

local function requestSaveAndHide()
    if not DailyPlan.popup or not DailyPlan.popupVisible then return end
    DailyPlan.popup:evaluateJavaScript("window.flushAndHide();")
end

local function buildHTML(text, title, heading)
    local headingJSON = jsString(heading)
    local titleJSON = jsString(title)
    local textJSON = jsString(text)

    local html = [==[
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
    :root {
        color-scheme: light dark;
        --bg: rgba(249, 249, 247, 0.98);
        --text: #1e1e1e;
        --muted: #7a7a7a;
        --border: rgba(0, 0, 0, 0.10);
    }

    @media (prefers-color-scheme: dark) {
        :root {
            --bg: rgba(29, 29, 31, 0.98);
            --text: #f2f2f2;
            --muted: #9a9a9a;
            --border: rgba(255, 255, 255, 0.10);
        }
    }

    * { box-sizing: border-box; }

    html, body {
        width: 100%;
        height: 100%;
        margin: 0;
        overflow: hidden;
        background: transparent;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    }

    .card {
        width: 100%;
        height: 100%;
        display: flex;
        flex-direction: column;
        background: var(--bg);
        color: var(--text);
        border: 1px solid var(--border);
        border-radius: 17px;
        overflow: hidden;
    }

    header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 18px 20px 12px;
        user-select: none;
    }

    .heading {
        font-size: 17px;
        font-weight: 650;
        letter-spacing: -0.2px;
    }

    .subheading {
        margin-top: 3px;
        color: var(--muted);
        font-size: 12px;
    }

    .right {
        display: flex;
        align-items: center;
        gap: 12px;
    }

    #status {
        color: var(--muted);
        font-size: 12px;
    }

    button {
        width: 28px;
        height: 28px;
        border: 0;
        border-radius: 50%;
        background: transparent;
        color: var(--muted);
        font-size: 19px;
        cursor: pointer;
    }

    button:hover {
        background: var(--border);
        color: var(--text);
    }

    textarea {
        flex: 1;
        width: 100%;
        min-height: 0;
        resize: none;
        border: 0;
        outline: 0;
        padding: 8px 20px 22px;
        background: transparent;
        color: var(--text);
        caret-color: var(--text);
        font: 15px/1.58 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        letter-spacing: 0.05px;
    }

    textarea::selection {
        background: rgba(128, 128, 128, 0.28);
    }
</style>
</head>
<body>
<div class="card">
    <header>
        <div>
            <div class="heading" id="heading"></div>
            <div class="subheading" id="title"></div>
        </div>
        <div class="right">
            <span id="status">Saved</span>
            <button id="close" title="Save and close">×</button>
        </div>
    </header>
    <textarea id="editor" spellcheck="true"></textarea>
</div>

<script>
    const heading = __HEADING__;
    const title = __TITLE__;
    const initialText = __TEXT__;

    const editor = document.getElementById("editor");
    const status = document.getElementById("status");

    document.getElementById("heading").textContent = heading;
    document.getElementById("title").textContent = title;
    editor.value = initialText;

    let saveTimer = null;

    function post(payload) {
        try {
            window.webkit.messageHandlers.dailyPlan.postMessage(payload);
        } catch (error) {
            status.textContent = "Bridge error";
        }
    }

    function queueSave() {
        status.textContent = "Saving…";
        clearTimeout(saveTimer);
        saveTimer = setTimeout(() => {
            saveTimer = null;
            post({action: "save", text: editor.value});
        }, 650);
    }

    window.setSaveStatus = function(ok, message) {
        status.textContent = message || (ok ? "Saved" : "Save failed");
    };

    window.flushAndHide = function() {
        clearTimeout(saveTimer);
        saveTimer = null;
        post({action: "saveAndHide", text: editor.value});
    };

    editor.addEventListener("input", queueSave);
    document.getElementById("close").addEventListener("click", window.flushAndHide);

    document.addEventListener("keydown", event => {
        if (event.key === "Escape") {
            event.preventDefault();
            window.flushAndHide();
        }
    });
</script>
</body>
</html>
]==]

    html = html:gsub("__HEADING__", function() return headingJSON end)
    html = html:gsub("__TITLE__", function() return titleJSON end)
    html = html:gsub("__TEXT__", function() return textJSON end)
    return html
end

local function destroyPopup()
    if DailyPlan.popup then
        pcall(function() DailyPlan.popup:delete() end)
    end
    DailyPlan.popup = nil
    DailyPlan.popupVisible = false
    DailyPlan.loadedTitle = nil
end

local function preparePopup()
    local title = todayTitle()

    if DailyPlan.popup and DailyPlan.loadedTitle == title then
        return true
    end

    if DailyPlan.preparing then
        return false
    end

    DailyPlan.preparing = true

    if DailyPlan.popup and DailyPlan.loadedTitle ~= title then
        destroyPopup()
    end

    local ok, result, errorInfo = runNotesScript("read", title, "")
    if not ok then
        DailyPlan.preparing = false
        print("Daily Plan read error:")
        print(hs.inspect(errorInfo))
        return false
    end

    local text
    if result == "__MISSING__" then
        text = template
        if not saveText(text, title) then
            DailyPlan.preparing = false
            return false
        end
    else
        text = removeTitleAndMarkup(result, title)
    end

    DailyPlan.controller = hs.webview.usercontent.new("dailyPlan")
    DailyPlan.controller:setCallback(function(message)
        local payload = message.body or message
        if type(payload) ~= "table" then return end

        local noteTitle = DailyPlan.loadedTitle or todayTitle()

        if payload.action == "save" then
            saveText(payload.text or "", noteTitle)

        elseif payload.action == "saveAndHide" then
            local capturedText = payload.text or ""
            hidePopupImmediately()

            -- The popup disappears immediately; Notes saving happens next.
            hs.timer.doAfter(0, function()
                saveText(capturedText, noteTitle)
            end)
        end
    end)

    DailyPlan.popup = hs.webview
        .new(
            popupFrame(),
            {
                javaScriptEnabled = true,
                javaScriptCanOpenWindowsAutomatically = false,
            },
            DailyPlan.controller
        )
        :allowTextEntry(true)
        :allowGestures(false)
        :allowNewWindows(false)
        :windowStyle(0)
        :shadow(true)
        :level(hs.drawing.windowLevels.floating)
        :html(buildHTML(text, title, todayHeading()))

    DailyPlan.loadedTitle = title
    DailyPlan.preparing = false

    if DailyPlan.showWhenReady then
        DailyPlan.showWhenReady = false
        hs.timer.doAfter(0, function()
            if DailyPlan.popup and not DailyPlan.popupVisible then
                DailyPlan.popup:frame(popupFrame())
                DailyPlan.popupVisible = true
                DailyPlan.popup:show(0):bringToFront(true)
                hs.timer.doAfter(config.focusDelay, function()
                    if DailyPlan.popup and DailyPlan.popupVisible then
                        local window = DailyPlan.popup:hswindow()
                        if window then window:focus() end
                        DailyPlan.popup:evaluateJavaScript(
                            "window.focus(); document.getElementById('editor').focus();"
                        )
                    end
                end)
            end
        end)
    end

    return true
end

local function showPopup()
    if DailyPlan.popupVisible then return end

    if not DailyPlan.popup or DailyPlan.loadedTitle ~= todayTitle() then
        DailyPlan.showWhenReady = true

        if not preparePopup() then
            if not DailyPlan.preparing then
                DailyPlan.showWhenReady = false
                hs.alert.show("Daily Plan: cannot access Apple Notes")
            end
        end
        return
    end

    DailyPlan.popup:frame(popupFrame())
    DailyPlan.popupVisible = true
    DailyPlan.popup:show(0):bringToFront(true)

    hs.timer.doAfter(config.focusDelay, function()
        if DailyPlan.popup and DailyPlan.popupVisible then
            local window = DailyPlan.popup:hswindow()
            if window then window:focus() end
            DailyPlan.popup:evaluateJavaScript(
                "window.focus(); document.getElementById('editor').focus();"
            )
        end
    end)
end

local function pointIsInCorner()
    local screen = hs.mouse.getCurrentScreen()
    if not screen then return false end

    local point = hs.mouse.absolutePosition()
    local frame = screen:fullFrame()

    return point.x >= frame.x + frame.w - config.triggerSize
       and point.y >= frame.y + frame.h - config.triggerSize
end

DailyPlan.cornerArmed = true

DailyPlan.mouseWatcher = hs.eventtap.new(
    {hs.eventtap.event.types.mouseMoved},
    function()
        local inCorner = pointIsInCorner()

        if DailyPlan.popupVisible then
            return false
        end

        if inCorner and DailyPlan.cornerArmed and not DailyPlan.hoverTimer then
            if config.hoverDelay <= 0 then
                DailyPlan.cornerArmed = false
                showPopup()
            else
                DailyPlan.hoverTimer = hs.timer.doAfter(config.hoverDelay, function()
                    DailyPlan.hoverTimer = nil
                    if pointIsInCorner() and not DailyPlan.popupVisible then
                        DailyPlan.cornerArmed = false
                        showPopup()
                    end
                end)
            end
        elseif not inCorner then
            DailyPlan.cornerArmed = true
            if DailyPlan.hoverTimer then
                DailyPlan.hoverTimer:stop()
                DailyPlan.hoverTimer = nil
            end
        end

        return false
    end
):start()

DailyPlan.clickWatcher = hs.eventtap.new(
    {
        hs.eventtap.event.types.leftMouseDown,
        hs.eventtap.event.types.rightMouseDown,
    },
    function()
        if not DailyPlan.popup or not DailyPlan.popupVisible then return false end

        local point = hs.mouse.absolutePosition()
        local frame = DailyPlan.popup:frame()
        local outside =
            point.x < frame.x or point.x > frame.x + frame.w or
            point.y < frame.y or point.y > frame.y + frame.h

        if outside then
            requestSaveAndHide()
        end

        return false
    end
):start()

DailyPlan.hotkey = hs.hotkey.bind(
    config.fallbackHotkey[1],
    config.fallbackHotkey[2],
    function()
        if DailyPlan.popupVisible then
            requestSaveAndHide()
        else
            showPopup()
        end
    end
)

-- Preload the note and WebView shortly after configuration reload.
-- This moves the Apple Notes delay away from the first hover.
DailyPlan.preloadTimer = hs.timer.doAfter(0.15, function()
    DailyPlan.preloadTimer = nil
    preparePopup()
end)

hs.alert.show("Daily Plan loaded")
