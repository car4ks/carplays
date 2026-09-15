local M = {}

local blowerLevel = 0
local lastBlowerUp = 0
local lastBlowerDown = 0
local savedBlowerLevel = 1
local ignitionWasOn = false

local blowerSoundSources = {}
local blowerSoundPath = "/vehicles/sdd_f87/sounds/blower_loop.ogg"
local blowerNodes = { "dsh1", "dsh1l", "dsh1r", "dsh2", "dsh2l", "dsh2r" }

local function resolveNodeID(nodeName)
  local v = _G.v
  if not v or not v.data or not v.data.nodes then return 0 end
  for _, node in pairs(v.data.nodes) do
    if node.name == nodeName then return node.cid end
  end
  return 0
end

local function startBlowerSounds()
  if #blowerSoundSources == 0 then
    for _, nodeName in ipairs(blowerNodes) do
      local nodeId = resolveNodeID(nodeName)
      local safeName = blowerSoundPath:gsub("/", "_") .. "_" .. nodeId
      local sfx = obj:createSFXSource(blowerSoundPath, "AudioDefaultLoop3D", safeName, nodeId)
      if sfx then
        obj:setVolumePitch(sfx, 0.3, 1.0)
        obj:playSFX(sfx)
        table.insert(blowerSoundSources, sfx)
      end
    end
  end
end

local function stopBlowerSounds()
  for _, sfx in ipairs(blowerSoundSources) do
    obj:stopSFX(sfx)
    obj:deleteSFXSource(sfx)
  end
  blowerSoundSources = {}
end

local function updateBlowerVolumes()
  local volume = math.min(1.0, blowerLevel / 7)
  for _, sfx in ipairs(blowerSoundSources) do
    obj:setVolumePitch(sfx, volume, 1.0)
  end
end

local function updateGFX(dt)
  local ignition = electrics.values.ignitionLevel or 0
  local up = electrics.values.blower_up or 0
  local down = electrics.values.blower_down or 0

  if ignition > 1 then
    if not ignitionWasOn then
      blowerLevel = savedBlowerLevel
      ignitionWasOn = true
    end
    
    if up == 1 and lastBlowerUp == 0 then
      blowerLevel = math.min(blowerLevel + 1, 7)
    end

    if down == 1 and lastBlowerDown == 0 then
      blowerLevel = math.max(blowerLevel - 1, 0)
    end

    savedBlowerLevel = blowerLevel
  else
    blowerLevel = 0
    ignitionWasOn = false
  end

  for i = 1, 7 do
    electrics.values["blower_" .. i] = (i <= blowerLevel) and 1 or 0
  end

  if blowerLevel > 0 then
    startBlowerSounds()
    updateBlowerVolumes()
  else
    stopBlowerSounds()
  end

  lastBlowerUp = up
  lastBlowerDown = down
end

local function onReset()
  stopBlowerSounds()
  blowerLevel = 0
  savedBlowerLevel = 1
  lastBlowerUp = 0
  lastBlowerDown = 0
  ignitionWasOn = false
end

M.updateGFX = updateGFX
M.onReset = onReset
return M