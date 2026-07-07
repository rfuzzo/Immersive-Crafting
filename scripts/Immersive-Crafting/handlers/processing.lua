local core = require('openmw.core')
local omwSelf = require('openmw.self')
local util = require('openmw.util')
local types = require('openmw.types')
local ui = require('openmw.ui')
local nearby = require('openmw.nearby')

local CAbstractHandler = require('scripts.Immersive-Crafting.handlers.CAbstractHandler')
local Crafting = require('scripts.Immersive-Crafting.ui.Crafting')
local processState = require('scripts.Immersive-Crafting.processState')
local processCrafting = require('scripts.Immersive-Crafting.processCrafting')
local stationPack = require('scripts.Immersive-Crafting.stationPack')
local lib = require('scripts.Immersive-Crafting.lib')
local io = require('scripts.Immersive-Crafting.io')
local log = require('scripts.Immersive-Crafting.log')

local IGNITE_HOLD = 1.5 -- seconds of holding F (with fire in hand) to light a charge

-- open-charge stations (kiln): items are PLACED VISIBLY in/on the mesh, never
-- absorbed — the charge is whatever loose items lie within this radius.
-- Mirrored in globalProcessing (the ignite consume scan).
local OPEN_CHARGE_RADIUS = 120

--- Activator record ids flagged `"openCharge": true` in stations.json.
local openChargeSet = nil ---@type table<string, boolean>?
local function isOpenCharge(recordId)
    if not openChargeSet then
        openChargeSet = {}
        for _, e in ipairs(io.loadJsonFile('data/Immersive-Crafting/stations/stations.json') or {}) do
            if e.activator and e.openCharge then openChargeSet[e.activator:lower()] = true end
        end
    end
    return openChargeSet[(recordId or ''):lower()] or false
end

--- The loose items physically placed in/on an open-charge station, as a
--- charge list (same shape the synced charge registry uses).
---@param station any the station game object
---@return { id: string, count: integer, name: string? }[]
local function worldCharge(station)
    local list, index = {}, {}
    for _, item in ipairs(nearby.items) do
        if item.count and (item.position - station.position):length() <= OPEN_CHARGE_RADIUS then
            local e = index[item.recordId]
            if e then
                e.count = e.count + (item.count or 1)
            else
                local name
                local ok, rec = pcall(function() return item.type.records[item.recordId] end)
                if ok and rec and rec.name and rec.name ~= '' then name = rec.name end
                e = { id = item.recordId, count = item.count or 1, name = name }
                index[item.recordId] = e
                list[#list + 1] = e
            end
        end
    end
    return list
end

--- "~N min" / "~N h" of remaining GAME time.
local function fmtRemaining(readyAt)
    local seconds = math.max(0, (readyAt or 0) - core.getGameTime())
    if seconds >= 3600 then
        return ('~%d h'):format(math.ceil(seconds / 3600))
    end
    return ('~%d min'):format(math.max(1, math.ceil(seconds / 60)))
end

-- ── UI-less ignition (loaded kiln / charcoal pit) ────────────────────────────

--- Is the player holding fire? A lit torch (Light in the carried-left hand)
--- or any inventory item tagged `firestarter`.
---@return boolean
local function fireInHand()
    local eq = types.Actor.getEquipment(omwSelf)
    local held = eq and eq[types.Actor.EQUIPMENT_SLOT.CarriedLeft]
    if held and held.type == types.Light then return true end
    for _, item in ipairs(types.Actor.inventory(omwSelf):getAll()) do
        if lib.matchesTag(item.recordId, 'firestarter') then return true end
    end
    return false
end

---@param tools string[]|nil
---@return string[] missing tools (empty = all in inventory)
local function missingTools(tools)
    local missing = {}
    for _, tool in ipairs(tools or {}) do
        local found = false
        for _, item in ipairs(types.Actor.inventory(omwSelf):getAll()) do
            if lib.matchesTag(item.recordId, tool) then
                found = true
                break
            end
        end
        if not found then missing[#missing + 1] = tool end
    end
    return missing
end

--- Resolve a station's charge against its process recipes and light it.
--- Exact multiset matching means a resolvable charge burns completely; ties
--- (bonemold helm vs boots) go to the first match by id — the window's
--- cycler remains the tool for choosing precisely.
---@param ctx HandlerContext
---@param charge { id: string, count: integer }[]
local function igniteCharge(ctx, charge)
    local placedIds = {}
    for _, e in ipairs(charge) do
        for _ = 1, (e.count or 1) do placedIds[#placedIds + 1] = e.id end
    end
    local matches = processCrafting.resolveProcessRecipes(placedIds, ctx.action, ctx.context)
    if #matches == 0 then
        ui.showMessage('That will not make anything')
        return
    end

    local recipe, firstMissing
    for _, r in ipairs(matches) do
        local missing = missingTools(r.tools)
        if #missing == 0 then
            recipe = r
            break
        end
        firstMissing = firstMissing or missing
    end
    if not recipe then
        ui.showMessage('Needs: ' .. table.concat(firstMissing, ', '))
        return
    end
    if not (recipe.duration and recipe.duration > 0) then
        ui.showMessage('This needs the crafting window') -- instant recipes stay windowed
        return
    end

    -- returned lines (the mold in the charge) -> actual charge record ids
    local counts = {}
    for _, e in ipairs(charge) do counts[e.id] = (counts[e.id] or 0) + (e.count or 1) end
    local returned = {}
    for _, line in ipairs(recipe.inputs or {}) do
        if line.returned then
            local remaining = line.count or 1
            for id, n in pairs(counts) do
                if remaining <= 0 then break end
                if lib.matchesTag(id, line.id) then
                    local take = math.min(n, remaining)
                    counts[id] = n - take
                    returned[#returned + 1] = { id = id, count = take }
                    remaining = remaining - take
                end
            end
        end
    end

    -- open-charge station (kiln): the charge is the loose items in/on it —
    -- tell the global side what to consume from the world (validated there)
    local consume = nil
    if isOpenCharge(ctx.object and ctx.object.recordId) then
        consume = {}
        for _, e in ipairs(charge) do
            consume[#consume + 1] = { id = e.id, count = e.count or 1 }
        end
    end

    core.sendGlobalEvent('ImmersiveCrafting_IgniteStation', {
        actor = omwSelf.object,
        station = ctx.object,
        recipeId = recipe.id,
        label = recipe.label or recipe.id,
        output = recipe.output,
        duration = recipe.duration,
        returned = #returned > 0 and returned or nil,
        consume = consume,
    })
end

---@class CProcessingHandler : CAbstractHandler
local CProcessingHandler = {

}
setmetatable(CProcessingHandler, { __index = CAbstractHandler })

--#region Implements

---@param ctx HandlerContext
---@return ViewModel
function CProcessingHandler:evaluate(ctx)
    -- a running/finished timed process owns the card
    local run = ctx.object and processState.forStation(ctx.object.id)
    if run then
        if run.done then
            ---@type ViewModel
            return {
                status = (run.label or 'Work') .. ' — ready!',
                details = { 'Activate to collect' },
            }
        end
        -- progress bar (the overlay renders ViewModel.progress) + remaining time
        local progress = nil
        if run.startedAt and run.readyAt and run.readyAt > run.startedAt then
            progress = util.clamp(
                (core.getGameTime() - run.startedAt) / (run.readyAt - run.startedAt), 0, 1)
        end
        ---@type ViewModel
        return {
            -- the bar + "Ready in" already say it's working; a suffix overflowed
            status = run.label or 'Working',
            progress = progress,
            details = { 'Ready in ' .. fmtRemaining(run.readyAt) },
        }
    end

    -- a loaded (but unlit) station owns the card: show the charge, and the
    -- hold-to-light action when the player holds fire. Open-charge stations
    -- (kiln) read the charge from the items physically placed in them.
    local stored = ctx.object and processState.chargeFor(ctx.object.id)
    local open = ctx.object and isOpenCharge(ctx.object.recordId)
    local charge = stored
    if (not charge or #charge == 0) and open then
        charge = worldCharge(ctx.object)
    end
    if charge and #charge > 0 and ctx.context.trigger == 'activate' then
        local parts = {}
        for _, e in ipairs(charge) do
            parts[#parts + 1] = ('%dx %s'):format(e.count or 1, e.name or e.id)
        end
        local details = { 'Contains: ' .. table.concat(parts, ', ') }
        local action = nil
        if fireInHand() then
            action = { id = 'ignite', label = 'Light the fire', enabled = true, hold = IGNITE_HOLD }
        else
            details[#details + 1] = 'Needs fire in hand (a torch)'
        end
        if stored and #stored > 0 then
            -- absorbed charge (charcoal pit): activation is the undo. An
            -- open-charge station's items are simply picked up off it.
            details[#details + 1] = 'Activate to take the last item back'
        end
        ---@type ViewModel
        return {
            status = 'Loaded',
            details = details,
            action = action,
        }
    end

    -- Activate-triggered stations show an info-only card (opened by activating),
    -- listing the input roles so the player knows what the station needs.
    if ctx.context.trigger == 'activate' then
        local details = nil
        local inputs = ctx.context.layout and ctx.context.layout.inputs
        if inputs and #inputs > 0 then
            -- named roles (e.g. Input, Fuel, Mold) if the layout labels them,
            -- repeats collapsed ("Input x3"); otherwise the generic slot count
            local roles, counts = {}, {}
            for _, inp in ipairs(inputs) do
                if inp.label then
                    if not counts[inp.label] then
                        roles[#roles + 1] = inp.label
                        counts[inp.label] = 0
                    end
                    counts[inp.label] = counts[inp.label] + 1
                end
            end
            if #roles > 0 then
                for i, label in ipairs(roles) do
                    if counts[label] > 1 then
                        roles[i] = ('%s x%d'):format(label, counts[label])
                    end
                end
                details = { "Inputs: " .. table.concat(roles, ", ") }
            else
                details = { ("%d input slots"):format(#inputs) }
            end
        end
        ---@type ViewModel
        return {
            status = "Activate to use",
            details = details,
            -- placed IC stations offer hold-F pack-up under the info card
            action = stationPack.action(ctx.object),
        }
    end

    ---@type ViewModel
    local vm = {
        status = "Processing station",
        action = {
            id = "processing",
            label = "Use " .. (ctx.context.label or "station"),
            enabled = true,
        }
    }
    return vm
end

---@param ctx HandlerContext
function CProcessingHandler:OnActivate(ctx)
    -- proximity stations: [F] while a run is finished collects it; while it's
    -- still working, do nothing (the card shows the remaining time).
    local run = ctx.object and processState.forStation(ctx.object.id)
    if run then
        if run.done then
            core.sendGlobalEvent('ImmersiveCrafting_CollectProcess', {
                actor = omwSelf.object,
                stationId = ctx.object.id,
            })
        end
        return
    end

    -- activate-triggered stations never open the window from here (activating
    -- the object does that) — completing the hold on their card LIGHTS a
    -- loaded charge (with fire in hand) or PACKS the station up
    if ctx.context.trigger == 'activate' then
        local charge = ctx.object and processState.chargeFor(ctx.object.id)
        if (not charge or #charge == 0) and ctx.object and isOpenCharge(ctx.object.recordId) then
            charge = worldCharge(ctx.object)
        end
        if charge and #charge > 0 then
            if fireInHand() then igniteCharge(ctx, charge) end
            return
        end
        if stationPack.isPackable(ctx.object) then
            stationPack.pack(ctx.object)
        end
        return
    end

    -- The window picks its layout from ctx.context.layout, so the same handler
    -- serves grid and process stations.
    log.info("Toggling crafting window for " .. (ctx.context.id or "?"))
    Crafting.toggle(ctx)
end

--#endregion


return CProcessingHandler
