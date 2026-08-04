-- init.lua wrapper for DailyPlan Spoon
local scriptPath = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or ""
local chunk, err = loadfile(scriptPath .. "daily_plan_hammerspoon.lua")
if chunk then
    return chunk()
else
    return require("daily_plan_hammerspoon")
end
