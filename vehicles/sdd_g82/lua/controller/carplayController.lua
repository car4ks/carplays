local M = {}
M.type = "auxiliary"

local htmlTexture = require("htmlTexture")
local jsonReadFile = jsonReadFile
local jsonWriteFile = jsonWriteFile

-- Local references to frequently used globals
local obj = obj
local electrics = electrics
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local math_floor = math.floor
local math_deg = math.deg
local math_atan2 = math.atan2
local table_insert = table.insert
local table_remove = table.remove
local string_format = string.format
local os_clock = os.clock
local os_time = os.time

local screenMaterialName = nil
local htmlFilePath = nil  
local textureWidth = 1680
local textureHeight = 720
local textureFPS = 30
local name = "carplay"

local settingsFilePath = "/settings/sdd_g82_carplay_settings.json"
local callHistoryFilePath = "/settings/sdd_g82_call_history.json"
local recentAppsFilePath = "/settings/sdd_g82_carplay_recent_apps.json"

local defaultSettings = {
    wallpaper = 1,
    iconTheme = "default"
}

local currentSettings = {}
local callHistory = {}

local updateTimer = 0
local invFPS = 1/20  -- Reduced from 1/30

local lastNavLeft = 0
local lastNavRight = 0
local lastNavUp = 0
local lastNavDown = 0
local lastNavSelect = 0
local lastNavBack = 0
local lastNavHome = 0

local lastPhoneApp = 0

local currentApp = "home"
local selectedAppIndex = 0
local isCarPlayActive = false
local splitViewSelectedPanel = 0

local isInitialized = false

local recentApps = {}
local MAX_RECENT_APPS = 3

local GRID_COLS = 5
local GRID_ROWS = 2
local TOTAL_APPS = 10

local homeApps = {"music", "maps", "phone", "messages", "weather", "settings", "calendar", "podcasts", "audiobooks", "news"}

local messageAudioNodes = { "d14r", "d14l" }
local messageAudioTable = {}
local currentMessageAudio = nil

local phoneAudioTable = {}
local currentPhoneAudio = nil

local nodeIDCache = {}

local dirtyFlags = {
    navigation = false,
    settings = false,
    musicData = false,
    vehicleData = false,
    gpsData = false
}

local lastDataHash = ""
local lastMusicDataHash = ""
local lastHtmlUpdateTime = 0
local HTML_UPDATE_INTERVAL = 0.1  -- Increased from 0.05

local gpsUpdateTimer = 0
local GPS_UPDATE_INTERVAL = 1/60

local gpsData = {
    x = 0,
    y = 0,
    rotation = 0,
    zoom = 150,
    speed = 0,
    ignitionLevel = 0
}

local appNavigationStates = {
    phone = {
        selectedTabIndex = 0,
        selectedItemIndex = 0,
        isInTabBar = false
    },
    messages = {
        selectedConversationIndex = 0,
        inConversationView = false
    },
    weather = {
        selectedWeatherIndex = 0,
        currentView = "current"
    },
    calendar = {
        selectedEventIndex = 0,
        selectedViewIndex = 0,
        inDetailView = false,
        currentView = 'day'
    },
    podcasts = {
        selectedPodcastIndex = 0,
        selectedQueueIndex = 0,
        inQueueView = false,
        selectedHeaderIndex = 2,
        currentView = 'main'
    },
    audiobooks = {
        selectedReadingIndex = 0,
        selectedRecentIndex = 0,
        inReadingView = true,
        selectedHeaderIndex = 1,
        currentView = 'main'
    },
    news = {
        selectedArticleIndex = 0,
        selectedCategoryIndex = 0,
        inArticleView = false
    },
    music = {
        currentNavigationLevel = "main",
        selectedMainControlIndex = 1,
        selectedBottomControlIndex = 0,
        selectedLibraryTabIndex = 3,
        selectedPlaylistIndex = 0,
        selectedSongIndex = 0,
        currentScreen = "nowPlaying"
    }
}

local settingsNavigation = {
    currentPage = 'list',
    selectedListIndex = 0,
    selectedWallpaperIndex = 0,
    selectedIconThemeIndex = 0,
    totalListItems = 3,
    totalWallpapers = 7,
    totalIconThemes = 2
}

local frameMessageQueue = {}
local frameMessageTimer = 0
local FRAME_MESSAGE_INTERVAL = 0.1  -- Increased from 0.05

local function loadRecentApps()
    local appsData = jsonReadFile(recentAppsFilePath)
    if appsData and type(appsData) == "table" and appsData.recentApps and type(appsData.recentApps) == "table" then
        recentApps = {}
        for i, appName in ipairs(appsData.recentApps) do
            if i <= MAX_RECENT_APPS and type(appName) == "string" and appName ~= "" and appName ~= "home" then
                local isValidApp = false
                for _, validApp in ipairs(homeApps) do
                    if validApp == appName then
                        isValidApp = true
                        break
                    end
                end
                if isValidApp then
                    table_insert(recentApps, appName)
                end
            end
        end
    else
        recentApps = {}
    end
end

local function saveRecentApps()
    local dataToSave = {
        recentApps = recentApps,
        lastUpdated = os_time(),
        maxApps = MAX_RECENT_APPS
    }
    jsonWriteFile(recentAppsFilePath, dataToSave)
end

local function resolveNodeID(nodeName)
    if nodeIDCache[nodeName] then
        return nodeIDCache[nodeName]
    end
    
    local v = _G.v
    if not v or not v.data or not v.data.nodes then return 0 end
    for _, node in pairs(v.data.nodes) do
        if node.name == nodeName then
            nodeIDCache[nodeName] = node.cid
            return node.cid
        end
    end
    return 0
end

local function cleanupAllMessageAudio()
    if currentMessageAudio then
        obj:stopSFX(currentMessageAudio)
        currentMessageAudio = nil
    end
    
    for audioFile, sfx in pairs(messageAudioTable) do
        if sfx then
            obj:stopSFX(sfx)
            obj:deleteSFXSource(sfx)
        end
    end
    
    messageAudioTable = {}
end

local function cleanupAllPhoneAudio()
    if currentPhoneAudio then
        obj:stopSFX(currentPhoneAudio)
        currentPhoneAudio = nil
    end
    
    for audioFile, sfx in pairs(phoneAudioTable) do
        if sfx then
            obj:stopSFX(sfx)
            obj:deleteSFXSource(sfx)
        end
    end
    
    phoneAudioTable = {}
end

local function loadMessageAudio(audioFile)
    if not audioFile then return false end
    
    local audioPath = "/vehicles/sdd_g82/carplay/message_audio/" .. audioFile
    
    if not messageAudioTable[audioFile] then
        local nodeId = resolveNodeID(messageAudioNodes[1])
        local safeName = audioFile:gsub("/", "_"):gsub("%.", "_") .. "_msg_" .. nodeId
        
        local sfx = obj:createSFXSource(audioPath, "AudioDefault3D", safeName, nodeId)
        if sfx then
            messageAudioTable[audioFile] = sfx
            return true
        else
            return false
        end
    end
    return messageAudioTable[audioFile] ~= nil
end

local function playMessageAudio(audioFile)
    if not audioFile then return false end
    
    if currentMessageAudio then
        obj:stopSFX(currentMessageAudio)
        currentMessageAudio = nil
    end
    
    if loadMessageAudio(audioFile) then
        local sfx = messageAudioTable[audioFile]
        if sfx then
            obj:setVolumePitch(sfx, 0.8, 1.0)
            obj:playSFX(sfx)
            currentMessageAudio = sfx
            return true
        end
    end
    
    return false
end

local function stopMessageAudio()
    if currentMessageAudio then
        obj:stopSFX(currentMessageAudio)
        currentMessageAudio = nil
    end
end

local function loadPhoneAudio(audioFile)
    if not audioFile then return false end
    
    local audioPath = "/vehicles/sdd_g82/carplay/message_audio/" .. audioFile
    
    if not phoneAudioTable[audioFile] then
        local nodeId = resolveNodeID(messageAudioNodes[1])
        local safeName = audioFile:gsub("/", "_"):gsub("%.", "_") .. "_phone_" .. nodeId
        
        local sfx = obj:createSFXSource(audioPath, "AudioDefault3D", safeName, nodeId)
        if sfx then
            phoneAudioTable[audioFile] = sfx
            return true
        else
            return false
        end
    end
    return phoneAudioTable[audioFile] ~= nil
end

local function playPhoneAudio(audioFile)
    if not audioFile then return false end
    
    if currentPhoneAudio then
        obj:stopSFX(currentPhoneAudio)
        currentPhoneAudio = nil
    end
    
    if loadPhoneAudio(audioFile) then
        local sfx = phoneAudioTable[audioFile]
        if sfx then
            obj:setVolumePitch(sfx, 0.8, 1.0)
            obj:playSFX(sfx)
            currentPhoneAudio = sfx
            return true
        end
    end
    
    return false
end

local function stopPhoneAudio()
    if currentPhoneAudio then
        obj:stopSFX(currentPhoneAudio)
        currentPhoneAudio = nil
    end
    
    local toDelete = {}
    for audioFile, sfx in pairs(phoneAudioTable) do
        if sfx then
            obj:stopSFX(sfx)
            table_insert(toDelete, audioFile)
        end
    end
    
    for _, audioFile in ipairs(toDelete) do
        local sfx = phoneAudioTable[audioFile]
        if sfx then
            obj:deleteSFXSource(sfx)
        end
        phoneAudioTable[audioFile] = nil
    end
end

local function addToRecentApps(appName)
    if not appName or appName == "home" then
        return
    end
    
    local isValidApp = false
    for _, validApp in ipairs(homeApps) do
        if validApp == appName then
            isValidApp = true
            break
        end
    end
    
    if not isValidApp then
        return
    end
    
    for i = #recentApps, 1, -1 do
        if recentApps[i] == appName then
            table_remove(recentApps, i)
            break
        end
    end
    
    table_insert(recentApps, 1, appName)
    
    if #recentApps > MAX_RECENT_APPS then
        for i = #recentApps, MAX_RECENT_APPS + 1, -1 do
            table_remove(recentApps, i)
        end
    end
    
    saveRecentApps()
end

local function launchPhoneApp()
    addToRecentApps("phone")
    
    currentApp = "phone"
    electrics.values.carplayApp = "phone"
    
    appNavigationStates.phone.selectedTabIndex = 0
    appNavigationStates.phone.selectedItemIndex = 0
    appNavigationStates.phone.isInTabBar = false
    
    dirtyFlags.navigation = true
end

local function loadCallHistory()
    local history = jsonReadFile(callHistoryFilePath)
    if history and type(history) == "table" and history.callHistory then
        callHistory = history.callHistory
    else
        callHistory = {}
    end
end

local function saveCallHistory()
    local dataToSave = {
        callHistory = callHistory,
        lastUpdated = os_time()
    }
    jsonWriteFile(callHistoryFilePath, dataToSave)
end

local function parseCallHistoryFromElectrics()
    local historyJson = electrics.values.carplayCallHistory or ""
    if historyJson ~= "" then
        local success, parsedHistory = pcall(function()
            return jsonDecode(historyJson)
        end)
        
        if success and parsedHistory and type(parsedHistory) == "table" then
            callHistory = parsedHistory
            saveCallHistory()
            electrics.values.carplayCallHistory = ""
        end
    end
end

local function loadSettings()
    local settings = jsonReadFile(settingsFilePath)
    if settings then
        currentSettings = settings
    else
        currentSettings = defaultSettings
    end
    
    settingsNavigation.selectedWallpaperIndex = (currentSettings.wallpaper or 1) - 1
    settingsNavigation.selectedIconThemeIndex = (currentSettings.iconTheme == "default") and 0 or 1
    
    electrics.values.carplayWallpaper = currentSettings.wallpaper or 1
    electrics.values.carplayIconTheme = currentSettings.iconTheme or "default"
end

local function saveSettings()
    local success = jsonWriteFile(settingsFilePath, currentSettings)
    if success then
        electrics.values.carplayWallpaper = currentSettings.wallpaper or 1
        electrics.values.carplayIconTheme = currentSettings.iconTheme or "default"
        dirtyFlags.settings = true
    end
end

local function handleSettingsChange()
    local wallpaper = electrics.values.carplayWallpaper or 1
    local iconTheme = electrics.values.carplayIconTheme or "default"
    
    local changed = false
    
    if currentSettings.wallpaper ~= wallpaper then
        currentSettings.wallpaper = wallpaper
        changed = true
    end
    
    if currentSettings.iconTheme ~= iconTheme then
        currentSettings.iconTheme = iconTheme
        changed = true
    end
    
    if changed then
        saveSettings()
    end
end

local function indexTo2D(index)
    return {
        row = math_floor(index / GRID_COLS),
        col = index % GRID_COLS
    }
end

local function coordsTo1D(row, col)
    return row * GRID_COLS + col
end

function sendToFrame(frameId, message)
    if not frameMessageQueue[frameId] then
        frameMessageQueue[frameId] = {}
    end
    table_insert(frameMessageQueue[frameId], message)
end

local function processFrameMessageQueue()
    if screenMaterialName then
        for frameId, messages in pairs(frameMessageQueue) do
            if #messages > 0 then
                local message = messages[#messages]
                local messageScript = string_format(
                    "var frame = document.getElementById('%sFrame'); " ..
                    "if (frame && frame.contentWindow) { " ..
                        "frame.contentWindow.postMessage(%s, '*'); " ..
                    "}",
                    frameId,
                    jsonEncode and jsonEncode(message) or "null"
                )
                htmlTexture.call(screenMaterialName, messageScript)
                frameMessageQueue[frameId] = {}
            end
        end
    end
end

function sendToAllFrames(message)
    local frames = {"music", "phone", "messages", "weather", "settings", "calendar", "podcasts", "audiobooks", "news", "maps"}
    for _, frameId in ipairs(frames) do
        sendToFrame(frameId, message)
    end
end

local function sendNavigationEvent(appName, direction, action)
    if appName and appName ~= "home" then
        sendToFrame(appName, {
            type = 'navigation',
            direction = direction,
            action = action or direction,
            state = appNavigationStates[appName]
        })
        dirtyFlags.navigation = true
    end
end

local function sendSplitViewNavigationEvent(direction)
    if screenMaterialName then
        local navigationScript = string_format(
            "window.postMessage({type: 'navigation', direction: '%s'}, '*');",
            direction
        )
        htmlTexture.call(screenMaterialName, navigationScript)
        dirtyFlags.navigation = true
    end
end

local function handleExitToHome()
    currentApp = "home"
    selectedAppIndex = 0
    
    electrics.values.carplayApp = "home"
    electrics.values.carplaySelectedApp = 0
    electrics.values.settingsActive = 0
    
    appNavigationStates.phone.selectedTabIndex = 0
    appNavigationStates.phone.selectedItemIndex = 0
    appNavigationStates.phone.isInTabBar = false
    
    appNavigationStates.messages.selectedConversationIndex = 0
    appNavigationStates.messages.inConversationView = false
    
    appNavigationStates.weather.selectedWeatherIndex = 0
    appNavigationStates.weather.currentView = "current"
    
    appNavigationStates.calendar.selectedEventIndex = 0
    appNavigationStates.calendar.selectedViewIndex = 0
    appNavigationStates.calendar.inDetailView = false
    
    appNavigationStates.audiobooks.selectedReadingIndex = 0
    appNavigationStates.audiobooks.selectedRecentIndex = 0
    appNavigationStates.audiobooks.inReadingView = true
    appNavigationStates.audiobooks.selectedHeaderIndex = 1
    
    appNavigationStates.news.selectedArticleIndex = 0
    appNavigationStates.news.selectedCategoryIndex = 0
    appNavigationStates.news.inArticleView = false
    
    appNavigationStates.music.currentNavigationLevel = "main"
    appNavigationStates.music.selectedMainControlIndex = 1
    appNavigationStates.music.selectedBottomControlIndex = 0
    appNavigationStates.music.currentScreen = "nowPlaying"
    
    settingsNavigation.currentPage = 'list'
    settingsNavigation.selectedListIndex = 0
    
    dirtyFlags.navigation = true
end

local function handleHTMLExitMessage()
    handleExitToHome()
end

local function handleSteeringWheelInputs()
    local phoneApp = electrics.values.phoneApp or 0
    
    if phoneApp == 1 and lastPhoneApp == 0 then
        launchPhoneApp()
    end
    
    lastPhoneApp = phoneApp
end

local lastLoggedGPS = {x = 0, y = 0, rotation = 0}
local gpsLogTimer = 0

local function updateGPSData()
    local pos = obj:getPosition()
    local dir = obj:getDirectionVector()
    local rotation = math_deg(math_atan2(dir.y, dir.x))
    local speed = electrics.values.airspeed * 3.6
    local zoom = math_min(250 + speed * 2.0, 400)
    
    gpsData.x = pos.x
    gpsData.y = pos.y
    gpsData.rotation = rotation
    gpsData.speed = speed
    gpsData.zoom = zoom
    gpsData.ignitionLevel = electrics.values.ignitionLevel or 0
    
    gpsLogTimer = gpsLogTimer + GPS_UPDATE_INTERVAL
    if gpsLogTimer >= 2.0 then
        local changed = math_abs(gpsData.x - lastLoggedGPS.x) > 0.1 or 
                       math_abs(gpsData.y - lastLoggedGPS.y) > 0.1 or
                       math_abs(gpsData.rotation - lastLoggedGPS.rotation) > 1
        
        if changed then
            lastLoggedGPS.x = gpsData.x
            lastLoggedGPS.y = gpsData.y
            lastLoggedGPS.rotation = gpsData.rotation
        end
        gpsLogTimer = 0
    end
    
    dirtyFlags.gpsData = true
end

local function isMapViewActive()
    return currentApp == "maps" or currentApp == "splitview"
end

local function init(jbeamData)
    local requiredTexture = "/vehicles/sdd_g82/textures/002b0000.dds"
    
    if not FS:fileExists(requiredTexture) then
        return
    end
    
    if jbeamData then
        screenMaterialName = jbeamData.screenMaterialName or "@sdd_g82_screen"
        htmlFilePath = jbeamData.htmlFilePath or "local://local/vehicles/sdd_g82/carplay/carplay.html"
        textureWidth = jbeamData.textureWidth or 1680
        textureHeight = jbeamData.textureHeight or 720
        textureFPS = jbeamData.textureFPS or 30
        name = jbeamData.name or "carplay"
    end
    
    if not screenMaterialName then
        return
    end
    
    if not htmlFilePath then
        return
    end
    
    nodeIDCache = {}
    frameMessageQueue = {}
    
    loadSettings()
    loadCallHistory()
    loadRecentApps()
    
    cleanupAllMessageAudio()
    cleanupAllPhoneAudio()
    
    if not isInitialized then
        htmlTexture.create(screenMaterialName, htmlFilePath, textureWidth, textureHeight, textureFPS, "automatic")
        electrics.values.carplayExitToHome = 0
        isInitialized = true
        
        obj:queueGameEngineLua(string_format("extensions.ui_uinavi.requestVehicleDashboardMap(%q, nil, %d)", screenMaterialName, obj:getID()))
    end
    
    currentApp = "home"
    selectedAppIndex = 0
    splitViewSelectedPanel = 0
    
    electrics.values.carplayActive = 0
    electrics.values.carplayApp = "home"
    electrics.values.carplaySelectedApp = 0
    
    electrics.values.carplayWallpaper = currentSettings.wallpaper or 1
    electrics.values.carplayIconTheme = currentSettings.iconTheme or "default"
    
    electrics.values.carplayAppLaunched = ""
    
    electrics.values.musicSystemActive = 0
    electrics.values.carplayPhoneAudio = ""
    electrics.values.carplayStopPhoneAudio = 0
    electrics.values.carplayCallHistory = ""
    electrics.values.carplayMessageAudio = ""
    electrics.values.carplayStopMessageAudio = 0
    
    electrics.values.phoneApp = 0
    lastPhoneApp = 0
end

local function handleMusicNavLeft()
    sendNavigationEvent('music', 'left')
end

local function handleMusicNavRight()
    sendNavigationEvent('music', 'right')
end

local function handleMusicNavUp()
    sendNavigationEvent('music', 'up')
end

local function handleMusicNavDown()
    sendNavigationEvent('music', 'down')
end

local function handleMusicNavSelect()
    sendNavigationEvent('music', 'select')
end

local function handleMusicNavBack()
    sendNavigationEvent('music', 'back')
end

local function handlePhoneNavigation(direction)
    local state = appNavigationStates.phone
    
    if direction == "left" then
        if state.isInTabBar then
            state.selectedTabIndex = math_max(0, state.selectedTabIndex - 1)
        else
            state.selectedItemIndex = math_max(0, state.selectedItemIndex - 1)
        end
    elseif direction == "right" then
        if state.isInTabBar then
            state.selectedTabIndex = math_min(2, state.selectedTabIndex + 1)
        else
            state.selectedItemIndex = state.selectedItemIndex + 1
        end
    elseif direction == "up" then
        if not state.isInTabBar then
            state.selectedItemIndex = math_max(0, state.selectedItemIndex - 1)
        end
    elseif direction == "down" then
        if not state.isInTabBar then
            state.selectedItemIndex = state.selectedItemIndex + 1
        end
    elseif direction == "select" then
    elseif direction == "back" then
        if not state.isInTabBar then
            state.isInTabBar = true
        end
    end
    
    sendNavigationEvent("phone", direction)
end

local function handleMessagesNavigation(direction)
    local state = appNavigationStates.messages
    
    if direction == "up" then
        state.selectedConversationIndex = math_max(0, state.selectedConversationIndex - 1)
    elseif direction == "down" then
        state.selectedConversationIndex = state.selectedConversationIndex + 1
    elseif direction == "select" then
        state.inConversationView = not state.inConversationView
    elseif direction == "back" then
        if state.inConversationView then
            state.inConversationView = false
        end
    end
    
    sendNavigationEvent("messages", direction)
end

local function handleNavLeft()
    if currentApp == "home" then
        local coords = indexTo2D(selectedAppIndex)
        if coords.col > 0 then
            selectedAppIndex = coordsTo1D(coords.row, coords.col - 1)
            electrics.values.carplaySelectedApp = selectedAppIndex
            dirtyFlags.navigation = true
        elseif coords.col == 0 then
            currentApp = "splitview"
            electrics.values.carplayApp = "splitview"
            splitViewSelectedPanel = 1
            dirtyFlags.navigation = true
        end
    elseif currentApp == "splitview" then
        if splitViewSelectedPanel == 0 then
            currentApp = "page3"
            electrics.values.carplayApp = "page3"
            dirtyFlags.navigation = true
        else
            splitViewSelectedPanel = 0
            sendSplitViewNavigationEvent("left")
            dirtyFlags.navigation = true
        end
    elseif currentApp == "page3" then
    elseif currentApp == "music" then
        handleMusicNavLeft()
    elseif currentApp == "phone" then
        handlePhoneNavigation("left")
    elseif currentApp == "messages" then
        handleMessagesNavigation("left")
    else
        sendNavigationEvent(currentApp, "left")
    end
end

local function handleNavRight()
    if currentApp == "home" then
        local coords = indexTo2D(selectedAppIndex)
        if coords.col < GRID_COLS - 1 then
            selectedAppIndex = coordsTo1D(coords.row, coords.col + 1)
            electrics.values.carplaySelectedApp = selectedAppIndex
            dirtyFlags.navigation = true
        end
    elseif currentApp == "page3" then
        currentApp = "splitview"
        splitViewSelectedPanel = 0
        electrics.values.carplayApp = "splitview"
        dirtyFlags.navigation = true
    elseif currentApp == "splitview" then
        if splitViewSelectedPanel == 1 then
            currentApp = "home"
            selectedAppIndex = 0
            electrics.values.carplayApp = "home"
            electrics.values.carplaySelectedApp = 0
            dirtyFlags.navigation = true
        else
            splitViewSelectedPanel = 1
            sendSplitViewNavigationEvent("right")
            dirtyFlags.navigation = true
        end
    elseif currentApp == "music" then
        handleMusicNavRight()
    elseif currentApp == "phone" then
        handlePhoneNavigation("right")
    elseif currentApp == "messages" then
        handleMessagesNavigation("right")
    else
        sendNavigationEvent(currentApp, "right")
    end
end

local function handleNavUp()
    if currentApp == "home" then
        local coords = indexTo2D(selectedAppIndex)
        if coords.row > 0 then
            selectedAppIndex = coordsTo1D(coords.row - 1, coords.col)
            electrics.values.carplaySelectedApp = selectedAppIndex
            dirtyFlags.navigation = true
        end
    elseif currentApp == "splitview" then
    elseif currentApp == "music" then
        handleMusicNavUp()
    elseif currentApp == "phone" then
        handlePhoneNavigation("up")
    elseif currentApp == "messages" then
        handleMessagesNavigation("up")
    else
        sendNavigationEvent(currentApp, "up")
    end
end

local function handleNavDown()
    if currentApp == "home" then
        local coords = indexTo2D(selectedAppIndex)
        if coords.row < GRID_ROWS - 1 then
            selectedAppIndex = coordsTo1D(coords.row + 1, coords.col)
            electrics.values.carplaySelectedApp = selectedAppIndex
            dirtyFlags.navigation = true
        end
    elseif currentApp == "splitview" then
    elseif currentApp == "music" then
        handleMusicNavDown()
    elseif currentApp == "phone" then
        handlePhoneNavigation("down")
    elseif currentApp == "messages" then
        handleMessagesNavigation("down")
    else
        sendNavigationEvent(currentApp, "down")
    end
end

local function handleNavSelect()
    if currentApp == "home" then
        local selectedApp = homeApps[selectedAppIndex + 1]
        if selectedApp then
            currentApp = selectedApp
            electrics.values.carplayApp = currentApp
            
            addToRecentApps(selectedApp)
            
            if selectedApp == "music" then
                electrics.values.musicSystemActive = 1
            elseif selectedApp == "settings" then
                electrics.values.settingsActive = 1
            end
            
            dirtyFlags.navigation = true
        end
    elseif currentApp == "splitview" then
        if splitViewSelectedPanel == 0 then
            currentApp = "maps"
            electrics.values.carplayApp = "maps"
            addToRecentApps("maps")
        else
            currentApp = "music"
            electrics.values.carplayApp = "music"
            electrics.values.musicSystemActive = 1
            addToRecentApps("music")
        end
        dirtyFlags.navigation = true
    elseif currentApp == "music" then
        handleMusicNavSelect()
    elseif currentApp == "phone" then
        handlePhoneNavigation("select")
    elseif currentApp == "messages" then
        handleMessagesNavigation("select")
    else
        sendNavigationEvent(currentApp, "select")
    end
end

local function handleNavBack()
    if currentApp == "home" then
    elseif currentApp == "page3" then
        currentApp = "splitview"
        splitViewSelectedPanel = 0
        electrics.values.carplayApp = "splitview"
        dirtyFlags.navigation = true
    elseif currentApp == "splitview" then
        currentApp = "home"
        selectedAppIndex = 0
        electrics.values.carplayApp = "home"
        electrics.values.carplaySelectedApp = 0
        dirtyFlags.navigation = true
    elseif currentApp == "music" then
        sendNavigationEvent('music', 'back')
    elseif currentApp == "settings" then
        sendNavigationEvent('settings', 'back')
    else
        handleExitToHome()
        electrics.values.settingsActive = 0
    end
end

local function handleNavHome()
    if currentApp == "splitview" or currentApp == "page3" then
        currentApp = "home"
        selectedAppIndex = 0
        electrics.values.carplayApp = "home"
        electrics.values.carplaySelectedApp = 0
        dirtyFlags.navigation = true
    else
        handleExitToHome()
    end
end

local function handleNavigation(dt)
    local navLeft = electrics.values.menuNavLeft or 0
    local navRight = electrics.values.menuNavRight or 0
    local navUp = electrics.values.menuNavUp or 0
    local navDown = electrics.values.menuNavDown or 0
    local navSelect = electrics.values.menuSelect or 0
    local navBack = electrics.values.menuBack or 0
    local navHome = electrics.values.menuHome or 0
    
    if navLeft == 1 and lastNavLeft == 0 then
        handleNavLeft()
    elseif navRight == 1 and lastNavRight == 0 then
        handleNavRight()
    elseif navUp == 1 and lastNavUp == 0 then
        handleNavUp()
    elseif navDown == 1 and lastNavDown == 0 then
        handleNavDown()
    elseif navSelect == 1 and lastNavSelect == 0 then
        handleNavSelect()
    elseif navBack == 1 and lastNavBack == 0 then
        handleNavBack()
    elseif navHome == 1 and lastNavHome == 0 then
        handleNavHome()
    end
    
    lastNavLeft = navLeft
    lastNavRight = navRight
    lastNavUp = navUp
    lastNavDown = navDown
    lastNavSelect = navSelect
    lastNavBack = navBack
    lastNavHome = navHome
end

local cachedMusicData = nil
local lastMusicUpdateTime = 0
local MUSIC_UPDATE_INTERVAL = 0.15  -- Increased from 0.1

local function getMusicData()
    local now = os_clock()
    if cachedMusicData and (now - lastMusicUpdateTime) < MUSIC_UPDATE_INTERVAL then
        return cachedMusicData
    end
    
    local repeatModes = {"off", "all", "track"}
    local repeatIndex = (electrics.values.musicRepeat or 0) + 1
    local repeatMode = repeatModes[repeatIndex] or "off"
    
    cachedMusicData = {
        isPlaying = (electrics.values.musicIsPlaying or 0) == 1,
        currentSong = electrics.values.musicCurrentSong or "No Music Playing",
        artist = electrics.values.musicArtist or "",
        albumArt = electrics.values.musicAlbumArt,
        currentTime = electrics.values.musicCurrentTime or "0:00",
        totalTime = electrics.values.musicTotalTime or "0:00",
        currentSongId = electrics.values.musicCurrentSongId or "",
        currentSongLiked = (electrics.values.musicCurrentSongLiked or 0) == 1,
        shuffle = (electrics.values.musicShuffle or 0) == 1,
        repeatMode = repeatMode,
        volume = electrics.values.musicVolume or 75,
        playlists = electrics.values.musicPlaylistsData or "[]",
        likedSongs = electrics.values.musicLikedSongs or "[]",
        hasSongs = (electrics.values.musicHasSongs or 0) == 1,
        currentPlaylist = electrics.values.musicCurrentPlaylist or "likedsongs",
        currentTrackIndex = electrics.values.musicCurrentTrackIndex or 1,
        currentViewSongs = electrics.values.musicCurrentViewSongs or "[]"
    }
    
    lastMusicUpdateTime = now
    return cachedMusicData
end

local function updateGFX(dt)
    updateTimer = updateTimer + dt
    frameMessageTimer = frameMessageTimer + dt
    gpsUpdateTimer = gpsUpdateTimer + dt
    
    handleNavigation(dt)
    
    handleSteeringWheelInputs()
    
    local exitToHome = electrics.values.carplayExitToHome or 0
    if exitToHome == 1 then
        handleHTMLExitMessage()
        electrics.values.carplayExitToHome = 0
    end
    
    local messageAudioFile = electrics.values.carplayMessageAudio or ""
    if messageAudioFile ~= "" then
        playMessageAudio(messageAudioFile)
        electrics.values.carplayMessageAudio = ""
    end
    
    local stopMessageAudioSignal = electrics.values.carplayStopMessageAudio or 0
    if stopMessageAudioSignal == 1 then
        stopMessageAudio()
        electrics.values.carplayStopMessageAudio = 0
    end
    
    parseCallHistoryFromElectrics()
    
    local phoneAudioFile = electrics.values.carplayPhoneAudio or ""
    if phoneAudioFile ~= "" then
        playPhoneAudio(phoneAudioFile)
        electrics.values.carplayPhoneAudio = ""
    end
    
    local stopPhoneAudioSignal = electrics.values.carplayStopPhoneAudio or 0
    if stopPhoneAudioSignal == 1 then
        stopPhoneAudio()
        electrics.values.carplayStopPhoneAudio = 0
    end
    
    if frameMessageTimer > FRAME_MESSAGE_INTERVAL then
        processFrameMessageQueue()
        frameMessageTimer = 0
    end
    
    if gpsUpdateTimer > GPS_UPDATE_INTERVAL then
        gpsUpdateTimer = 0
        
        local ignitionLevel = electrics.values.ignitionLevel or 0
        
        if ignitionLevel > 0 and playerInfo.anyPlayerSeated then
            updateGPSData()
        end
    end
    
    if updateTimer > invFPS then
        updateTimer = 0
        
        local ignitionLevel = electrics.values.ignitionLevel or 0
        
        if ignitionLevel > 0 then
            if not isCarPlayActive then
                isCarPlayActive = true
                electrics.values.carplayActive = 1
                dirtyFlags.vehicleData = true
            end
        else
            if isCarPlayActive then
                isCarPlayActive = false
                electrics.values.carplayActive = 0
                
                if currentMessageAudio then
                    stopMessageAudio()
                end
                if currentPhoneAudio then
                    stopPhoneAudio()
                end
                dirtyFlags.vehicleData = true
            end
        end
        
        handleSettingsChange()
        
        local appLaunched = electrics.values.carplayAppLaunched
        if appLaunched and appLaunched ~= "" then
            addToRecentApps(appLaunched)
            electrics.values.carplayAppLaunched = ""
        end
        
        if isCarPlayActive and screenMaterialName then
            local now = os_clock()
            
            if (now - lastHtmlUpdateTime) > HTML_UPDATE_INTERVAL then
                local musicData = getMusicData()
                
                local dataHash = tostring(ignitionLevel) .. currentApp .. tostring(selectedAppIndex) .. tostring(splitViewSelectedPanel)
                local musicHash = tostring(musicData.isPlaying) .. (musicData.currentSong or "") .. (musicData.currentTime or "0:00")
                
                local forceUpdate = isMapViewActive()
                
                if forceUpdate or dataHash ~= lastDataHash or musicHash ~= lastMusicDataHash or 
                   dirtyFlags.navigation or dirtyFlags.settings or dirtyFlags.vehicleData or dirtyFlags.gpsData then
                    
                    local vehicleData = {
                        speed = electrics.values.wheelspeed or 0,
                        rpm = electrics.values.rpm or 0,
                        gear = electrics.values.gear or 0,
                        fuel = electrics.values.fuel or 0,
                        engineRunning = (electrics.values.engineRunning or 0) == 1
                    }
                    
                    local carplayData = {
                        active = isCarPlayActive,
                        currentApp = currentApp,
                        selectedAppIndex = selectedAppIndex,
                        splitViewSelectedPanel = splitViewSelectedPanel,
                        homeApps = homeApps,
                        recentApps = recentApps,
                        settings = currentSettings,
                        settingsNavigation = settingsNavigation,
                        appNavigationStates = appNavigationStates,
                        music = musicData,
                        phone = {
                            callHistory = callHistory
                        },
                        vehicle = vehicleData,
                        gps = gpsData,
                        time = os.date("%H:%M"),
                        date = os.date("%Y-%m-%d"),
                        ignitionLevel = ignitionLevel
                    }
                    
                    htmlTexture.call(screenMaterialName, "updateCarPlayData", carplayData)
                    
                    lastDataHash = dataHash
                    lastMusicDataHash = musicHash
                    lastHtmlUpdateTime = now
                    
                    dirtyFlags.navigation = false
                    dirtyFlags.settings = false
                    dirtyFlags.vehicleData = false
                    dirtyFlags.musicData = false
                    dirtyFlags.gpsData = false
                end
            end
        end
    end
end

local function onReset()
    lastNavLeft = 0
    lastNavRight = 0
    lastNavUp = 0
    lastNavDown = 0
    lastNavSelect = 0
    lastNavBack = 0
    lastNavHome = 0
    
    lastPhoneApp = 0
    
    updateTimer = 0
    frameMessageTimer = 0
    gpsUpdateTimer = 0
    
    splitViewSelectedPanel = 0
    
    nodeIDCache = {}
    frameMessageQueue = {}
    cachedMusicData = nil
    lastMusicUpdateTime = 0
    
    electrics.values.carplayMessageAudio = ""
    electrics.values.carplayStopMessageAudio = 0
    electrics.values.carplayPhoneAudio = ""
    electrics.values.carplayStopPhoneAudio = 0
    electrics.values.carplayExitToHome = 0
    
    electrics.values.phoneApp = 0
end

local function onDestroy()
    if screenMaterialName then
        htmlTexture.destroy(screenMaterialName)
    end
    
    cleanupAllMessageAudio()
    cleanupAllPhoneAudio()
    
    isInitialized = false
    currentApp = "home"
    selectedAppIndex = 0
    splitViewSelectedPanel = 0
    
    nodeIDCache = {}
    frameMessageQueue = {}
    cachedMusicData = nil
end

M.init = init
M.updateGFX = updateGFX
M.onReset = onReset
M.onDestroy = onDestroy

return M