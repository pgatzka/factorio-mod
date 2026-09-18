-- Shows the amount of debris inside a roboport's construction range
-- in the roboport's info panel while a player hovers over it, and lets
-- roboports mark that debris for deconstruction one piece at a time.

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

-- Search filters matching the debris in the roboport's construction range.
-- to_be_deconstructed limits them to marked (true) or unmarked (false)
-- debris; nil matches both.
local function get_debris_filters(roboport, to_be_deconstructed)
  local radius = roboport.logistic_cell.construction_radius
  local position = roboport.position
  local area = {
    { position.x - radius, position.y - radius },
    { position.x + radius, position.y + radius },
  }
  local filters = {
    { area = area, type = { "item-entity", "tree", "cliff" }, to_be_deconstructed = to_be_deconstructed },
  }
  local rocks = get_rock_names()
  if #rocks > 0 then
    filters[#filters + 1] = { area = area, name = rocks, to_be_deconstructed = to_be_deconstructed }
  end
  return filters
end

local function count_debris(roboport, to_be_deconstructed)
  local surface = roboport.surface
  local count = 0
  for _, filter in pairs(get_debris_filters(roboport, to_be_deconstructed)) do
    count = count + surface.count_entities_filtered(filter)
  end
  return count
end

local function distance_squared(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return dx * dx + dy * dy
end

-- Marks the closest unmarked debris, unless debris in range is already marked.
local function mark_next_debris(roboport)
  if count_debris(roboport, true) > 0 then return end

  local surface = roboport.surface
  local position = roboport.position
  local candidates = {}
  for _, filter in pairs(get_debris_filters(roboport, false)) do
    for _, entity in pairs(surface.find_entities_filtered(filter)) do
      candidates[#candidates + 1] = { entity = entity, distance = distance_squared(entity.position, position) }
    end
  end
  table.sort(candidates, function(a, b) return a.distance < b.distance end)

  -- Some entities refuse the order (e.g. not minable), so fall through to the next closest.
  for _, candidate in pairs(candidates) do
    if candidate.entity.order_deconstruction(roboport.force) then return end
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
