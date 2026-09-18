-- Shows the amount of debris inside a roboport's construction range
-- in the roboport's info panel while a player hovers over it, and lets
-- roboports mark that debris for deconstruction, limited by a map setting.

local MAX_MARKED_SETTING = "factorio-mod-max-marked-debris"

-- At most one roboport is visited per tick, so the time spent per tick does
-- not grow with the number of roboports. Visits are spaced out so that every
-- roboport is visited about once per VISIT_PERIOD ticks; with more roboports
-- than that, the time between two visits of a roboport grows instead.
local VISIT_PERIOD = 600

-- How many marked entities beyond the limit a visit looks at before it
-- fetches all of them; see count_marked.
local MARKED_SLACK = 20

-- Thickness of the strips used to find debris that overlaps the range's edge.
local EDGE = 0.01

local debris

-- Everything about debris that follows from the prototypes alone.
local function get_debris()
  if debris then return debris end
  debris = {
    -- Trees and rocks: robots can always remove them.
    plain_names = {},
    -- Cliff name -> name of the item that destroys it.
    cliff_explosives = {},
    item_names = {},
    all_names = {},
    -- Upper bound for the distance between the position of a piece of debris
    -- and any point of its collision box. Cliffs have a collision box per
    -- orientation that the prototype does not expose, hence the generous
    -- floor. A margin that is too large only makes fewer searches cheap; one
    -- that is too small would let debris outside the range slip in.
    margin = 4,
  }
  local function add(type, names, check)
    for name, prototype in pairs(prototypes.get_entity_filtered({ { filter = "type", type = type } })) do
      if not check or check(prototype) then
        if names then names[#names + 1] = name end
        debris.all_names[#debris.all_names + 1] = name
        local box = prototype.collision_box
        -- Boxes can be rotated, so allow for their diagonal.
        local extent = math.max(-box.left_top.x, -box.left_top.y, box.right_bottom.x, box.right_bottom.y) * 1.5 + 0.1
        debris.margin = math.max(debris.margin, extent)
      end
    end
  end
  add("tree", debris.plain_names)
  -- Rocks share the "simple-entity" type with other entities, so they are
  -- identified by the same prototype flag the deconstruction planner uses.
  add("simple-entity", debris.plain_names, function(prototype)
    return prototype.count_as_rock_for_filtered_deconstruction
  end)
  add("item-entity", debris.item_names)
  add("cliff")
  for name, prototype in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "cliff" } })) do
    debris.cliff_explosives[name] = prototype.cliff_explosive_prototype
  end
  return debris
end

local function get_construction_range(roboport)
  local radius = roboport.logistic_cell.construction_radius
  local position = roboport.position
  return {
    left = position.x - radius,
    top = position.y - radius,
    right = position.x + radius,
    bottom = position.y + radius,
  }
end

local function to_area(range)
  return { { range.left, range.top }, { range.right, range.bottom } }
end

-- Area searches match every entity whose collision box touches the area,
-- which includes debris that sits outside the construction range and merely
-- overlaps its edge. Debris is in range only when its position is.
local function contains(range, position)
  return position.x >= range.left and position.x < range.right
    and position.y >= range.top and position.y < range.bottom
end

-- The range shrunk by the debris margin: whatever touches it is certainly in
-- range. Nil for ranges too small to have such a part.
local function get_inner_range(range)
  local margin = get_debris().margin
  local inner = {
    left = range.left + margin,
    top = range.top + margin,
    right = range.right - margin,
    bottom = range.bottom - margin,
  }
  if inner.left < inner.right and inner.top < inner.bottom then return inner end
end

-- A single count covers the whole range; the debris that only overlaps the
-- edge from outside is then found along the four edges and taken off again.
local function count_debris(roboport)
  local surface = roboport.surface
  local range = get_construction_range(roboport)
  local names = get_debris().all_names
  if #names == 0 then return 0 end
  local count = surface.count_entities_filtered({ area = to_area(range), name = names })

  local edges = {
    { left = range.left, top = range.top, right = range.left + EDGE, bottom = range.bottom },
    { left = range.right - EDGE, top = range.top, right = range.right, bottom = range.bottom },
    { left = range.left, top = range.top, right = range.right, bottom = range.top + EDGE },
    { left = range.left, top = range.bottom - EDGE, right = range.right, bottom = range.bottom },
  }
  -- Debris at a corner touches two edges but must be taken off only once.
  local seen = {}
  for _, edge in pairs(edges) do
    for _, entity in pairs(surface.find_entities_filtered({ area = to_area(edge), name = names })) do
      local position = entity.position
      if not contains(range, position) then
        local key = entity.name .. "/" .. position.x .. "/" .. position.y
        if not seen[key] then
          seen[key] = true
          count = count - 1
        end
      end
    end
  end
  return count
end

local function network_has_item(network, item)
  for quality in pairs(prototypes.quality) do
    if network.get_item_count({ name = item, quality = quality }) > 0 then return true end
  end
  return false
end

local search_names = {}

-- The names a roboport searches for: `pieces` are trees, rocks and the cliffs
-- its network holds explosives for; `all` adds the items on the ground when
-- there is a network that could store them. Debris its robots cannot remove
-- is left out, so it is neither marked nor counted toward the limit. The
-- lists are kept per combination, as building them for every visit would
-- cost more than the searches.
local function get_search_names(network)
  local cliffs = {}
  if network then
    local available = {}
    for cliff, explosive in pairs(get_debris().cliff_explosives) do
      if available[explosive] == nil then available[explosive] = network_has_item(network, explosive) end
      if available[explosive] then cliffs[#cliffs + 1] = cliff end
    end
  end

  local key = (network and "network/" or "none/") .. table.concat(cliffs, "/")
  local names = search_names[key]
  if names then return names end

  names = { pieces = {}, all = {} }
  for _, name in pairs(get_debris().plain_names) do names.pieces[#names.pieces + 1] = name end
  for _, name in pairs(cliffs) do names.pieces[#names.pieces + 1] = name end
  for _, name in pairs(names.pieces) do names.all[#names.all + 1] = name end
  if network then
    for _, name in pairs(get_debris().item_names) do names.all[#names.all + 1] = name end
  end
  search_names[key] = names
  return names
end

-- Items on the ground can only be removed while the network has storage
-- space for them. The answer is remembered per kind of item, so a visit asks
-- the network once per kind instead of once per entity.
local function always()
  return true
end

local function get_item_check(network)
  local removable = {}
  return function(entity)
    if entity.type ~= "item-entity" then return true end
    local stack = entity.stack
    local key = stack.name .. "/" .. stack.quality.name
    if removable[key] == nil then
      removable[key] = network.select_drop_point({ stack = stack }) ~= nil
    end
    return removable[key]
  end
end

-- Counts the marked debris that occupies the roboport's limit, up to `limit`.
-- Marked debris is normally rare, so it is fetched in one search and checked
-- piece by piece. The search stops a bit beyond the limit; only when that was
-- not enough to tell (many marked pieces that do not count) all are fetched.
local function count_marked(surface, range, names, is_removable, limit)
  local filter = { area = to_area(range), name = names, to_be_deconstructed = true, limit = limit + MARKED_SLACK }
  local entities = surface.find_entities_filtered(filter)
  local function count()
    local marked = 0
    for _, entity in pairs(entities) do
      if contains(range, entity.position) and is_removable(entity) then
        marked = marked + 1
        if marked == limit then break end
      end
    end
    return marked
  end
  local marked = count()
  if marked < limit and #entities == filter.limit then
    filter.limit = nil
    entities = surface.find_entities_filtered(filter)
    marked = count()
  end
  return marked
end

-- Marks up to `remaining` unmarked entities matching the filter and returns
-- what is left to mark. The inner part of the range is searched first: no
-- more entities than needed are fetched there, which keeps a visit cheap even
-- when the range is full of trees. Only when that was not enough (little
-- debris left, or entities were passed over because they are unremovable or
-- refuse the order, e.g. not minable) the whole range is searched.
local function mark(roboport, range, filter, is_removable, remaining)
  local surface = roboport.surface
  local force = roboport.force
  filter.to_be_deconstructed = false

  local inner = get_inner_range(range)
  if inner then
    filter.area = to_area(inner)
    filter.limit = remaining
    for _, entity in pairs(surface.find_entities_filtered(filter)) do
      if is_removable(entity) and entity.order_deconstruction(force) then
        remaining = remaining - 1
        if remaining == 0 then return 0 end
      end
    end
  end

  filter.area = to_area(range)
  filter.limit = nil
  for _, entity in pairs(surface.find_entities_filtered(filter)) do
    if contains(range, entity.position) and is_removable(entity) and entity.order_deconstruction(force) then
      remaining = remaining - 1
      if remaining == 0 then return 0 end
    end
  end
  return remaining
end

-- Marks unmarked debris until the map setting's limit of marked debris in
-- range is reached; which pieces get marked does not matter. Most visits find
-- nothing to do, so those are kept cheapest.
local function mark_next_debris(roboport)
  local limit = settings.global[MAX_MARKED_SETTING].value
  if limit == 0 then return end

  local surface = roboport.surface
  local range = get_construction_range(roboport)
  local area = to_area(range)
  local all_names = get_debris().all_names
  if #all_names == 0 or surface.count_entities_filtered({ area = area, name = all_names, limit = 1 }) == 0 then return end

  local network = roboport.logistic_network
  local names = get_search_names(network)
  if #names.all == 0 or surface.count_entities_filtered({ area = area, name = names.all, limit = 1 }) == 0 then return end

  local is_removable = network and get_item_check(network) or always
  local remaining = limit - count_marked(surface, range, names.all, is_removable, limit)
  if remaining <= 0 then return end

  -- Items come last: they are the only debris that may need a look at every
  -- piece in range.
  if #names.pieces > 0 then
    remaining = mark(roboport, range, { name = names.pieces }, always, remaining)
  end
  if remaining > 0 and network and #get_debris().item_names > 0 then
    mark(roboport, range, { name = get_debris().item_names }, is_removable, remaining)
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
  storage.visit_credit = 0
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

script.on_event(defines.events.on_tick, function()
  if not storage.roboports then rebuild_roboports() end
  local roboports = storage.roboports
  if #roboports == 0 then return end

  -- Each tick earns the share of a visit that lets all roboports be visited
  -- once per VISIT_PERIOD, but never more than the one visit a tick may make.
  storage.visit_credit = math.min((storage.visit_credit or 0) + #roboports / VISIT_PERIOD, 1)
  if storage.visit_credit < 1 then return end
  storage.visit_credit = storage.visit_credit - 1

  if storage.next_roboport > #roboports then storage.next_roboport = 1 end
  local roboport = roboports[storage.next_roboport]
  if roboport.valid then
    if is_roboport(roboport) then mark_next_debris(roboport) end
    storage.next_roboport = storage.next_roboport + 1
  else
    -- Removed roboport: the last entry takes its place and is visited next.
    roboports[storage.next_roboport] = roboports[#roboports]
    roboports[#roboports] = nil
  end
end)
