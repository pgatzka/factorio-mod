-- Shows the amount of debris inside a roboport's construction range
-- in the roboport's info panel while a player hovers over it.

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

local function count_debris(roboport)
  local radius = roboport.logistic_cell.construction_radius
  local position = roboport.position
  local area = {
    { position.x - radius, position.y - radius },
    { position.x + radius, position.y + radius },
  }
  local surface = roboport.surface
  local count = surface.count_entities_filtered({ area = area, type = { "item-entity", "tree", "cliff" } })
  local rocks = get_rock_names()
  if #rocks > 0 then
    count = count + surface.count_entities_filtered({ area = area, name = rocks })
  end
  return count
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
