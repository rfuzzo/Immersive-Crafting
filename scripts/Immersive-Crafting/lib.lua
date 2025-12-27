local core = require('openmw.core')


local this = {}

function this.len(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

return this
