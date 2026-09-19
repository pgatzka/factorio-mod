-- Gives the mod under test something to do during the pull request checks:
-- roboports with debris around them. Without it the mod's scripts would load
-- but hardly run, and script errors would go unnoticed.

-- The mod visits each of the two roboports within its first 600 ticks.
local CHECK_TICK = 700

local POWERED = { x = 0, y = 0 }
local UNPOWERED = { x = 320, y = 0 }

local function area_around(center, radius)
  return { { center.x - radius, center.y - radius }, { center.x + radius, center.y + radius } }
end

local function build_scene(surface, center, powered)
  surface.request_to_generate_chunks(center, 3)
  surface.force_generate_chunk_requests()

  -- Clear the scene first so the debris below is the only debris in range.
  for _, entity in pairs(surface.find_entities_filtered({ area = area_around(center, 64) })) do
    if entity.type ~= "character" then entity.destroy() end
  end

  local roboport = surface.create_entity({ name = "roboport", position = center, force = "player", raise_built = true })
  if powered then
    surface.create_entity({ name = "substation", position = { center.x + 4, center.y }, force = "player" })
    surface.create_entity({ name = "electric-energy-interface", position = { center.x + 4, center.y + 3 }, force = "player" })
    roboport.energy = roboport.electric_buffer_size
  end

  for i = 1, 5 do
    surface.create_entity({ name = "tree-01", position = { center.x + 10 + i * 2, center.y + 10 } })
  end
  surface.create_entity({ name = "big-rock", position = { center.x - 15, center.y - 15 } })
  surface.spill_item_stack({ position = { center.x + 5, center.y - 5 }, stack = { name = "iron-plate", count = 5 } })
end

local function count_marked(surface, center)
  return surface.count_entities_filtered({ area = area_around(center, 55), to_be_deconstructed = true })
end

script.on_init(function()
  local surface = game.surfaces[1]
  build_scene(surface, POWERED, true)
  build_scene(surface, UNPOWERED, false)
end)

script.on_event(defines.events.on_tick, function(event)
  if event.tick ~= CHECK_TICK then return end
  local surface = game.surfaces[1]
  local marked = count_marked(surface, POWERED)
  if marked == 0 then
    error("ci-harness: the powered roboport marked no debris within " .. CHECK_TICK .. " ticks")
  end
  local marked_unpowered = count_marked(surface, UNPOWERED)
  if marked_unpowered > 0 then
    error("ci-harness: the unpowered roboport marked " .. marked_unpowered .. " piece(s) of debris")
  end
  log("ci-harness: " .. marked .. " piece(s) of debris marked")
end)
