local dataHandler = require('scripts.Immersive-Crafting.datahandler')


local function onSave()
    return saveData
end

local function onLoad(data)
    saveData = data or {}

    dataHandler.loadAllData()
end

return {
    engineHandlers = {
        onLoad = onLoad,
        onInit = onLoad,
        onSave = onSave,
    },
    eventHandlers = {

    }
}
