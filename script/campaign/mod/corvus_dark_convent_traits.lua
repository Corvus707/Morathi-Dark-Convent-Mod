-- Dark Convent trait effects that need script.
--
-- The Diplomat trait used to warm the region owner's relations with Morathi through a scripted, permanent bundle on
-- that faction. It now gives Devotees instead (db only), so this only removes the old bundle from saves that have it.

local relations_bundle_key = "corv_diplomat_relations"
local cleanup_saved_key = "corvus_dark_convent_diplomat_relations_removed"

cm:add_first_tick_callback(function ()
    if cm:get_saved_value(cleanup_saved_key) then
        return
    end
    local factions = cm:model():world():faction_list()
    for i = 0, factions:num_items() - 1 do
        local faction = factions:item_at(i)
        if faction:has_effect_bundle(relations_bundle_key) then
            out("Dark Convent: removing the old Diplomat relations bundle from "..faction:name())
            cm:remove_effect_bundle(relations_bundle_key, faction:name())
        end
    end
    cm:set_saved_value(cleanup_saved_key, true)
end)
