-- Dark Convent Hexer trait: the Soul Harvest passive feeds the army's winds of magic reserve as soldiers die nearby.
-- The passive itself does nothing in battle; it marks the unit (and shows on its card). This script does the work.

local ability_key = "corv_passive_hexer_soul_harvest"
local process_name = "corvus_hexer_soul_harvest"
local tick_ms = 1000
-- Deaths within this many metres of the Hexer count
local radius = 75
-- Reserve gained per second for each recent death nearby, capped at max_rate
local rate_per_death = 0.005
local max_rate = 0.1
-- How long a death keeps counting towards the rate
local window_seconds = 10

if not bm then
    return
end

-- unit unique ui id -> men alive at the last tick
local last_alive = {}
-- unit unique ui id -> { unit, history = { { time, deaths } } }, or false for units without the passive
local hexers = {}
local elapsed_seconds = 0

local function has_soul_harvest(unit)
    for _, key in ipairs(unit:owned_passive_special_abilities()) do
        if key == ability_key then
            return true
        end
    end
    return false
end

local function for_each_unit(callback)
    local alliances = bm:alliances()
    for a = 1, alliances:count() do
        local armies = alliances:item(a):armies()
        for b = 1, armies:count() do
            local units = armies:item(b):units()
            for u = 1, units:count() do
                callback(units:item(u))
            end
        end
    end
end

local function tick()
    elapsed_seconds = elapsed_seconds + tick_ms / 1000

    -- Where soldiers died since the last tick (units are re-read every tick so reinforcements are included)
    local deaths = {}
    for_each_unit(function (unit)
        local id = unit:unique_ui_id()
        local alive = unit:number_of_men_alive()
        local previous = last_alive[id]
        if previous and previous > alive then
            table.insert(deaths, { position = unit:position(), count = previous - alive })
        end
        last_alive[id] = alive
        if hexers[id] == nil then
            hexers[id] = has_soul_harvest(unit) and { unit = unit, history = {} } or false
        end
    end)

    for _, hexer in pairs(hexers) do
        if hexer and hexer.unit:number_of_men_alive() > 0 then
            local position = hexer.unit:position()
            local nearby_deaths = 0
            for _, death in ipairs(deaths) do
                if position:distance_xz(death.position) <= radius then
                    nearby_deaths = nearby_deaths + death.count
                end
            end
            if nearby_deaths > 0 then
                table.insert(hexer.history, { time = elapsed_seconds, deaths = nearby_deaths })
            end

            local recent_deaths = 0
            for i = #hexer.history, 1, -1 do
                local entry = hexer.history[i]
                if elapsed_seconds - entry.time > window_seconds then
                    table.remove(hexer.history, i)
                else
                    recent_deaths = recent_deaths + entry.deaths
                end
            end

            local rate = math.min(max_rate, recent_deaths * rate_per_death)
            if rate > 0 then
                hexer.unit:army():modify_winds_of_magic_reserve(rate * tick_ms / 1000)
            end
        end
    end
end

bm:register_phase_change_callback("Deployed", function ()
    bm:repeat_callback(function ()
        local ok, err = pcall(tick)
        if not ok then
            bm:out("Soul Harvest: error, stopping: "..tostring(err))
            bm:remove_process(process_name)
        end
    end, tick_ms, process_name)
end)
