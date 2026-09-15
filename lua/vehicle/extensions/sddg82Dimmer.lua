-- Royal Renderings G82 -- vehicle-side ambient dimmer.
--
-- Runs the actual brightness control, every frame, via
-- obj:setMaterialEmissiveFactor(). That is the engine's dynamic-emissive path
-- (the same one materialEmissiveScaling drives for cornering lights): it costs
-- nothing and takes effect immediately, unlike Material:reload() which measures
-- ~30ms and can only be afforded a few times per sunset.
--
-- Because the factor is a 0..1 multiplier it can only take brightness away, so
-- the materials carry their DAYTIME emissive and this scales down toward night.
--
-- The GE side (sddg82_screenDimmer) only decides how much daylight there is and
-- pushes a target per group; the easing and the per-frame application live here
-- so the fade is smooth regardless of how coarsely the target is updated.

local M = {}

M.type = "auxiliary"

local logTag = "sddg82Dimmer"

-- Seconds to travel the FULL brightness range. This is a bounded linear ramp,
-- not exponential smoothing: an exponential approach never quite arrives, so a
-- large time-of-day jump crawled through its last stretch and took roughly 3x
-- this long to look settled. Linear means a swing always completes in at most
-- FADE_TIME, and a small one finishes proportionally sooner.
local FADE_TIME = 0.8

-- Smallest change worth pushing to the engine. The factor is quantised to
-- 1/255 anyway, so anything finer is wasted work.
local EPSILON = 1 / 512

-- Which glowMap `on` / `on_intense` materials belong to which group. Slots are
-- resolved from these at init: a slot is claimed if either of its lit materials
-- is in the list.
local GROUP_MATERIALS = {
  carplay = {"sdd_g82_screen", "sdd_g82_screen_lci"},
  clusterScreens = {"sdd_g82_gauge_on", "sdd_g82_gauges_lci"},
  headlights = {
    "sdd_g82_headlight_blue_on", "sdd_g82_headlight_blue_on_intense",
    "sdd_g82_headlight_glossblack_on", "sdd_g82_headlight_glossblack_on_intense",
    "sdd_g82_headlight_matteblack_on", "sdd_g82_headlight_matteblack_on_intense",
    "sdd_g82_headlight_lci_blue_on", "sdd_g82_headlight_lci_glossblack_on",
    "sdd_g82_headlight_lci_matteblack_on",
    "sdd_g82_headlightglass_glow_on", "sdd_g82_headlightglass_glow_on_intense",
    "sdd_g82_headlightglass_lci_on", "sdd_g82_headlightglass_lci_on_intense",
  },
  taillights = {
    "sdd_g82_tlights_on",
    "sdd_g82_csllights_on",
    "sdd_g82_taillightlogo_on",
  },
  drl = {
    "sdd_g82_drl_w", "sdd_g82_drl_y",
    "sdd_g82_drlglass", "sdd_g82_drlglass_y",
  },
}
local slots = {}    -- [group] = array of msc
local current = {}  -- [group] = applied fraction
local target = {}   -- [group] = wanted fraction
local applied = {}  -- [group] = last value actually pushed to the engine
local frameCount = 0 -- diagnostic: how many times updateGFX has run

local function buildSlots()
  slots = {}
  current = {}
  target = {}
  applied = {}

  -- The interior group owns no materials (see the GE side): it is published as
  -- electrics rather than applied to material slots, so seed it by hand or the
  -- easing loop below would never see it.
  current.interior = current.interior or 1
  target.interior = target.interior or 1

  local lookup = {}
  for group, names in pairs(GROUP_MATERIALS) do
    slots[group] = {}
    -- Start at full brightness: the materials hold their daytime value, and
    -- the GE side corrects this within a tick of the vehicle appearing.
    current[group] = 1
    target[group] = 1
    applied[group] = nil
    for _, name in ipairs(names) do lookup[name] = group end
  end

  if not (v.data and v.data._materials and v.data._materials.triggers) then
    log("W", logTag, "no material triggers on this vehicle")
    return
  end

  local claimed = {}
  for _, t in ipairs(v.data._materials.triggers) do
    local group = (t.on and lookup[t.on]) or (t.on_intense and lookup[t.on_intense])
    if group and t.msc and not claimed[t.msc] then
      claimed[t.msc] = true
      -- Most of these slots already have their emissive factor driven by the
      -- engine: that is how glow intensity works, including the RoyalTriggers
      -- proximity fade. So we do not overwrite it -- we evaluate the same glow
      -- value material.lua does and multiply our ambient factor on top, which
      -- keeps the hover fade intact while still dimming with the sun.
      -- Stash the untouched maxes the first time this trigger is seen. We
      -- inflate the live fields to fold ambient into the engine's own maths,
      -- so on a rebuild the live value is no longer the original. `false`
      -- records "there wasn't one" so the check stays idempotent.
      if t.__sddOrigOnMax == nil then
        t.__sddOrigOnMax = t.scaleEmissiveMaterialOnMax or false
        t.__sddOrigOnIntenseMax = t.scaleEmissiveMaterialOnIntenseMax or false
      end

      table.insert(slots[group], {
        msc = t.msc,
        trigger = t,
        evalFunction = t.scaleEmissiveMaterial and t.evalFunction or nil,
        onMax = t.__sddOrigOnMax or nil,
        onIntenseMax = t.__sddOrigOnIntenseMax or nil,
        hasIntense = t.on_intense ~= nil,
      })
    end
  end
end

-- Reproduce material.lua's glow value for a slot: 0 when unlit, up to 1 when
-- fully lit, normalised by whichever max applies. Returns nil when the engine
-- does not drive this slot, in which case the ambient factor stands alone.
local function engineFraction(slot)
  if not slot.evalFunction then return nil end

  local ok, localVal = pcall(slot.evalFunction)
  if not ok or type(localVal) ~= "number" then return nil end
  if localVal <= 0.0001 then return 0 end

  local max = slot.onMax
  if slot.hasIntense and localVal > 0.5 and slot.onIntenseMax then
    max = slot.onIntenseMax
  end
  if not max or max <= 0 then return nil end

  return math.max(0, math.min(1, localVal / max))
end

-- Push a group's ambient factor to every slot it owns, composed with whatever
-- glow value the engine would have written. color() takes 0-255, where 255
-- leaves the material's own emissive untouched.
-- material.lua recomputes the factor for every engine-driven slot whenever any
-- glow electric moves, using localVal / scaleEmissiveMaterialOnMax. It knows
-- nothing about ambient light, so its writes used to flash every button back to
-- full brightness for a frame whenever one was hovered.
--
-- Rather than race it, inflate the max it divides by: with onMax / ambient in
-- there, the engine's own arithmetic lands on localVal / onMax * ambient --
-- exactly the value we want. Both writers now agree and the flash is gone.
local function retuneEngineMax(slot, ambient)
  local t = slot.trigger
  if not t or not slot.onMax then return end
  local safe = math.max(ambient, 1 / 255)
  t.scaleEmissiveMaterialOnMax = slot.onMax / safe
  if slot.onIntenseMax then
    t.scaleEmissiveMaterialOnIntenseMax = slot.onIntenseMax / safe
  end
end

local function push(group, ambient)
  ambient = math.max(0, math.min(1, ambient))
  local changed = applied[group] == nil or math.abs(applied[group] - ambient) > EPSILON
  for _, slot in ipairs(slots[group] or {}) do
    if changed then retuneEngineMax(slot, ambient) end
    local engine = engineFraction(slot)
    local combined = engine and (engine * ambient) or ambient
    local byte = math.floor(combined * 255 + 0.5)
    obj:setMaterialEmissiveFactor(slot.msc, color(byte, byte, byte))
  end
  applied[group] = ambient
end

-- Called from the GE side with the wanted fraction per group, 0..1.
local function setTargets(levels)
  if type(levels) ~= "table" then return end
  for group, value in pairs(levels) do
    if target[group] ~= nil then
      local n = tonumber(value)
      if n then target[group] = math.max(0, math.min(1, n)) end
    end
  end
end

-- Snap everything to its target with no fade. Used on spawn/reset so the car
-- does not visibly ramp from full brightness when it appears at night.
local function snap()
  for group, value in pairs(target) do
    current[group] = value
    push(group, value)
  end
end

-- Interior ambient lighting is prop-driven, not material-driven: the underglow
-- material carries no emissiveFactor, and a SPOTLIGHT prop's brightness cannot
-- be written at runtime. What CAN be scaled is the electric the prop is driven
-- from -- exactly how the filament turn signals fade. So publish the eased
-- ambient factor as electrics and point the props at those instead.
--
-- Multiplying the ORIGINAL electric keeps daylight byte-identical to before
-- (ambient is 1, so x * 1 == x); only night scales down.
local function publishInterior(ambient)
  local e = electrics.values
  e.sdd_g82_ambient = ambient

  -- A prop light's brightness is baked at spawn: meshs.lua calls
  -- plight:setLightArgs(..., prop.lightBrightness, ...) once, and the only
  -- runtime setter (setLightArgsDynamic) is commented out in the engine. The
  -- func electric therefore GATES a light on/off but can never dim it.
  --
  -- So interior dimming is done with two sets of props at different authored
  -- brightnesses, and these electrics pick which set is lit. Crossing at 0.5
  -- daylight means the swap happens mid-dusk, when both are faint anyway.
  local day = (ambient >= 0.5) and 1 or 0
  local ign = e.ignitionLevel or 0
  e.sdd_g82_underglow_day   = ign * day
  e.sdd_g82_underglow_night = ign * (1 - day)
  e.sdd_g82_lampL_day       = (e.lampL or 0) * day
  e.sdd_g82_lampL_night     = (e.lampL or 0) * (1 - day)
  e.sdd_g82_lampR_day       = (e.lampR or 0) * day
  e.sdd_g82_lampR_night     = (e.lampR or 0) * (1 - day)
end

local function updateGFX(dt)
  frameCount = frameCount + 1
  local maxMove = dt / FADE_TIME

  publishInterior(current.interior or 1)

  for group, want in pairs(target) do
    local now = current[group]
    local delta = want - now
    if math.abs(delta) > EPSILON then
      if delta > maxMove then
        now = now + maxMove
      elseif delta < -maxMove then
        now = now - maxMove
      else
        now = want
      end
    else
      now = want
    end
    current[group] = now
    -- Pushed every frame rather than only on change: the engine rewrites these
    -- slots whenever any glow electric moves, and the glow value itself changes
    -- under us as a trigger is hovered. Recomputing is a closure call and a
    -- setter per slot, which is far cheaper than a single Material:reload().
    push(group, now)
  end
end

local function init()
  buildSlots()
  local counts = {}
  for group, list in pairs(slots) do counts[#counts + 1] = group .. "=" .. #list end
  log("I", logTag, "slots resolved: " .. table.concat(counts, " "))
end

-- Material switches and resets can drop the factor; re-assert on reset.
local function reset()
  snap()
end

-- Both entry points: init() is what the vehicle calls when it spawns,
-- onExtensionLoaded() is what extensions.load() calls on a hot reload.
M.init = init
M.onExtensionLoaded = init
M.reset = reset
M.updateGFX = updateGFX
M.setTargets = setTargets
M.snap = snap
M.getSlotCounts = function()
  local out = {}
  for group, list in pairs(slots) do out[group] = #list end
  return out
end
-- Drive one update from outside. updateGFX does not run while the simulation is
-- paused, so with the environment/time-of-day UI open the lighting would change
-- but nothing would re-dim until the game resumed. Queued Lua *does* still run
-- when paused, so the GE side calls this to keep things live.
M.tick = function(dt)
  updateGFX(tonumber(dt) or 0.1)
end
M.getCurrent = function()
  local out = {frames = frameCount}
  for group, value in pairs(current) do out[group] = value end
  return out
end

return M
