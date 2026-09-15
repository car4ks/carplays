local M = {}
M.type = "auxiliary"

local playlistConfig = require("vehicles/common/lua/sdd_carplay_playlist_config")
local obj = obj
local electrics = electrics
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local table_insert = table.insert
local table_remove = table.remove
local table_concat = table.concat
local string_format = string.format
local string_gsub = string.gsub
local os_clock = os.clock
local os_time = os.time

local audioNodes = {
    { name = "dsh1", id = "front", volume = 1.0, type = "front_center" },
    { name = "d14r", id = "right", volume = 1.0, type = "side_right" },
    { name = "d14l", id = "left", volume = 1.0, type = "side_left" },
    { name = "f9r",  id = "rear_right", volume = 1.0, type = "rear_right" },
    { name = "f9l",  id = "rear_left", volume = 1.0, type = "rear_left" }
}

local subwooferConfig = {
    nodeNames = {"subwfr_cne_L_0", "subwfr_cne_R_0"},
    id = "subwoofer",
    volume = 20.0,
    type = "subwoofer"
}

local volumeControl = {
    masterVolume = 0.75,
    minVolume = 0.0,
    maxVolume = 1.0,
    volumeStep = 0.005
}

local equalizerControl = {
    fade = 50,
    balance = 50,
    bass = 50,
    lastFade = 50,
    lastBalance = 50,
    lastBass = 50
}

local lastBassGainMultiplier = 1.0

local subwooferSync = {
    syncTime = 0,
    musicStartTime = 0,
    active = false,
    dataTable = nil,
    dataIndex = 1,
    hasSupport = false,
    currentBassPath = "",
    currentDataPath = ""
}

local subwooferAudio = {
    sfx = nil,
    nodeId = 0,
    active = false,
    isPlaying = false
}

local likedSongsFilePath = "/settings/liked_songs.json"
local likedSongs = {}

local lastSongFilePath = "/settings/last_song_state.json"
local lastSongState = {
    playlistId = "likedsongs",
    trackIndex = 1,
    songId = nil,
    hasBeenSet = false
}

local musicPreferencesFilePath = "/settings/music_preferences.json"
local musicPreferences = {
    shuffle = false,
    repeatMode = "off",
    volume = 75,
    lastUpdated = 0
}

local playlistCache = {}
local cacheTimeout = 300
local cacheTimestamps = {}

local repeatMode = "off"
local shuffleEnabled = false
local repeatModeIndex = 0
local isRestoringState = false

local sfx_sources = {}
local current_playing_sources = nil
local currentSongPath = ""
local songElapsedTime = 0
local actualSongDuration = 0

local pendingPlayback = nil
local syncFrameCounter = 0
local primingDelay = 1

local availablePlaylists = {}
local currentQueue = {}
local currentQueueIndex = 0
local currentQueuePlaylistName = ""
local isQueueInitialized = false
local originalQueue = {}

local isInitialized = false
local updateTimer = 0
local invFPS = 1/15
local isPlaying = false
local currentTime = 0
local isFavorited = false
local currentSongAlbumArt = ""
local isPausedByUser = false
local currentSongData = nil
local musicSystemActive = false

local dirtyFlags = {
    playlists = false,
    likedSongs = false,
    currentSong = false,
    playbackState = false,
    volume = false,
    equalizer = false
}

local cachedJSONData = {
    playlists = "[]",
    likedSongs = "[]",
    currentViewSongs = "[]"
}

local lastUpdateTime = 0
local MIN_UPDATE_INTERVAL = 0.15

local lastCarplayVolume = -1

local nodeIDCache = {}
local subwooferNodeID = nil

local jsonBuffer = {}

local function resolveNodeID(nodeName)
    if nodeIDCache[nodeName] then
        return nodeIDCache[nodeName]
    end
    
    if not v or not v.data or not v.data.nodes then return 0 end
    for _, node in pairs(v.data.nodes) do
        if node.name == nodeName then
            nodeIDCache[nodeName] = node.cid
            return node.cid
        end
    end
    return 0
end

local function getSubwooferNode()
    if subwooferNodeID then return subwooferNodeID end
    
    if not v or not v.data or not v.data.nodes then return 0 end
    for _, nodeName in ipairs(subwooferConfig.nodeNames) do
        for _, node in pairs(v.data.nodes) do
            if node.name == nodeName then
                subwooferNodeID = node.cid
                return node.cid
            end
        end
    end
    return 0
end

local jsonEncodeCache = {}
local jsonEncodeCacheTime = {}
local JSON_CACHE_TIMEOUT = 2.0

local function escapeString(str)
    if type(str) == "string" then
        return string_gsub(string_gsub(string_gsub(tostring(str), '"', '\\"'), '\n', '\\n'), '\r', '\\r')
    end
    return tostring(str)
end

local function jsonEncode(data, cacheKey)
    if cacheKey then
        local now = os_clock()
        if jsonEncodeCache[cacheKey] and jsonEncodeCacheTime[cacheKey] and 
           (now - jsonEncodeCacheTime[cacheKey]) < JSON_CACHE_TIMEOUT then
            return jsonEncodeCache[cacheKey]
        end
    end
    
    if not data then return "[]" end
    if type(data) == "table" then
        if #data == 0 and next(data) == nil then return "[]" end
        
        for i = 1, #jsonBuffer do jsonBuffer[i] = nil end
        
        for i, item in ipairs(data) do
            if type(item) == "table" then
                local songName = item.name or item.title or "Unknown Song"
                local artistName = item.artist or item.artistName or ""
                local songId = item.id or item.songId or tostring(i)
                local duration = item.duration or item.length or 0
                local albumArt = item.albumArt or item.album_art or item.cover or item.art or ""
                
                jsonBuffer[i] = string_format('{"title":"%s","artist":"%s","id":"%s","art":"%s","albumArt":"%s","duration":%d}',
                    escapeString(songName), escapeString(artistName), escapeString(songId), 
                    escapeString(albumArt), escapeString(albumArt), 
                    type(duration) == "number" and duration or 0)
            end
        end
        local result = "[" .. table_concat(jsonBuffer, ",") .. "]"
        
        if cacheKey then
            jsonEncodeCache[cacheKey] = result
            jsonEncodeCacheTime[cacheKey] = os_clock()
        end
        
        return result
    end
    return "[]"
end

local function jsonEncodePlaylist(playlist)
    if not playlist or type(playlist) ~= "table" then return "{}" end
    return string_format('{"name":"%s","id":"%s","songCount":%d,"coverImage":"%s"}',
        escapeString(playlist.name or "Unknown Playlist"), escapeString(playlist.id or ""), 
        playlist.songCount or 0, escapeString(playlist.coverImage or ""))
end

local function jsonEncodePlaylists(playlists)
    if not playlists or type(playlists) ~= "table" or #playlists == 0 then return "[]" end
    
    for i = 1, #jsonBuffer do jsonBuffer[i] = nil end
    for i, playlist in ipairs(playlists) do
        jsonBuffer[i] = jsonEncodePlaylist(playlist)
    end
    return "[" .. table_concat(jsonBuffer, ",") .. "]"
end

local function loadLikedSongs()
    local success, data = pcall(function() return jsonReadFile(likedSongsFilePath) end)
    if success and data and type(data) == "table" then
        likedSongs = data.likedSongs or {}
    else
        likedSongs = {}
    end
end

local function saveLikedSongs()
    local dataToSave = { likedSongs = likedSongs, lastUpdated = os_time() }
    jsonWriteFile(likedSongsFilePath, dataToSave)
    dirtyFlags.likedSongs = true
end

local function isSongLiked(songId)
    if not songId or not likedSongs then return false end
    for _, likedId in ipairs(likedSongs) do
        if likedId == songId then return true end
    end
    return false
end

local function addSongToLiked(songId)
    if not songId or isSongLiked(songId) then return false end
    table_insert(likedSongs, songId)
    saveLikedSongs()
    if currentQueuePlaylistName == "likedsongs" or currentQueuePlaylistName == "Liked Songs" then
        playlistCache["likedsongs"] = nil
        cacheTimestamps["likedsongs"] = nil
    end
    return true
end

local function removeSongFromLiked(songId)
    if not songId then return false end
    for i, likedId in ipairs(likedSongs) do
        if likedId == songId then
            table_remove(likedSongs, i)
            saveLikedSongs()
            if currentQueuePlaylistName == "likedsongs" or currentQueuePlaylistName == "Liked Songs" then
                playlistCache["likedsongs"] = nil
                cacheTimestamps["likedsongs"] = nil
            end
            return true
        end
    end
    return false
end

local function saveLastSongState()
    if isRestoringState then return end
    local stateToSave = {
        playlistId = currentQueuePlaylistName or "likedsongs",
        trackIndex = currentQueueIndex or 1,
        songId = currentSongData and currentSongData.id or nil,
        hasBeenSet = true,
        lastUpdated = os_time()
    }
    jsonWriteFile(lastSongFilePath, stateToSave)
end

local function loadLastSongState()
    local success, data = pcall(function() return jsonReadFile(lastSongFilePath) end)
    if success and data and type(data) == "table" and data.hasBeenSet then
        lastSongState.playlistId = data.playlistId or "likedsongs"
        lastSongState.trackIndex = data.trackIndex or 1
        lastSongState.songId = data.songId
        lastSongState.hasBeenSet = true
        return true
    end
    return false
end

local function saveMusicPreferences()
    local prefsToSave = {
        shuffle = shuffleEnabled,
        repeatMode = repeatMode,
        volume = math_floor(volumeControl.masterVolume * 100),
        lastUpdated = os_time()
    }
    jsonWriteFile(musicPreferencesFilePath, prefsToSave)
end

local function loadMusicPreferences()
    local success, data = pcall(function() return jsonReadFile(musicPreferencesFilePath) end)
    if success and data and type(data) == "table" then
        shuffleEnabled = data.shuffle or false
        repeatMode = data.repeatMode or "off"
        volumeControl.masterVolume = (data.volume or 75) / 100
        if repeatMode == "off" then repeatModeIndex = 0
        elseif repeatMode == "all" then repeatModeIndex = 1
        elseif repeatMode == "track" then repeatModeIndex = 2 end
        return true
    end
    return false
end

local function sanitizeObjectName(path)
    return string_gsub(string_gsub(path, "/", "_"), "%.", "_")
end

local function loadSubwooferData(dataPath)
    if not dataPath or dataPath == "" then return nil end
    local success, data = pcall(function() return jsonReadFile(dataPath) end)
    if success and data and type(data) == "table" then
        if data.values and type(data.values) == "table" then
            local interval = data.interval or 0.05
            if interval > 1.0 then interval = interval / 1000.0 end
            if interval > 0.5 then interval = 0.05 end
            return { data = data.values, interval = interval, dataCount = #data.values }
        elseif data.data and type(data.data) == "table" then
            local interval = data.interval or 0.05
            if interval > 1.0 then interval = interval / 1000.0 end
            if interval > 0.5 then interval = 0.05 end
            return { data = data.data, interval = interval, dataCount = #data.data }
        elseif #data > 0 then
            return { data = data, interval = 0.05, dataCount = #data }
        end
    end
    return nil
end

local function subwooferSyncStart()
    subwooferSync.musicStartTime = os_clock()
    subwooferSync.syncTime = 0
    subwooferSync.active = true
    electrics.values.musicIsPlaying = 1
end

local function subwooferSyncStop()
    subwooferSync.active = false
    subwooferSync.syncTime = 0
    subwooferSync.musicStartTime = 0
    electrics.values.musicIsPlaying = 0
    electrics.values.rlaSubwooferDriver = 0
end

local function subwooferSyncPause()
    subwooferSync.active = false
    electrics.values.musicIsPlaying = 0
end

local function subwooferSyncResume()
    subwooferSync.active = true
    subwooferSync.musicStartTime = os_clock() - subwooferSync.syncTime
    electrics.values.musicIsPlaying = 1
end

local function subwooferSyncReset()
    subwooferSync.musicStartTime = 0
    subwooferSync.syncTime = 0
    subwooferSync.active = false
    subwooferSync.dataTable = nil
    subwooferSync.dataIndex = 1
    electrics.values.musicIsPlaying = 0
    electrics.values.rlaSubwooferDriver = 0
end

local function updateSubwooferSync(dt)
    if not electrics.values.rlaSubwooferDriver then
        electrics.values.rlaSubwooferDriver = 0
    end
    if subwooferSync.active then
        local currentClock = os_clock()
        subwooferSync.syncTime = currentClock - subwooferSync.musicStartTime
        if subwooferSync.hasSupport and subwooferSync.dataTable and subwooferSync.dataTable.data then
            local dataInterval = subwooferSync.dataTable.interval
            local targetIndex = math_floor(subwooferSync.syncTime / dataInterval) + 1
            if targetIndex > subwooferSync.dataTable.dataCount then targetIndex = subwooferSync.dataTable.dataCount
            elseif targetIndex < 1 then targetIndex = 1 end
            local dataValue = 0
            if targetIndex <= subwooferSync.dataTable.dataCount then
                dataValue = tonumber(subwooferSync.dataTable.data[targetIndex]) or 0
                dataValue = math_max(0, math_min(1, dataValue))
            end
            local bassGainMultiplier = electrics.values.bassGainMultiplier or 1.0
            local volumeMultiplier = volumeControl.masterVolume or 1.0
            electrics.values.rlaSubwooferDriver = dataValue * bassGainMultiplier * volumeMultiplier
            subwooferSync.dataIndex = targetIndex
        else
            electrics.values.rlaSubwooferDriver = 0
        end
    else
        electrics.values.rlaSubwooferDriver = 0
    end
end

local function calculateSpeakerVolume(nodeType, baseVolume, fade, balance)
    local fadeValue = fade * 0.01
    local balanceValue = balance * 0.01
    local frontMultiplier, rearMultiplier
    
    if fadeValue <= 0.5 then
        rearMultiplier = 1.0
        frontMultiplier = fadeValue * 2.0
    else
        frontMultiplier = 1.0
        rearMultiplier = (1.0 - fadeValue) * 2.0
    end
    
    local leftMultiplier = math_min(1.0, math_max(0.0, (1.0 - balanceValue) * 2.0))
    local rightMultiplier = math_min(1.0, math_max(0.0, balanceValue * 2.0))
    local centerBalanceMultiplier = 1.0 - (math_abs(balanceValue - 0.5) * 2.0)
    
    local multiplier = 1.0
    if nodeType == "front_center" then
        multiplier = frontMultiplier * centerBalanceMultiplier
    elseif nodeType == "side_left" then
        multiplier = leftMultiplier * (frontMultiplier + rearMultiplier) * 0.5
    elseif nodeType == "side_right" then
        multiplier = rightMultiplier * (frontMultiplier + rearMultiplier) * 0.5
    elseif nodeType == "rear_left" then
        local rearBalanceMultiplier = leftMultiplier
        if balanceValue < 0.5 and leftMultiplier > 0 then
            rearBalanceMultiplier = leftMultiplier * 0.5 + 0.5
        end
        multiplier = rearBalanceMultiplier * rearMultiplier
    elseif nodeType == "rear_right" then
        local rearBalanceMultiplier = rightMultiplier
        if balanceValue > 0.5 and rightMultiplier > 0 then
            rearBalanceMultiplier = rightMultiplier * 0.5 + 0.5
        end
        multiplier = rearBalanceMultiplier * rearMultiplier
    elseif nodeType == "subwoofer" then
        multiplier = 1.0 + ((electrics.values.equalizerBass or 50) - 50) * 0.01
    end
    
    return baseVolume * multiplier
end

local function updateBassGainControl()
    if not subwooferAudio.sfx or not subwooferAudio.active then return end
    local bassGainMultiplier = electrics.values.bassGainMultiplier or 1.0
    if math_abs(bassGainMultiplier - lastBassGainMultiplier) > 0.005 then
        local fade = electrics.values.equalizerFade or equalizerControl.fade
        local balance = electrics.values.equalizerBalance or equalizerControl.balance
        local eqBaseVolume = calculateSpeakerVolume(subwooferConfig.type, subwooferConfig.volume, fade, balance)
        local finalVolume = eqBaseVolume * volumeControl.masterVolume * bassGainMultiplier
        obj:setVolumePitch(subwooferAudio.sfx, finalVolume, 1.0)
        lastBassGainMultiplier = bassGainMultiplier
    end
end

local function updateEqualizerVolumes()
    if not current_playing_sources then return end
    local fade = electrics.values.equalizerFade or equalizerControl.fade
    local balance = electrics.values.equalizerBalance or equalizerControl.balance
    local bass = electrics.values.equalizerBass or equalizerControl.bass
    
    equalizerControl.fade = fade
    equalizerControl.balance = balance
    equalizerControl.bass = bass
    
    if fade == equalizerControl.lastFade and balance == equalizerControl.lastBalance and bass == equalizerControl.lastBass then return end
    
    local bassMultiplier = 1.0 + (bass - 50) * 0.01
    
    for _, nodeConfig in ipairs(audioNodes) do
        local sourceData = current_playing_sources[nodeConfig.id]
        if sourceData then
            local eqBaseVolume = calculateSpeakerVolume(nodeConfig.type, nodeConfig.volume, fade, balance) * bassMultiplier
            sourceData.eqBaseVolume = eqBaseVolume
            obj:setVolumePitch(sourceData.sfx, eqBaseVolume * volumeControl.masterVolume, 1.0)
        end
    end
    
    if subwooferAudio.sfx and subwooferAudio.active then
        local bassGainMultiplier = electrics.values.bassGainMultiplier or 1.0
        local eqBaseVolume = calculateSpeakerVolume(subwooferConfig.type, subwooferConfig.volume, fade, balance)
        local finalVolume = eqBaseVolume * volumeControl.masterVolume * bassGainMultiplier
        obj:setVolumePitch(subwooferAudio.sfx, finalVolume, 1.0)
    end
    
    equalizerControl.lastFade = fade
    equalizerControl.lastBalance = balance
    equalizerControl.lastBass = bass
    dirtyFlags.equalizer = false
end

local function stopSubwooferAudio()
    if subwooferAudio.sfx then
        obj:cutSFX(subwooferAudio.sfx)
        obj:deleteSFXSource(subwooferAudio.sfx)
        subwooferAudio.sfx = nil
    end
    subwooferAudio.active = false
    subwooferAudio.isPlaying = false
end

local function startSubwooferAudio(bassPath)
    if not bassPath or bassPath == "" then return false end
    if not electrics.values.bassGainMultiplier then return false end
    stopSubwooferAudio()
    local nodeID = getSubwooferNode()
    if nodeID <= 0 then
        nodeID = resolveNodeID("dsh1")
        if nodeID <= 0 then return false end
    end
    local safeName = sanitizeObjectName(bassPath) .. "_sub"
    subwooferAudio.sfx = obj:createSFXSource(bassPath, "AudioDefaultLoop3D", safeName, nodeID)
    if subwooferAudio.sfx then
        local bassGainMultiplier = electrics.values.bassGainMultiplier or 1.0
        local fade = electrics.values.equalizerFade or equalizerControl.fade
        local balance = electrics.values.equalizerBalance or equalizerControl.balance
        local eqBaseVolume = calculateSpeakerVolume(subwooferConfig.type, subwooferConfig.volume, fade, balance)
        local finalVolume = eqBaseVolume * volumeControl.masterVolume * bassGainMultiplier
        obj:setVolumePitch(subwooferAudio.sfx, finalVolume, 1.0)
        subwooferAudio.nodeId = nodeID
        subwooferAudio.active = true
        subwooferAudio.isPlaying = false
        lastBassGainMultiplier = bassGainMultiplier
        return true
    end
    return false
end

local function playSubwooferAudio()
    if subwooferAudio.sfx and subwooferAudio.active then
        local bassGainPercent = electrics.values.bassGain or 0.5
        if bassGainPercent > 0.01 then
            obj:playSFX(subwooferAudio.sfx)
            subwooferAudio.isPlaying = true
            return true
        else
            subwooferAudio.isPlaying = false
        end
    end
    return false
end

local function pauseSubwooferAudio()
    if subwooferAudio.sfx and subwooferAudio.active then
        obj:cutSFX(subwooferAudio.sfx)
        subwooferAudio.isPlaying = false
        return true
    end
    return false
end

local function cleanupUnusedSources()
    for songPath, sources in pairs(sfx_sources) do
        if sources ~= current_playing_sources then
            for location, sourceData in pairs(sources) do
                obj:cutSFX(sourceData.sfx)
                obj:deleteSFXSource(sourceData.sfx)
            end
            sfx_sources[songPath] = nil
        end
    end
end

local function prepareSongMultiSource(songPath, bassPath, shouldPrime)
    if not songPath or songPath == "" then return nil end
    cleanupUnusedSources()
    local newSources = {}
    local successCount = 0
    local fade = electrics.values.equalizerFade or equalizerControl.fade
    local balance = electrics.values.equalizerBalance or equalizerControl.balance
    local bass = electrics.values.equalizerBass or equalizerControl.bass
    local bassMultiplier = 1.0 + (bass - 50) * 0.01
    
    for _, nodeConfig in ipairs(audioNodes) do
        local nodeId = resolveNodeID(nodeConfig.name)
        local safeName = string_gsub(string_gsub(songPath, "/", "_"), "%.", "_") .. "_" .. nodeConfig.id .. "_" .. nodeId
        local sfx = obj:createSFXSource(songPath, "AudioDefaultLoop3D", safeName, nodeId)
        if sfx then
            local eqBaseVolume = calculateSpeakerVolume(nodeConfig.type, nodeConfig.volume, fade, balance) * bassMultiplier
            local effectiveVolume = eqBaseVolume * volumeControl.masterVolume
            obj:setVolumePitch(sfx, effectiveVolume, 1.0)
            newSources[nodeConfig.id] = {
                sfx = sfx,
                baseVolume = nodeConfig.volume,
                eqBaseVolume = eqBaseVolume,
                nodeType = nodeConfig.type,
                nodeId = nodeId,
                nodeName = nodeConfig.name
            }
            successCount = successCount + 1
        end
    end
    
    if bassPath and bassPath ~= "" then
        startSubwooferAudio(bassPath)
    else
        stopSubwooferAudio()
    end
    
    if successCount > 0 then
        if shouldPrime then
            local playSFX = obj.playSFX
            local cutSFX = obj.cutSFX
            for location, sourceData in pairs(newSources) do
                playSFX(obj, sourceData.sfx)
            end
            if subwooferAudio.sfx and subwooferAudio.active then
                local bassGainPercent = electrics.values.bassGain or 0.5
                if bassGainPercent > 0.01 then
                    playSFX(obj, subwooferAudio.sfx)
                end
            end
            for location, sourceData in pairs(newSources) do
                cutSFX(obj, sourceData.sfx)
            end
            if subwooferAudio.sfx and subwooferAudio.active then
                cutSFX(obj, subwooferAudio.sfx)
            end
        end
        return newSources
    else
        for location, sourceData in pairs(newSources) do
            obj:deleteSFXSource(sourceData.sfx)
        end
        stopSubwooferAudio()
        return nil
    end
end

local function executeSyncPlayback()
    if not pendingPlayback then return end
    local action = pendingPlayback.action
    local sources = pendingPlayback.sources
    local songPath = pendingPlayback.songPath
    if action == "play" then
        local playSFX = obj.playSFX
        for location, sourceData in pairs(sources) do
            playSFX(obj, sourceData.sfx)
        end
        playSubwooferAudio()
        current_playing_sources = sources
        currentSongPath = songPath
        songElapsedTime = 0
        currentTime = 0
        isPlaying = true
        isPausedByUser = false
        subwooferSyncStart()
        dirtyFlags.playbackState = true
        dirtyFlags.currentSong = true
    elseif action == "resume" then
        local playSFX = obj.playSFX
        for location, sourceData in pairs(sources) do
            playSFX(obj, sourceData.sfx)
        end
        playSubwooferAudio()
        isPlaying = true
        isPausedByUser = false
        subwooferSyncResume()
        dirtyFlags.playbackState = true
    end
    pendingPlayback = nil
    syncFrameCounter = 0
end

local function playSongMultiSource(songPath, bassPath, dataPath)
    if not songPath or songPath == "" then return false end
    if current_playing_sources then
        local cutSFX = obj.cutSFX
        for location, sourceData in pairs(current_playing_sources) do
            cutSFX(obj, sourceData.sfx)
        end
        pauseSubwooferAudio()
        if currentSongPath ~= songPath and sfx_sources[currentSongPath] then
            for location, sourceData in pairs(sfx_sources[currentSongPath]) do
                obj:deleteSFXSource(sourceData.sfx)
            end
            sfx_sources[currentSongPath] = nil
        end
        current_playing_sources = nil
    end
    subwooferSyncStop()
    subwooferSync.dataTable = nil
    subwooferSync.dataIndex = 1
    if bassPath and bassPath ~= "" then
        subwooferSync.currentBassPath = bassPath
        subwooferSync.currentDataPath = dataPath or ""
        subwooferSync.hasSupport = true
        if dataPath and dataPath ~= "" then
            subwooferSync.dataTable = loadSubwooferData(dataPath)
        end
    else
        subwooferSync.currentBassPath = ""
        subwooferSync.currentDataPath = ""
        subwooferSync.hasSupport = false
    end
    local sources = sfx_sources[songPath]
    if not sources then
        sources = prepareSongMultiSource(songPath, bassPath, true)
        if not sources then return false end
        sfx_sources[songPath] = sources
    end
    pendingPlayback = {
        action = "play",
        songPath = songPath,
        sources = sources
    }
    syncFrameCounter = primingDelay
    return true
end

local function stopCurrentSongMultiSource()
    if current_playing_sources then
        local cutSFX = obj.cutSFX
        for location, sourceData in pairs(current_playing_sources) do
            cutSFX(obj, sourceData.sfx)
        end
        pauseSubwooferAudio()
        current_playing_sources = nil
        currentSongPath = ""
        isPlaying = false
        isPausedByUser = false
        currentTime = 0
        songElapsedTime = 0
        subwooferSyncStop()
        dirtyFlags.playbackState = true
        dirtyFlags.currentSong = true
    end
end

local function pauseCurrentSongMultiSource()
    if current_playing_sources then
        local cutSFX = obj.cutSFX
        for location, sourceData in pairs(current_playing_sources) do
            cutSFX(obj, sourceData.sfx)
        end
        pauseSubwooferAudio()
        isPlaying = false
        isPausedByUser = true
        currentTime = songElapsedTime
        subwooferSyncPause()
        dirtyFlags.playbackState = true
    end
end

local function resumeCurrentSongMultiSource()
    if currentSongPath ~= "" and isPausedByUser and current_playing_sources then
        local sources = sfx_sources[currentSongPath]
        if not sources then
            sources = prepareSongMultiSource(currentSongPath, subwooferSync.currentBassPath, true)
            if not sources then return false end
            sfx_sources[currentSongPath] = sources
            current_playing_sources = sources
        else
            local playSFX = obj.playSFX
            local cutSFX = obj.cutSFX
            for location, sourceData in pairs(sources) do
                playSFX(obj, sourceData.sfx)
            end
            if subwooferAudio.sfx and subwooferAudio.active then
                local bassGainPercent = electrics.values.bassGain or 0.5
                if bassGainPercent > 0.01 then
                    playSFX(obj, subwooferAudio.sfx)
                end
            end
            for location, sourceData in pairs(sources) do
                cutSFX(obj, sourceData.sfx)
            end
            if subwooferAudio.sfx and subwooferAudio.active then
                cutSFX(obj, subwooferAudio.sfx)
            end
            updateEqualizerVolumes()
        end
        pendingPlayback = {
            action = "resume",
            songPath = currentSongPath,
            sources = current_playing_sources
        }
        syncFrameCounter = 1
        songElapsedTime = currentTime
        return true
    end
    return false
end

local function updateMasterVolume()
    print("[Music Controller] Applying volume: " .. (volumeControl.masterVolume * 100))
    
    if current_playing_sources then
        for location, sourceData in pairs(current_playing_sources) do
            local baseVol = sourceData.eqBaseVolume or sourceData.baseVolume
            local finalVolume = baseVol * volumeControl.masterVolume
            obj:setVolumePitch(sourceData.sfx, finalVolume, 1.0)
        end
        
        if subwooferAudio.sfx and subwooferAudio.active then
            local bassGainMultiplier = electrics.values.bassGainMultiplier or 1.0
            local fade = electrics.values.equalizerFade or equalizerControl.fade
            local balance = electrics.values.equalizerBalance or equalizerControl.balance
            local eqBaseVolume = calculateSpeakerVolume(subwooferConfig.type, subwooferConfig.volume, fade, balance)
            local effectiveVolume = eqBaseVolume * volumeControl.masterVolume * bassGainMultiplier
            obj:setVolumePitch(subwooferAudio.sfx, effectiveVolume, 1.0)
        end
    end
end

local function handleVolumeControl(dt)
    local carplayVolume = electrics.values.carplayVolume
    
    if not carplayVolume then
        return
    end
    
    local newMasterVolume = carplayVolume / 100
    
    if carplayVolume ~= lastCarplayVolume then
        lastCarplayVolume = carplayVolume
        
        newMasterVolume = math_max(volumeControl.minVolume, math_min(volumeControl.maxVolume, newMasterVolume))
        
        if math_abs(volumeControl.masterVolume - newMasterVolume) > 0.001 then
            print("[Music Controller] Volume changed: " .. (volumeControl.masterVolume * 100) .. " -> " .. carplayVolume)
            volumeControl.masterVolume = newMasterVolume
            updateMasterVolume()
            dirtyFlags.volume = true
            saveMusicPreferences()
        end
    end
end

local function shuffleArray(array)
    local shuffled = {}
    local indices = {}
    for i = 1, #array do
        indices[i] = i
    end
    for i = #indices, 2, -1 do
        local j = math.random(1, i)
        indices[i], indices[j] = indices[j], indices[i]
    end
    for i = 1, #indices do
        shuffled[i] = array[indices[i]]
    end
    return shuffled
end

local function startShuffle()
    if not isQueueInitialized or #currentQueue == 0 then return false end
    shuffleEnabled = true
    math.randomseed(os_time())
    if #originalQueue == 0 then
        for i, song in ipairs(currentQueue) do
            originalQueue[i] = song
        end
    end
    local shuffledQueue = shuffleArray(currentQueue)
    currentQueue = shuffledQueue
    local startIndex = 1
    if startIndex >= 1 and startIndex <= #currentQueue then
        currentQueueIndex = startIndex
        local song = currentQueue[startIndex]
        if song then
            currentSongData = song
            isFavorited = isSongLiked(song.id)
            currentSongAlbumArt = song.albumArt or song.art or ""
            actualSongDuration = song.duration
            currentTime = 0
            songElapsedTime = 0
            dirtyFlags.currentSong = true
            if song.songPath then
                if playSongMultiSource(song.songPath, song.songBassPath, song.songDataPath) then
                    return true
                end
            end
        end
    end
    return false
end

local function initializeQueue(songs, playlistName)
    currentQueue = {}
    originalQueue = {}
    for i, song in ipairs(songs) do
        local bassPath = song.songBassPath or song.bassPath or ""
        local dataPath = song.songDataPath or song.dataPath or ""
        local albumArt = song.albumArt or song.album_art or song.cover or song.art or ""
        local songTitle = song.name or song.title or "Unknown Song"
        local songId = string_gsub(songTitle, "%s+", "_"):lower()
        currentQueue[i] = {
            name = songTitle,
            artist = song.artist or song.artistName or "",
            id = songId,
            albumArt = albumArt,
            duration = song.duration or song.length or 0,
            playlistName = playlistName,
            songPath = song.songPath or song.file or "",
            songBassPath = bassPath,
            songDataPath = dataPath
        }
    end
    currentQueueIndex = 0
    currentQueuePlaylistName = playlistName
    isQueueInitialized = true
    shuffleEnabled = false
end

local function setCurrentSongFromQueue(index)
    if not isQueueInitialized or #currentQueue == 0 then return false end
    if index < 1 or index > #currentQueue then return false end
    currentQueueIndex = index
    local song = currentQueue[index]
    if song then
        currentSongData = song
        isFavorited = isSongLiked(song.id)
        currentSongAlbumArt = song.albumArt or song.art or ""
        actualSongDuration = song.duration
        dirtyFlags.currentSong = true
        saveLastSongState()
        return true
    end
    return false
end

local function queueNext()
    if not isQueueInitialized or #currentQueue == 0 then return false end
    if currentQueueIndex < #currentQueue then
        local newIndex = currentQueueIndex + 1
        stopCurrentSongMultiSource()
        if setCurrentSongFromQueue(newIndex) then
            currentTime = 0
            songElapsedTime = 0
            local song = currentQueue[newIndex]
            if song and song.songPath then
                if playSongMultiSource(song.songPath, song.songBassPath, song.songDataPath) then
                    return true
                end
            end
        end
    end
    return false
end

local function queuePrevious()
    if not isQueueInitialized or #currentQueue == 0 then return false end
    if currentTime >= 5.0 then
        local song = currentQueue[currentQueueIndex]
        if song and song.songPath then
            stopCurrentSongMultiSource()
            currentTime = 0
            songElapsedTime = 0
            if playSongMultiSource(song.songPath, song.songBassPath, song.songDataPath) then
                return true
            end
        end
        return false
    end
    if currentQueueIndex > 1 then
        local newIndex = currentQueueIndex - 1
        stopCurrentSongMultiSource()
        if setCurrentSongFromQueue(newIndex) then
            currentTime = 0
            songElapsedTime = 0
            local song = currentQueue[newIndex]
            if song and song.songPath then
                if playSongMultiSource(song.songPath, song.songBassPath, song.songDataPath) then
                    return true
                end
            end
        end
    end
    return false
end

local function queueSelectSongById(songId)
    if not isQueueInitialized or #currentQueue == 0 then return false end
    if shuffleEnabled and #originalQueue > 0 then
        currentQueue = {}
        for i, song in ipairs(originalQueue) do
            currentQueue[i] = song
        end
        shuffleEnabled = false
    end
    for i, song in ipairs(currentQueue) do
        if song.id == songId then
            stopCurrentSongMultiSource()
            if setCurrentSongFromQueue(i) then
                currentTime = 0
                songElapsedTime = 0
                if song.songPath then
                    if playSongMultiSource(song.songPath, song.songBassPath, song.songDataPath) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function formatTime(seconds)
    if not seconds or seconds <= 0 then return "0:00" end
    local mins = math_floor(seconds / 60)
    local secs = math_floor(seconds % 60)
    return string_format("%d:%02d", mins, secs)
end

function generateLikedSongsPlaylist()
    local likedSongsPlaylist = {}
    for _, playlist in ipairs(availablePlaylists) do
        if playlist.id ~= "likedsongs" then
            local success, playlistSongs = pcall(function()
                return playlistConfig.getPlaylistSongs(playlist.id)
            end)
            if success and playlistSongs then
                for _, song in ipairs(playlistSongs) do
                    local songTitle = song.name or song.title or "Unknown Song"
                    local songId = string_gsub(songTitle, "%s+", "_"):lower()
                    if isSongLiked(songId) then
                        table_insert(likedSongsPlaylist, {
                            id = songId,
                            name = songTitle,
                            title = songTitle,
                            artist = song.artist or song.artistName or "Unknown Artist",
                            duration = song.duration or song.length or 180,
                            songPath = song.songPath or song.file,
                            albumArt = song.albumArt or song.album_art or song.cover or song.art,
                            art = song.albumArt or song.album_art or song.cover or song.art,
                            songBassPath = song.songBassPath or song.bassPath,
                            songDataPath = song.songDataPath or song.dataPath,
                            playlistName = "Liked Songs"
                        })
                    end
                end
            end
        end
    end
    return likedSongsPlaylist
end

local function loadPlaylistSongs(playlistId)
    local now = os_time()
    if playlistCache[playlistId] and cacheTimestamps[playlistId] and 
       (now - cacheTimestamps[playlistId]) < cacheTimeout then
        local playlistName = "Songs"
        if playlistId == "likedsongs" or playlistId == "savedsongs" then
            playlistName = "Liked Songs"
        else
            for _, playlist in ipairs(availablePlaylists) do
                if playlist.id == playlistId then
                    playlistName = playlist.name
                    break
                end
            end
        end
        cachedJSONData.currentViewSongs = jsonEncode(playlistCache[playlistId], "currentViewSongs")
        electrics.values.musicCurrentViewSongs = cachedJSONData.currentViewSongs
        electrics.values.musicCurrentPlaylist = playlistId
        initializeQueue(playlistCache[playlistId], playlistName)
        return
    end
    if playlistId == "likedsongs" or playlistId == "savedsongs" then
        local likedSongsData = generateLikedSongsPlaylist()
        playlistCache[playlistId] = likedSongsData
        cacheTimestamps[playlistId] = now
        cachedJSONData.currentViewSongs = jsonEncode(likedSongsData, "currentViewSongs")
        cachedJSONData.likedSongs = jsonEncode(likedSongsData, "likedSongs")
        electrics.values.musicCurrentViewSongs = cachedJSONData.currentViewSongs
        electrics.values.musicLikedSongs = cachedJSONData.likedSongs
        electrics.values.musicCurrentPlaylist = playlistId
        initializeQueue(likedSongsData, "Liked Songs")
        return
    end
    local success, songs = pcall(function()
        return playlistConfig.getPlaylistSongs(playlistId)
    end)
    if success and songs then
        local processedSongs = {}
        for i, song in ipairs(songs) do
            local albumArt = song.albumArt or song.album_art or song.cover or song.art or ""
            local songTitle = song.name or song.title or "Unknown Song"
            local songId = string_gsub(songTitle, "%s+", "_"):lower()
            processedSongs[i] = {
                name = songTitle,
                artist = song.artist or song.artistName or "",
                id = songId,
                albumArt = albumArt,
                art = albumArt,
                duration = song.duration or song.length or 0,
                songPath = song.songPath or song.file or "",
                songBassPath = song.songBassPath or song.bassPath or "",
                songDataPath = song.songDataPath or song.dataPath or ""
            }
        end
        playlistCache[playlistId] = processedSongs
        cacheTimestamps[playlistId] = now
        cachedJSONData.currentViewSongs = jsonEncode(processedSongs, "currentViewSongs")
        electrics.values.musicCurrentViewSongs = cachedJSONData.currentViewSongs
        electrics.values.musicCurrentPlaylist = playlistId
        local playlistInfo = nil
        for _, playlist in ipairs(availablePlaylists) do
            if playlist.id == playlistId then
                playlistInfo = playlist
                break
            end
        end
        initializeQueue(processedSongs, playlistInfo and playlistInfo.name or "Unknown Playlist")
    else
        initializeQueue({}, "Unknown Playlist")
    end
end

local function loadPlaylists()
    local success, playlists = pcall(function()
        return playlistConfig.getAllPlaylists()
    end)
    if success and playlists then
        local filteredPlaylists = {}
        for _, playlist in ipairs(playlists) do
            if playlist.id ~= "allsongs" then
                table_insert(filteredPlaylists, playlist)
            end
        end
        table_insert(filteredPlaylists, 1, {
            id = "likedsongs",
            name = "Liked Songs",
            coverImage = "local://local/vehicles/common/album_covers/liked_songs.png",
            songCount = #likedSongs
        })
        availablePlaylists = filteredPlaylists
        cachedJSONData.playlists = jsonEncodePlaylists(availablePlaylists)
        cachedJSONData.likedSongs = jsonEncode(generateLikedSongsPlaylist(), "likedSongs")
        electrics.values.musicPlaylistsData = cachedJSONData.playlists
        electrics.values.musicLikedSongs = cachedJSONData.likedSongs
        dirtyFlags.playlists = false
    else
        availablePlaylists = {
            {
                id = "likedsongs",
                name = "Liked Songs",
                coverImage = "local://local/vehicles/common/album_covers/liked_songs.png",
                songCount = #likedSongs
            }
        }
        cachedJSONData.playlists = jsonEncodePlaylists(availablePlaylists)
        cachedJSONData.likedSongs = jsonEncode(generateLikedSongsPlaylist(), "likedSongs")
        electrics.values.musicPlaylistsData = cachedJSONData.playlists
        electrics.values.musicLikedSongs = cachedJSONData.likedSongs
        dirtyFlags.playlists = false
    end
end

local function updateCarPlayElectrics()
    local now = os_clock()
    if (now - lastUpdateTime) < MIN_UPDATE_INTERVAL then
        return
    end
    
    if dirtyFlags.currentSong then
        if currentSongData then
            electrics.values.musicCurrentSong = currentSongData.name or "No Music Playing"
            electrics.values.musicArtist = currentSongData.artist or ""
            electrics.values.musicAlbumArt = currentSongData.albumArt or currentSongData.art or ""
            electrics.values.musicCurrentSongId = currentSongData.id or ""
            electrics.values.musicCurrentSongLiked = isFavorited and 1 or 0
            electrics.values.musicTotalTime = formatTime(actualSongDuration)
        else
            electrics.values.musicCurrentSong = "No Music Playing"
            electrics.values.musicArtist = ""
            electrics.values.musicAlbumArt = ""
            electrics.values.musicCurrentSongId = ""
            electrics.values.musicCurrentSongLiked = 0
            electrics.values.musicCurrentTime = "0:00"
            electrics.values.musicTotalTime = "0:00"
        end
        dirtyFlags.currentSong = false
    end
    
    if dirtyFlags.playbackState then
        electrics.values.musicIsPlaying = isPlaying and 1 or 0
        electrics.values.musicHasSongs = (isQueueInitialized and #currentQueue > 0) and 1 or 0
        electrics.values.musicCurrentPlaylist = currentQueuePlaylistName
        electrics.values.musicCurrentTrackIndex = currentQueueIndex
        dirtyFlags.playbackState = false
    end
    
    if dirtyFlags.volume then
        electrics.values.musicVolume = math_floor(volumeControl.masterVolume * 100)
        dirtyFlags.volume = false
    end
    
    if dirtyFlags.likedSongs then
        cachedJSONData.likedSongs = jsonEncode(generateLikedSongsPlaylist(), "likedSongs")
        electrics.values.musicLikedSongs = cachedJSONData.likedSongs
        for i, playlist in ipairs(availablePlaylists) do
            if playlist.id == "likedsongs" then
                availablePlaylists[i].songCount = #likedSongs
                cachedJSONData.playlists = jsonEncodePlaylists(availablePlaylists)
                electrics.values.musicPlaylistsData = cachedJSONData.playlists
                break
            end
        end
        dirtyFlags.likedSongs = false
    end
    
    if isPlaying then
        electrics.values.musicCurrentTime = formatTime(currentTime)
    end
    
    lastUpdateTime = now
end

local function handleCarPlayLibraryCommand()
    local command = electrics.values.carplayLibraryCommand or ""
    if command == "" then return end
    if command == "loadPlaylistSongs" then
        local playlistId = electrics.values.carplayLibraryPlaylistId or ""
        if playlistId ~= "" then
            loadPlaylistSongs(playlistId)
        end
    elseif command == "playSong" then
        local playlistId = electrics.values.carplayLibraryPlaylistId or ""
        local songIndex = electrics.values.carplayLibrarySongIndex or 0
        if playlistId ~= "" and songIndex >= 0 then
            if not isQueueInitialized or currentQueuePlaylistName ~= playlistId then
                loadPlaylistSongs(playlistId)
            end
            if isQueueInitialized and #currentQueue > 0 then
                local targetIndex = songIndex + 1
                if targetIndex >= 1 and targetIndex <= #currentQueue then
                    stopCurrentSongMultiSource()
                    if setCurrentSongFromQueue(targetIndex) then
                        currentTime = 0
                        songElapsedTime = 0
                        local song = currentQueue[targetIndex]
                        if song and song.songPath then
                            playSongMultiSource(song.songPath, song.songBassPath, song.songDataPath)
                        end
                    end
                end
            end
        end
    elseif command == "shuffleAll" then
        local playlistId = electrics.values.carplayLibraryPlaylistId or ""
        if playlistId ~= "" then
            if not isQueueInitialized or currentQueuePlaylistName ~= playlistId then
                loadPlaylistSongs(playlistId)
            end
            if isQueueInitialized and #currentQueue > 0 then
                startShuffle()
            end
        end
    end
    electrics.values.carplayLibraryCommand = ""
end

local saveStateTimer = 0
local SAVE_STATE_INTERVAL = 15

local function init(jbeamData)
    local requiredTexture = "/vehicles/sdd_f87/textures/xx.dds"
    
    if not FS:fileExists(requiredTexture) then
        return
    end
    
    if not isInitialized then
        isInitialized = true
        
        nodeIDCache = {}
        subwooferNodeID = nil
        jsonEncodeCache = {}
        jsonEncodeCacheTime = {}
        
        subwooferSyncReset()
        subwooferAudio.sfx = nil
        subwooferAudio.nodeId = 0
        subwooferAudio.active = false
        subwooferAudio.isPlaying = false
        loadLikedSongs()
        
        loadMusicPreferences()

        local savedVolume = electrics.values.carplayVolume or math_floor(volumeControl.masterVolume * 100)
        volumeControl.masterVolume = savedVolume / 100
        
        electrics.values.musicShuffle = shuffleEnabled and 1 or 0
        electrics.values.musicRepeat = repeatModeIndex
        electrics.values.musicVolume = savedVolume
        
        electrics.values.musicIsPlaying = 0
        electrics.values.musicCurrentSong = "No Music Playing"
        electrics.values.musicArtist = ""
        electrics.values.musicAlbumArt = ""
        electrics.values.musicCurrentTime = "0:00"
        electrics.values.musicTotalTime = "0:00"
        electrics.values.musicCurrentSongId = ""
        electrics.values.musicCurrentSongLiked = 0
        electrics.values.musicPlaylistsData = "[]"
        electrics.values.musicLikedSongs = "[]"
        electrics.values.musicHasSongs = 0
        electrics.values.musicCurrentPlaylist = ""
        electrics.values.musicCurrentTrackIndex = 0
        electrics.values.musicCurrentViewSongs = "[]"
        electrics.values.musicPlayPause = 0
        electrics.values.musicNext = 0
        electrics.values.musicPrevious = 0
        electrics.values.musicRepeatToggle = 0
        electrics.values.musicToggleCurrentLike = 0
        electrics.values.musicShuffleToggle = 0
        electrics.values.carplayLibraryCommand = ""
        electrics.values.carplayLibraryPlaylistId = ""
        electrics.values.carplayLibrarySongIndex = 0
        electrics.values.carplayLibrarySongId = ""
        electrics.values.equalizerFade = equalizerControl.fade
        electrics.values.equalizerBalance = equalizerControl.balance
        electrics.values.equalizerBass = equalizerControl.bass
        electrics.values.rlaSubwooferDriver = 0
        sfx_sources = {}
        current_playing_sources = nil
        currentSongPath = ""
        songElapsedTime = 0
        musicSystemActive = false
        loadPlaylists()
        
        if loadLastSongState() and lastSongState.hasBeenSet then
            isRestoringState = true
            loadPlaylistSongs(lastSongState.playlistId)
            if isQueueInitialized and lastSongState.trackIndex <= #currentQueue then
                setCurrentSongFromQueue(lastSongState.trackIndex)
            end
            isRestoringState = false
        end
        
        updateCarPlayElectrics()
    end
end

local function updateGFX(dt)
    handleVolumeControl(dt)
    
    if pendingPlayback and syncFrameCounter > 0 then
        syncFrameCounter = syncFrameCounter - 1
        if syncFrameCounter == 0 then
            executeSyncPlayback()
        end
    end
    
    updateSubwooferSync(dt)
    updateBassGainControl()
    
    if dirtyFlags.equalizer then
        updateEqualizerVolumes()
    else
        local currentFade = electrics.values.equalizerFade
        local currentBalance = electrics.values.equalizerBalance
        local currentBass = electrics.values.equalizerBass
        if currentFade and currentBalance then
            if currentFade ~= equalizerControl.fade or 
               currentBalance ~= equalizerControl.balance or
               (currentBass and currentBass ~= equalizerControl.bass) then
                equalizerControl.fade = currentFade
                equalizerControl.balance = currentBalance
                equalizerControl.bass = currentBass or 50
                dirtyFlags.equalizer = true
            end
        end
    end
    
    updateTimer = updateTimer + dt
    if updateTimer > invFPS then
        updateTimer = 0
        handleCarPlayLibraryCommand()
        
        if electrics.values.musicPlayPause == 1 then
            if isPlaying then
                pauseCurrentSongMultiSource()
            else
                resumeCurrentSongMultiSource()
            end
            electrics.values.musicPlayPause = 0
        end
        
        if electrics.values.musicNext == 1 then
            queueNext()
            electrics.values.musicNext = 0
        end
        
        if electrics.values.musicPrevious == 1 then
            queuePrevious()
            electrics.values.musicPrevious = 0
        end
        
        if electrics.values.musicShuffleToggle == 1 then
            if not shuffleEnabled then
                shuffleEnabled = true
                if isQueueInitialized and #currentQueue > 0 then
                    startShuffle()
                end
            else
                shuffleEnabled = false
                if #originalQueue > 0 then
                    currentQueue = {}
                    for i, song in ipairs(originalQueue) do
                        currentQueue[i] = song
                    end
                    originalQueue = {}
                end
            end
            electrics.values.musicShuffle = shuffleEnabled and 1 or 0
            saveMusicPreferences()
            electrics.values.musicShuffleToggle = 0
        end
        
        if electrics.values.musicRepeatToggle == 1 then
            repeatModeIndex = (repeatModeIndex + 1) % 3
            if repeatModeIndex == 0 then
                repeatMode = "off"
            elseif repeatModeIndex == 1 then
                repeatMode = "all"
            else
                repeatMode = "track"
            end
            electrics.values.musicRepeat = repeatModeIndex
            saveMusicPreferences()
            electrics.values.musicRepeatToggle = 0
        end
        
        if electrics.values.musicToggleCurrentLike == 1 then
            if currentSongData and currentSongData.id then
                if isFavorited then
                    removeSongFromLiked(currentSongData.id)
                    isFavorited = false
                else
                    addSongToLiked(currentSongData.id)
                    isFavorited = true
                end
                electrics.values.musicCurrentSongLiked = isFavorited and 1 or 0
                dirtyFlags.likedSongs = true
            end
            electrics.values.musicToggleCurrentLike = 0
        end
        
        updateCarPlayElectrics()
    end
    
    if isPlaying and current_playing_sources and not isPausedByUser then
        songElapsedTime = songElapsedTime + dt
        currentTime = songElapsedTime
        if actualSongDuration > 0 and currentTime >= actualSongDuration then
            currentTime = actualSongDuration
            stopCurrentSongMultiSource()
            if repeatMode == "track" then
                local song = currentQueue[currentQueueIndex]
                if song and song.songPath then
                    currentTime = 0
                    songElapsedTime = 0
                    playSongMultiSource(song.songPath, song.songBassPath, song.songDataPath)
                end
            elseif repeatMode == "all" then
                if currentQueueIndex < #currentQueue then
                    queueNext()
                else
                    if setCurrentSongFromQueue(1) then
                        currentTime = 0
                        songElapsedTime = 0
                        local song = currentQueue[1]
                        if song and song.songPath then
                            playSongMultiSource(song.songPath, song.songBassPath, song.songDataPath)
                        end
                    end
                end
            else
                queueNext()
            end
        end
        
        if updateTimer <= invFPS then
            electrics.values.musicCurrentTime = formatTime(currentTime)
        end
    end
    
    saveStateTimer = saveStateTimer + dt
    if isPlaying and saveStateTimer >= SAVE_STATE_INTERVAL then
        saveLastSongState()
        saveStateTimer = 0
    end
end

local function onReset()
    if pendingPlayback then
        pendingPlayback = nil
        syncFrameCounter = 0
    end
    
    nodeIDCache = {}
    subwooferNodeID = nil
    jsonEncodeCache = {}
    jsonEncodeCacheTime = {}
    lastCarplayVolume = -1
    
    for songPath, sources in pairs(sfx_sources) do
        if sources ~= current_playing_sources then
            for location, sourceData in pairs(sources) do
                obj:cutSFX(sourceData.sfx)
                obj:deleteSFXSource(sourceData.sfx)
            end
            sfx_sources[songPath] = nil
        end
    end
    stopSubwooferAudio()
    subwooferSyncReset()
end

local function onExtensionUnloaded()
    saveLikedSongs()
    saveLastSongState()
    saveMusicPreferences()
    stopSubwooferAudio()
end

M.init = init
M.updateGFX = updateGFX
M.onReset = onReset
M.onExtensionUnloaded = onExtensionUnloaded

return M