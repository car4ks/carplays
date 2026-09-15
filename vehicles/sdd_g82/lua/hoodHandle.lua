local M = {}

local function s()
    local state = {
        trunkHandleAllowed = true,
        handleTimer = 0,
        lastCouplerState = 0,
        lastInputState = 0,
        lastOutputState = 0
    }
    
    local HANDLE_INTERVAL = 0.4
    
    -- Cache electrics values to reduce table lookups
    local electricsCache = {
        couplerDetached = 0,
        handlePressed = 0
    }
    
    local function setElectricValue(key, value)
        if electrics.values[key] ~= value then
            electrics.values[key] = value
        end
    end
    
    local function resetElectrics()
        setElectricValue("trunkHandleElectric", 0)
        setElectricValue("trunkHandle", 0)
    end
    
    local function updateElectricsCache()
        electricsCache.couplerDetached = electrics.values.hoodCatchCoupler_notAttached or 0
        electricsCache.handlePressed = electrics.values.trunkHandle or 0
    end
    
    local function updateTrunkHandle(dt)
        -- Update cache (lightweight operation)
        updateElectricsCache()
        
        local couplerDetached = electricsCache.couplerDetached == 1
        local handlePressed = electricsCache.handlePressed == 1
        
        if couplerDetached and state.trunkHandleAllowed then
            if handlePressed then
                setElectricValue("trunkHandleElectric", 1)
                state.handleTimer = state.handleTimer + dt
                
                if state.handleTimer >= HANDLE_INTERVAL then
                    setElectricValue("trunkHandleElectric", 0)
                    state.trunkHandleAllowed = false
                end
            end
        elseif not couplerDetached and not state.trunkHandleAllowed then
            -- Reset when coupler is reattached
            state.trunkHandleAllowed = true
            state.handleTimer = 0
        end
        
        -- Update state tracking for potential future optimizations
        state.lastCouplerState = electricsCache.couplerDetached
        state.lastInputState = electricsCache.handlePressed
    end
    
    local function reset()
        state.trunkHandleAllowed = true
        state.handleTimer = 0
        state.lastCouplerState = 0
        state.lastInputState = 0
        state.lastOutputState = 0
        
        -- Clear cache
        electricsCache.couplerDetached = 0
        electricsCache.handlePressed = 0
        
        resetElectrics()
    end
    
    local function init()
        resetElectrics()
        updateElectricsCache()
    end
    
    return {
        update = updateTrunkHandle,
        reset = reset,
        init = init
    }
end

local controller = s()
M.updateGFX = controller.update
M.onReset = controller.reset
M.onInit = controller.init
return M