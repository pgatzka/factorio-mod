-- Gives the mod under test something to do during the pull request checks:
-- a roboport with debris around it. Without it the mod's scripts would load
-- but hardly run, and script errors would go unnoticed.

-- The mod visits a lone roboport within its first 600 ticks.
local CHECK_TICK = 700

script.on_init(function()
  local surface = game.surfaces[1]
  surface.request_to_generate_chunks({ 0, 0 }, 3)
  surface.force_generate_chunk_requests()

  -- Clear the scene first so the debris below is the only debris in range.
  for _, entity in pairs(surface.find_entities_filtered({ area = { { -64, -64 }, { 64, 64 } } })) do
    if entity.type ~= "character" then entity.destroy() end
  end

  surface.create_entity({ name = "roboport", position = { 0, 0 }, force = "player", raise_built = true })
  for i = 1, 5 do
    surface.create_entity({ name = "tree-01", position = { 10 + i * 2, 10 } })
  end
  surface.create_entity({ name = "big-rock", position = { -15, -15 } })
  surface.spill_item_stack({ position = { 5, -5 }, stack = { name = "iron-plate", count = 5 } })
end)

script.on_event(defines.events.on_tick, function(event)
  if event.tick ~= CHECK_TICK then return end
  local marked = game.surfaces[1].count_entities_filtered({
    area = { { -55, -55 }, { 55, 55 } },
    to_be_deconstructed = true,
  })
  if marked == 0 then
    error("ci-harness: the roboport marked no debris within " .. CHECK_TICK .. " ticks")
  end
  log("ci-harness: " .. marked .. " piece(s) of debris marked")
end)
