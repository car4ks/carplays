-- Royal Renderings G82 -- automatic ambient dimming (GE side).
--
-- Decides how much daylight there is and what fraction of full brightness each
-- group of surfaces should sit at. The actual per-frame application lives in
-- the vehicle-side sddg82Dimmer extension, which multiplies each material slot
-- down via obj:setMaterialEmissiveFactor() -- free, immediate, and smooth.
--
-- Because that multiplier can only take brightness away, the materials carry
-- their DAYTIME emissive: each managed material is pinned once to night * gain
-- when the extension loads, and never reloaded again during play. The ~30ms
-- cost of Material:reload() is therefore paid once at load rather than several
-- times per sunset, which is what used to make transitions lag and jump.
--
-- Night values are the source of truth. Screens carry theirs explicitly; every
-- other group has its night value captured off the material before pinning.

local M = {}

local logTag = "sddg82_screenDimmer"

local JBEAM_NAME = "sdd_g82"
local VEHICLE_EXTENSION = "sddg82Dimmer"

-- Sun elevation in degrees at each end of the fade. The night end sits at the
-- horizon: the sun being down guarantees exactly the tuned night values.
local NIGHT_ELEVATION = 0
local DAY_ELEVATION = 10

-- Groups, in the same shape the vehicle side expects. `gain` is how many times
-- brighter than night the group gets in full daylight. `night` is only given
-- where the value cannot be read off the material (the screens were pinned to
-- day brightness by an earlier design, so reading them would capture a day
-- value as if it were night).
local GROUPS = {
  -- iDrive / CarPlay centre screen, pre-LCI and LCI dashes.
  carplay = {
    gain = 25.7,
    materials = {"sdd_g82_screen", "sdd_g82_screen_lci"},
  },
  -- Instrument cluster. Night values are captured off the materials: unlike the
  -- F82 these have never been pinned to a daytime value, so what the material
  -- carries IS the night value.
  --
  -- Deliberately NOT listed: sdd_g82_screen2, sdd_g82_gauge_lci,
  -- sdd_g82_consolescreen, sdd_g82_shiftscreen, sdd_g82_steerscreen. All of them
  -- have emissiveFactor 0 0 0 on every layer, so captureBase finds no base and
  -- skips them -- listing them would imply they dim when they cannot. Give one an
  -- emissive value and it can be added here. There is no sdd_g82_climatescreen
  -- material at all; that screen is a webview texture target, not a material.
  clusterScreens = {
    gain = 10.0,
    materials = {"sdd_g82_gauge_on", "sdd_g82_gauges_lci"},
  },
  -- Headlight housings and glass, across the pre-LCI and LCI variants. Pinned to
  -- night * gain so DAYLIGHT is brighter while night multiplies back to exactly
  -- the value the material already had -- night is unchanged by design.
  --
  -- Not listed, because they carry no emissiveFactor on any layer and so cannot
  -- be scaled: sdd_g82_headlight_lci_aluminum_on(_intense),
  -- sdd_g82_headlightstickers_glow_on(_intense).
  headlights = {
    gain = 50.0,
    materials = {
      "sdd_g82_headlight_blue_on", "sdd_g82_headlight_blue_on_intense",
      "sdd_g82_headlight_glossblack_on", "sdd_g82_headlight_glossblack_on_intense",
      "sdd_g82_headlight_matteblack_on", "sdd_g82_headlight_matteblack_on_intense",
      "sdd_g82_headlight_lci_blue_on", "sdd_g82_headlight_lci_glossblack_on",
      "sdd_g82_headlight_lci_matteblack_on",
      "sdd_g82_headlightglass_glow_on", "sdd_g82_headlightglass_glow_on_intense",
      "sdd_g82_headlightglass_lci_on", "sdd_g82_headlightglass_lci_on_intense",
    },
  },
  -- Rear lighting: tail/brake glass, the CSL laser tails and the illuminated
  -- badge. Pinned to night * gain, so daylight is brighter and night multiplies
  -- back to exactly the authored value.
  --
  -- No nightScale here, unlike the F82's taillights group: nightScale lifts the
  -- NIGHT end, and night is meant to be unchanged.
  --
  -- Not listed, no emissiveFactor to scale: sdd_g82_tlights_on_intense. And
  -- sdd_g82_csllights_on_intense does not exist as a material at all.
  taillights = {
    gain = 20.0,
    materials = {
      "sdd_g82_tlights_on",
      "sdd_g82_csllights_on",
      "sdd_g82_taillightlogo_on",
    },
  },
  -- Daytime running lights, white and amber. Turn signals (sdd_g82_drl_signal,
  -- sdd_g82_drlglass_signal) are deliberately excluded: separate function, and
  -- they already sit far hotter than the steady DRLs.
  drl = {
    gain = 32.0,
    materials = {
      "sdd_g82_drl_w", "sdd_g82_drl_y",
      "sdd_g82_drlglass", "sdd_g82_drlglass_y",
    },
  },
  -- Interior ambient lighting: dash underglow, door underglow, cabin lamps.
  --
  -- These are NOT material-driven. sdd_g82_underglow carries no emissiveFactor
  -- at all, and the light itself comes from SPOTLIGHT props, whose brightness
  -- cannot be written at runtime. So this group owns no materials -- it exists
  -- purely to produce a target, which the vehicle side republishes as electrics
  -- that the props are driven from.
  --
  -- nightFactor instead of gain: the materials/props already sit at their
  -- correct DAY value, so nothing gets pinned and daylight is a no-op. Night
  -- multiplies down to this fraction.
  interior = {
    nightFactor = 0.0001,
    materials = {},
  },
}
local UPDATE_INTERVAL = 0.1   -- seconds between sun checks
local RESEND_INTERVAL = 3     -- re-push even if unchanged, to catch respawns
local MIN_DELTA = 0.004       -- smaller target moves aren't worth a message

-- Pinning happens once, when the extension loads or a vehicle spawns. There is
-- no second "night" pin any more, so nothing reloads a material during play --
-- see MAX_GAIN below for why that became possible.
local PIN_INTERVAL = 0.05
local PIN_BATCH = 3

-- The per-slot multiplier is 8-bit, so a gain of G leaves only 255/G levels to
-- represent night. At G=50 that is 5 levels, and once a light's own glow
-- fraction folds in it rounds to 2 -- a 20% error, which is what used to make
-- the headlights sit visibly dimmer than their tuned night value.
--
-- The old answer was a second pinned mode that rewrote every material at dusk
-- so night could be exact. That rewrite is ~30ms per material and was the sole
-- cause of the time-of-day stutter.
--
-- At G<=16 the worst-case night error is 2.4%, which is not visible, so the
-- second mode is gone entirely. Daylight is capped at 16x night in exchange --
-- with bloom removed from the game, higher gains clipped to the same flat white
-- anyway, so this costs nothing on screen.
-- Do NOT raise this. Tried 64 on 2026-08-08 and it was visibly too bright at
-- night, even though the GROUP target quantises cleanly there (255/64 = 4 almost
-- exactly, a 0.39% error -- same as 16).
--
-- The group target is not what reaches the engine. The vehicle side pushes
-- engine_glow_fraction * ambient, and THAT product is what gets quantised to
-- 1/255. At gain 64 ambient is 0.0156, so any slot whose own glow fraction is
-- below 1 collapses into the bottom few bytes and rounds UP hard: a fraction of
-- 0.2 wants 0.0031 and gets 1/255 = 0.0039, i.e. 26% too bright. Higher gain
-- makes every partially-lit slot brighter at night, not dimmer.
--
-- 16 keeps the worst case near 2.4%, which is not visible. That is the whole
-- reason for the cap -- it is about the composed per-slot value, not the group
-- target on its own.
local MAX_GAIN = 16

local updateAccum = 0
local resendAccum = 0
local pinAccum = 0
local pinQueue = {}
local pinned = false
local pinWrites = 0     -- materials actually rewritten this pass
local pinSeen = 0       -- materials found (written or already correct)
local lastTargets = {}

-- Night values, keyed by material -> list of {layer, r, g, b}. On _G so an
-- extension reload cannot re-capture an already-pinned day value as night.
_G.__sddg82GlowBases = _G.__sddg82GlowBases or {}
-- Clamp every configured gain to what 8-bit precision can carry at night.
for _, group in pairs(GROUPS) do
  if group.gain and group.gain > MAX_GAIN then group.gain = MAX_GAIN end
end

local bases = _G.__sddg82GlowBases

-- === Helpers =============================================================

local function sunElevation()
  local sunsky = scenetree.findObject("sunsky")
  if not sunsky then return nil end
  return tonumber(sunsky.elevation)
end

local function daylightFactor()
  local sunsky = scenetree.findObject("sunsky")
  if not sunsky then return nil end

  local elevation = tonumber(sunsky.elevation)
  if not elevation then return nil end

  local t = (elevation - NIGHT_ELEVATION) / (DAY_ELEVATION - NIGHT_ELEVATION)
  t = math.max(0, math.min(1, t))
  return t * t * (3 - 2 * t) -- smoothstep, so dusk and dawn ease in and out
end

local function captureBase(name, explicit)
  if bases[name] then return bases[name] end

  if explicit then
    bases[name] = {{layer = 0, r = explicit[1], g = explicit[2], b = explicit[3]}}
    return bases[name]
  end

  local mat = scenetree.findObject(name)
  if not mat then return nil end

  local layers = {}
  for i = 0, 3 do
    local field = mat:getField("emissiveFactor", i)
    if field and field ~= "" then
      local r, g, b = field:match("^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
      r, g, b = tonumber(r), tonumber(g), tonumber(b)
      if r and g and b and (r > 0 or g > 0 or b > 0) then
        layers[#layers + 1] = {layer = i, r = r, g = g, b = b}
      end
    end
  end

  if #layers == 0 then return nil end
  bases[name] = layers
  return layers
end

-- What a group's materials are pinned at: night * gain, where the night end can
-- itself be lifted by nightScale. The vehicle multiplies back down by 1/gain
-- after dark, so night lands on base * nightScale.
local function dayScale(group)
  -- nightFactor groups carry their day value already: pinning would multiply an
  -- already-correct material, so the scale is a no-op 1.
  if group.nightFactor then return 1 end
  return group.gain * (group.nightScale or 1)
end

-- True only if some layer is not already at the value we want. getField is
-- free; Material:reload() costs ~30ms, so checking first is what stops a
-- redundant re-pin (a vehicle reset, say) from costing anything at all.
local function needsWrite(mat, layers, scale)
  for _, l in ipairs(layers) do
    -- Compare numerically, not as strings: getField returns the engine's own
    -- formatting ("120 120 120"), which never matches a "%.4f" render of the
    -- same value, so a string compare would report every material as dirty.
    local field = mat:getField("emissiveFactor", l.layer)
    if not field then return true end
    local r, g, b = field:match("^%s*([%-%d%.eE]+)%s+([%-%d%.eE]+)%s+([%-%d%.eE]+)")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not (r and g and b) then return true end
    local want = {l.r * scale, l.g * scale, l.b * scale}
    local have = {r, g, b}
    for i = 1, 3 do
      local tol = math.max(0.001, math.abs(want[i]) * 0.0005)
      if math.abs(have[i] - want[i]) > tol then return true end
    end
  end
  return false
end

local function writeLayers(mat, layers, scale)
  if not needsWrite(mat, layers, scale) then return false end
  for _, l in ipairs(layers) do
    mat:setField("emissiveFactor", l.layer,
      string.format("%.4f %.4f %.4f", l.r * scale, l.g * scale, l.b * scale))
  end
  mat:reload()
  return true
end

-- Queue every managed material to be written at the scale for `mode`.
--
-- "day"   -> night * gain, with the vehicle multiplying back down by 1/gain.
-- "night" -> the base night value, with the vehicle multiplier held at exactly
--            1 so the engine owns the emissive factor just as it does without
--            this mod.
--
-- The night mode exists because setMaterialEmissiveFactor is 8-bit. At gain 50
-- the night multiplier is 5/255, and once the engine's own glow fraction is
-- folded in it rounds to 2/255 instead of 2.5 -- a 20% loss that showed up as
-- the headlights sitting visibly dimmer than their tuned night value. Carrying
-- the night value in the material instead makes it exact.
--
-- Switching modes is seamless: base * gain * (1/gain) equals base * 1, so both
-- states render identically at the moment of the crossing.
local function queuePin()
  pinQueue = {}
  pinWrites = 0
  pinSeen = 0
  for groupName, group in pairs(GROUPS) do
    local scale = dayScale(group)
    for _, name in ipairs(group.materials) do
      pinQueue[#pinQueue + 1] = {name = name, scale = scale,
                                 explicit = group.night and group.night[name] or nil}
    end
  end
  pinned = false
end

local function drainPin(dt)
  if #pinQueue == 0 then
    if not pinned then
      -- Only count as pinned if materials were actually there to write. The
      -- extension loads with the mod, which on a fresh game is long before any
      -- level or vehicle exists -- every lookup fails, and marking it done then
      -- would leave the materials never pinned while the vehicle side still
      -- multiplied them down. That is the "works for me, broken for everyone
      -- else" case: it only worked here because a car was always already
      -- spawned when I reloaded.
      if pinSeen > 0 then
        pinned = true
        log("I", logTag, string.format("pinned: %d rewritten, %d already correct", pinWrites, pinSeen - pinWrites))
      end
    end
    return
  end
  -- Urgent only when the materials carry night values while the sun is actually
  -- up: that combination reads as too dim until the queue finishes. The reverse
  -- (day values at night) is already correct, so it can take its time.
  pinAccum = pinAccum + dt
  if pinAccum < PIN_INTERVAL then return end
  pinAccum = 0

  for _ = 1, PIN_BATCH do
    local job = table.remove(pinQueue, 1)
    if not job then break end
    local layers = captureBase(job.name, job.explicit)
    if layers then
      local mat = scenetree.findObject(job.name)
      if mat then
        if writeLayers(mat, layers, job.scale) then pinWrites = pinWrites + 1 end
        pinSeen = pinSeen + 1
      end
    end
  end
end

-- The vehicle's updateGFX is frozen while the simulation is paused, which is
-- exactly the state you are in with the environment/time-of-day UI open: the
-- world lighting changes but nothing re-dims until you close the menu. Queued
-- Lua still runs when paused, so we drive the update from here instead.
local function isPaused()
  return simTimeAuthority ~= nil
     and simTimeAuthority.getPause ~= nil
     and simTimeAuthority.getPause() == true
end

local function pushTick(veh, dt)
  veh:queueLuaCommand(string.format(
    'if extensions.sddg82Dimmer then extensions.sddg82Dimmer.tick(%.4f) end', dt))
end

local function pushTargets(veh, targets)
  local parts = {}
  for group, value in pairs(targets) do
    parts[#parts + 1] = string.format("%s=%.4f", group, value)
  end
  veh:queueLuaCommand(string.format(
    'if not extensions.sddg82Dimmer then extensions.load("%s") end ' ..
    'if extensions.sddg82Dimmer then extensions.sddg82Dimmer.setTargets({%s}) end',
    VEHICLE_EXTENSION, table.concat(parts, ",")))
end

-- === Lifecycle ===========================================================

function M.onUpdate(dtReal)
  drainPin(dtReal)

  updateAccum = updateAccum + dtReal
  if updateAccum < UPDATE_INTERVAL then return end
  updateAccum = 0

  local daylight = daylightFactor()
  if not daylight then return end

  resendAccum = resendAccum + UPDATE_INTERVAL
  local force = resendAccum >= RESEND_INTERVAL
  if force then resendAccum = 0 end

  -- Fraction of the pinned value each group should sit at. In night mode the
  -- material already holds the night value, so the multiplier is exactly 1 and
  -- the engine's own emissive factor is left untouched -- no 8-bit rounding.
  local targets = {}
  for groupName, group in pairs(GROUPS) do
    if group.nightFactor then
      -- day = 1 (untouched), night = nightFactor
      targets[groupName] = group.nightFactor + (1 - group.nightFactor) * daylight
    else
      local scale = 1 + (group.gain - 1) * daylight
      targets[groupName] = scale / group.gain
    end
  end

  local changed = force
  if not changed then
    for groupName, value in pairs(targets) do
      if lastTargets[groupName] == nil or math.abs(lastTargets[groupName] - value) >= MIN_DELTA then
        changed = true
        break
      end
    end
  end

  -- While paused the vehicle cannot step itself, so keep ticking it regardless
  -- of whether the target moved -- that is what lets an in-progress fade finish
  -- and a time-of-day change show up with the menu still open.
  local paused = isPaused()
  if paused then
    for _, veh in ipairs(getAllVehicles()) do
      if veh:getJBeamFilename() == JBEAM_NAME then
        pushTick(veh, UPDATE_INTERVAL)
      end
    end
  end

  if not changed then return end
  lastTargets = targets

  for _, veh in ipairs(getAllVehicles()) do
    if veh:getJBeamFilename() == JBEAM_NAME then
      pushTargets(veh, targets)
    end
  end
end

-- Re-pin whenever a level or a G82 actually appears. The extension loads with
-- the mod, which on a fresh game start is long before any level exists, so the
-- first pass finds no materials at all. Without these hooks the materials would
-- stay at their raw file values while the vehicle side kept multiplying them
-- down -- correct on a machine where a car was already spawned, broken on a
-- clean start.
local function repin()
  queuePin()
  lastTargets = {}
end

local function repinIfG82(vehId)
  local veh = be:getObjectByID(vehId)
  if veh and veh:getJBeamFilename() == JBEAM_NAME then repin() end
end

function M.onVehicleSpawned(vehId) repinIfG82(vehId) end
function M.onVehicleResetted(vehId) repinIfG82(vehId) end
function M.onClientPostStartMission() repin() end

-- Put the night values back so the next load captures night, not a pinned day
-- value, and so the car does not sit blazing if the extension is unloaded.
function M.onExtensionUnloaded()
  for name, layers in pairs(bases) do
    local mat = scenetree.findObject(name)
    if mat then writeLayers(mat, layers, 1) end
  end
end

-- === Tuning ==============================================================
-- Gains are how many times brighter than night a group gets in full daylight.
-- Changing one re-pins that group's materials; night is unaffected.
function M.setGain(groupName, value)
  local group = GROUPS[groupName]
  if not group then return {error = "unknown group: " .. tostring(groupName)} end
  group.gain = tonumber(value) or group.gain

  local scale = dayScale(group)
  for _, name in ipairs(group.materials) do
    local layers = captureBase(name, group.night and group.night[name] or nil)
    if layers then
      local mat = scenetree.findObject(name)
      if mat then writeLayers(mat, layers, scale) end
    end
  end
  lastTargets = {}
  return {group = groupName, gain = group.gain, nightScale = group.nightScale or 1}
end

function M.setDrlGain(value) return M.setGain("drl", value) end
function M.setHeadlightGain(value) return M.setGain("headlights", value) end
function M.setTaillightGain(value) return M.setGain("taillights", value) end

-- Lift (or lower) a group's night end. 1.0 is the material's own value; 1.35
-- means 35% brighter at night, and daylight rides on top via the gain.
function M.setNightScale(groupName, value)
  local group = GROUPS[groupName]
  if not group then return {error = "unknown group: " .. tostring(groupName)} end
  group.nightScale = tonumber(value) or group.nightScale
  return M.setGain(groupName, group.gain)
end
-- Tune a nightFactor group's night end live. 1.0 = no dimming at all, 0 = fully
-- dark. The interior props sit at lightBrightness 5.0, so the light you actually
-- see at night is roughly 5.0 * ignitionLevel * nightFactor.
function M.setNightFactor(groupName, value)
  local group = GROUPS[groupName]
  if not group then return {error = "unknown group: " .. tostring(groupName)} end
  if not group.nightFactor then return {error = groupName .. " is a gain group, use setGain"} end
  group.nightFactor = tonumber(value) or group.nightFactor
  lastTargets = {}
  return {group = groupName, nightFactor = group.nightFactor}
end
function M.setInteriorNightFactor(value) return M.setNightFactor("interior", value) end

function M.setSignalGain(value) return M.setGain("signals", value) end
function M.setMotecGain(value) return M.setGain("motec", value) end
function M.setCarplayGain(value) return M.setGain("carplay", value) end
function M.setClusterScreenGain(value) return M.setGain("clusterScreens", value) end
function M.setClusterGain(value) return M.setGain("cluster", value) end
function M.setButtonGain(value) return M.setGain("buttons", value) end

function M.getState()
  local sunsky = scenetree.findObject("sunsky")
  local gains, live = {}, {}
  for groupName, group in pairs(GROUPS) do
    gains[groupName] = group.gain or ("nightFactor=" .. tostring(group.nightFactor))
    local first = group.materials[1]
    if not first then live[groupName] = "(no materials - electric-driven)" end
    local mat = first and scenetree.findObject(first)
    local base = first and bases[first] and bases[first][1]
    if first then live[groupName] = string.format("%s night=%s pinned=%s", first,
      base and string.format("%.4f", base.r) or "none",
      mat and (mat:getField("emissiveFactor", base and base.layer or 0) or "?"):match("^[%-%d%.]+") or "absent") end
  end
  return {
    elevation = sunsky and tonumber(sunsky.elevation) or nil,
    daylight = daylightFactor(),
    gains = gains,
    targets = lastTargets,
    pinned = pinned,
    pinPending = #pinQueue,
    sample = live,
  }
end

function M.onExtensionLoaded()
  lastTargets = {}
  queuePin()
  log("I", logTag, "G82 ambient dimming loaded")
  return true
end

return M
