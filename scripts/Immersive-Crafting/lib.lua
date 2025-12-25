local this = {}

--- Logs an informational message to the console.
--- @param msg string The message to log.
function this.info(msg)
    print(('[Immersive-Crafting] INFO: %s'):format(msg))
end

--- Logs a warning message to the console.
--- @param msg string The warning message to log.
function this.warn(msg)
    print(('[Immersive-Crafting] WARNING: %s'):format(msg))
end

return this
