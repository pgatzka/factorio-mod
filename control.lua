-- Shows the amount of debris inside a roboport's construction range
-- in the roboport's info panel while a player hovers over it, and lets
-- roboports mark that debris for deconstruction, limited by a map setting.

local MAX_MARKED_SETTING = "factorio-mod-max-marked-debris"

-- Roboports are visited round-robin; the batch size is chosen so that every
-- roboport is visited about once per VISIT_PERIOD ticks.
local VISIT_INTERVAL = 10
local VISIT_PERIOD = 600

local rock_names

-- Rocks share the "simple-entity" type with other entities, so they are
-- identified by the same prototype flag the deconstruction planner uses.
local function get_rock_names()
  if rock_names then return rock_names end
  rock_names = {}
  local simple_entities = prototypes.get_entity_filtered({ { filter = "type", type = "simple-entity" } })
  for name, prototype in pairs(simple_entities) do
    if prototype.count_as_rock_for_filtered_deconstruction then
      rock_names[#rock_names + 1] = name
    end
  end
  return rock_names
end

local function get_construction_area(roboport)
  local radius = roboport.logistic_cell.construction_radius
  local position = roboport.position
  return {
    { position.x - radius, position.y - radius },
    { position.x + radius, position.y + radius },
  }
end

local function count_debris(roboport)
  local area = get_construction_area(roboport)
  local surface = roboport.surface
  local count = surface.count_entities_filtered({ area = area, type = { "item-entity", "tree", "cliff" } })
  local rocks = get_rock_names()
  if #rocks > 0 then
    count = count + surface.count_entities_filtered({ area = area, name = rocks })
  end
  return count
end

local cliff_explosives

-- Cliff name -> name of the item that destroys it.
local function get_cliff_explosives()
  if cliff_explosives then return cliff_explosives end
  cliff_explosives = {}
  for name, prototype in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "cliff" } })) do
    cliff_explosives[name] = prototype.cliff_explosive_prototype
  end
  return cliff_explosives
end

local function network_has_item(network, item)
  for quality in pairs(prototypes.quality) do
    if network.get_item_count({ name = item, quality = quality }) > 0 then return true end
  end
  return false
end

-- Cliffs can only be removed while the network holds their explosives.
local function get_removable_cliff_names(network)
  local names = {}
  local available = {}
  for cliff, explosive in pairs(get_cliff_explosives()) do
    if available[explosive] == nil then available[explosive] = network_has_item(network, explosive) end
    if available[explosive] then names[#names + 1] = cliff end
  end
  return names
end

-- Items on the ground can only be removed while the network has storage
-- space for them. The answer is remembered per kind of item, so a visit asks
-- the network once per kind instead of once per entity.
local function get_item_check(network)
  local removable = {}
  return function(entity)
    local stack = entity.stack
    local key = stack.name .. "/" .. stack.quality.name
    if removable[key] == nil then
      removable[key] = network.select_drop_point({ stack = stack }) ~= nil
    end
    return removable[key]
  end
end

-- The debris a roboport may mark, as groups of a search filter and an
-- optional per-entity check. Debris its robots cannot remove is left out, so
-- it is neither marked nor counted toward the limit. Items come last: they
-- are the only group that may need a look at every entity.
local function get_marking_groups(roboport)
  local area = get_construction_area(roboport)
  local groups = { { filter = { area = area, type = "tree" } } }
  local rocks = get_rock_names()
  if #rocks > 0 then
    groups[#groups + 1] = { filter = { area = area, name = rocks } }
  end
  local network = roboport.logistic_network
  if network then
    local cliffs = get_removable_cliff_names(network)
    if #cliffs > 0 then
      groups[#groups + 1] = { filter = { area = area, name = cliffs } }
    end
    groups[#groups + 1] = { filter = { area = area, type = "item-entity" }, is_removable = get_item_check(network) }
  end
  return groups
end

-- Marks up to `remaining` unmarked entities of the group, looking at no more
-- than `limit` of them. Returns what is left to mark and whether any entity
-- was passed over.
local function mark_group(roboport, group, remaining, limit)
  group.filter.limit = limit
  local skipped = false
  for _, entity in pairs(roboport.surface.find_entities_filtered(group.filter)) do
    if (not group.is_removable or group.is_removable(entity)) and entity.order_deconstruction(roboport.force) then
      remaining = remaining - 1
      if remaining == 0 then break end
    else
      skipped = true
    end
  end
  return remaining, skipped
end

-- Marks unmarked debris until the map setting's limit of marked debris in
-- range is reached. Searches stop as soon as they have enough matches, so a
-- visit stays cheap even when the range is full of trees; which pieces get
-- marked does not matter.
local function mark_next_debris(roboport)
  local remaining = settings.global[MAX_MARKED_SETTING].value
  if remaining == 0 then return end

  local surface = roboport.surface
  local groups = get_marking_groups(roboport)
  for _, group in pairs(groups) do
    local filter = group.filter
    filter.to_be_deconstructed = true
    if group.is_removable then
      for _, entity in pairs(surface.find_entities_filtered(filter)) do
        if group.is_removable(entity) then remaining = remaining - 1 end
      end
    else
      filter.limit = remaining
      remaining = remaining - surface.count_entities_filtered(filter)
    end
    if remaining <= 0 then return end
  end

  for _, group in pairs(groups) do
    group.filter.to_be_deconstructed = false
    local skipped
    remaining, skipped = mark_group(roboport, group, remaining, remaining)
    -- Some entities were passed over (unremovable, or they refuse the order,
    -- e.g. not minable); only then look at all of the group.
    if remaining > 0 and skipped then
      remaining = mark_group(roboport, group, remaining, nil)
    end
    if remaining == 0 then return end
  end
end

-- The custom status replaces the regular status line, so the diode keeps
-- reflecting the roboport's actual state.
local function get_diode(roboport)
  local status = roboport.status
  if status == defines.entity_status.working or status == defines.entity_status.normal then
    return defines.entity_status_diode.green
  elseif status == defines.entity_status.low_power then
    return defines.entity_status_diode.yellow
  end
  return defines.entity_status_diode.red
end

local function is_roboport(entity)
  return entity and entity.valid and entity.type == "roboport" and entity.logistic_cell ~= nil
end

local function is_hovered_by_anyone(entity)
  for _, player in pairs(game.connected_players) do
    if player.selected == entity then return true end
  end
  return false
end

script.on_event(defines.events.on_selected_entity_changed, function(event)
  local last_entity = event.last_entity
  if is_roboport(last_entity) and not is_hovered_by_anyone(last_entity) then
    last_entity.custom_status = nil
  end

  local selected = game.get_player(event.player_index).selected
  if is_roboport(selected) then
    -- Read the diode before a status set by another hovering player is replaced.
    selected.custom_status = nil
    selected.custom_status = {
      diode = get_diode(selected),
      label = { "factorio-mod.debris-in-range", count_debris(selected) },
    }
  end
end)

local function register_roboport(entity)
  if entity and entity.valid and entity.type == "roboport" then
    storage.roboports[#storage.roboports + 1] = entity
  end
end

local function rebuild_roboports()
  storage.roboports = {}
  storage.next_roboport = 1
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ type = "roboport" })) do
      register_roboport(entity)
    end
  end
end

script.on_init(rebuild_roboports)
script.on_configuration_changed(rebuild_roboports)

local roboport_filter = { { filter = "type", type = "roboport" } }
local function on_built(event)
  -- Saves that ran an earlier version without storage get their list on the next visit.
  if storage.roboports then register_roboport(event.entity or event.destination) end
end
script.on_event(defines.events.on_built_entity, on_built, roboport_filter)
script.on_event(defines.events.on_robot_built_entity, on_built, roboport_filter)
script.on_event(defines.events.on_space_platform_built_entity, on_built, roboport_filter)
script.on_event(defines.events.script_raised_built, on_built, roboport_filter)
script.on_event(defines.events.script_raised_revive, on_built, roboport_filter)
script.on_event(defines.events.on_entity_cloned, on_built, roboport_filter)

script.on_nth_tick(VISIT_INTERVAL, function()
  if not storage.roboports then rebuild_roboports() end
  local roboports = storage.roboports
  local visits = math.ceil(#roboports * VISIT_INTERVAL / VISIT_PERIOD)
  for _ = 1, visits do
    if #roboports == 0 then return end
    if storage.next_roboport > #roboports then storage.next_roboport = 1 end
    local roboport = roboports[storage.next_roboport]
    if is_roboport(roboport) then
      mark_next_debris(roboport)
      storage.next_roboport = storage.next_roboport + 1
    elseif roboport.valid then
      storage.next_roboport = storage.next_roboport + 1
    else
      -- Removed roboport: the last entry takes its place and is visited next.
      roboports[storage.next_roboport] = roboports[#roboports]
      roboports[#roboports] = nil
    end
  end
end)
