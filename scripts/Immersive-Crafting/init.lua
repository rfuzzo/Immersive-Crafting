local function onSave() return saveData end

local function onLoad(data)
    ---@diagnostic disable-next-line: lowercase-global
    saveData = data or {}
end

return {
    engineHandlers = {onLoad = onLoad, onInit = onLoad, onSave = onSave},
    eventHandlers = {}
}
