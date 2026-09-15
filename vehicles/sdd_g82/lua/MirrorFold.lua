local M = {}

local function init()
   electrics.values.royalmirrorfold = 0
end

local function reset()
   init()
end

local function updateGFX(dt)
   if electrics.values.ignitionLevel == 2 or electrics.values.ignitionLevel == 1 then
         electrics.values.royalmirrorfold = 0
      else
      electrics.values.royalmirrorfold = 1
   end
end

M.onInit = init
M.onReset = init
M.updateGFX = updateGFX

return M