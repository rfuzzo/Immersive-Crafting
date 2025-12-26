local this = {}

--- Logs a trace message to the console.
--- @param msg string The trace message to log.
function this.trace(msg) print(('[Immersive-Crafting] TRACE: %s'):format(msg)) end

--- Logs an informational message to the console.
--- @param msg string The message to log.
function this.info(msg) print(('[Immersive-Crafting] INFO: %s'):format(msg)) end

--- Logs a warning message to the console.
--- @param msg string The warning message to log.
function this.warn(msg) print(('[Immersive-Crafting] WARN: %s'):format(msg)) end

--- Logs an error message to the console.
--- @param msg string The error message to log.
function this.error(msg) print(('[Immersive-Crafting] ERROR: %s'):format(msg)) end

return this
