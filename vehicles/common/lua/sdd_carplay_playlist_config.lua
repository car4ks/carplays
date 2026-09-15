-- sdd_carplay_playlist_config.lua
local M = {}

-- Initialize with empty playlists
M.playlists = {}

-- Track loaded files to prevent duplicates
local loadedFiles = {}

function M.addPlaylist(playlistId, name, coverImage, songs)
    M.playlists[playlistId] = {
        name = name or playlistId,
        coverImage = coverImage or "local://local/vehicles/common/album_covers/default_playlist.png",
        songs = songs or {}
    }
    print("Added new playlist: " .. (name or playlistId) .. " with " .. #(songs or {}) .. " songs")
end

function M.mergePlaylist(playlistId, name, coverImage, songs)
    print("Creating playlist " .. playlistId .. " with " .. #songs .. " songs")
    
    -- Replace/create the playlist (same as before)
    M.playlists[playlistId] = {
        name = name or playlistId,
        coverImage = coverImage or "local://local/vehicles/common/album_covers/default_playlist.png",
        songs = songs or {}
    }
    
    print("Created playlist: " .. (name or playlistId) .. " with " .. #(songs or {}) .. " songs")
end

local function loadAdditionalSongs()
    print("Scanning for playlist files...")
    
    -- Directories to scan for playlist files
    local searchPaths = {
        "/vehicles/common/lua/songs/",
        "/vehicles/sdd_g82/lua/songs/",  -- Your specific vehicle
        "/lua/common/songs/",
        "/lua/songs/",
        "/lua/playlists/",
        "/vehicles/common/lua/playlists/"
    }
    
    -- Scan each directory for ANY .lua files
    if FS and FS.findFiles then
        for _, basePath in ipairs(searchPaths) do
            local success, files = pcall(function()
                return FS:findFiles(basePath, "*.lua", -1, true, false)
            end)
            
            if success and files then
                for _, file in ipairs(files) do
                    -- Skip the main sdd_carplay_playlist_config.lua file and already loaded files
                    if not file:match("sdd_carplay_playlist_config%.lua$") and not loadedFiles[file] then
                        local status, result = pcall(function()
                            print("Loading playlist file: " .. file)
                            dofile(file)
                            loadedFiles[file] = true  -- Mark as loaded
                        end)
                        
                        if status then
                            print("Successfully loaded: " .. file)
                        else
                            print("Error loading " .. file .. ": " .. tostring(result))
                        end
                    end
                end
            end
        end
    else
        print("FS not available - using fallback method")
        -- Fallback: try to load known files directly
        local commonFiles = {

        }
        
        for _, file in ipairs(commonFiles) do
            if not loadedFiles[file] then
                local success, result = pcall(function()
                    dofile(file)
                    loadedFiles[file] = true
                end)
                if success then
                    print("Successfully loaded (fallback): " .. file)
                end
            end
        end
    end
    
    print("Finished loading playlist files. Total playlists: " .. M.getPlaylistCount())
end

function M.getPlaylistCount()
    local count = 0
    for _ in pairs(M.playlists) do
        count = count + 1
    end
    return count
end

function M.getAllSongs()
    -- Load playlist files only once
    loadAdditionalSongs()
    
    local allSongs = {}
    for playlistId, playlistData in pairs(M.playlists) do
        if type(playlistData) == "table" and playlistData.songs then
            for _, song in ipairs(playlistData.songs) do
                -- Add playlist info to each song
                local songWithPlaylist = {}
                for k, v in pairs(song) do
                    songWithPlaylist[k] = v
                end
                songWithPlaylist.playlistId = playlistId
                songWithPlaylist.playlistName = playlistData.name or playlistId
                table.insert(allSongs, songWithPlaylist)
            end
        end
    end
    print("Total songs gathered: " .. #allSongs)
    return allSongs
end

function M.getPlaylistSongs(playlistId)
    if playlistId == "allsongs" then
        return M.getAllSongs()
    elseif M.playlists[playlistId] then
        return M.playlists[playlistId].songs or {}
    end
    return {}
end

function M.getPlaylistInfo(playlistId)
    if playlistId == "allsongs" then
        local totalSongs = #M.getAllSongs()
        return {
            id = "allsongs",
            name = "All Songs",
            coverImage = "local://local/vehicles/common/album_covers/default_playlist.png",
            songCount = totalSongs
        }
    elseif M.playlists[playlistId] then
        local playlist = M.playlists[playlistId]
        return {
            id = playlistId,
            name = playlist.name,
            coverImage = playlist.coverImage,
            songCount = #(playlist.songs or {})
        }
    end
    return nil
end

function M.getAllPlaylists()
    -- Load playlist files only once
    loadAdditionalSongs()
    
    local playlists = {}
    
    -- Always add "All Songs" first
    local allSongsInfo = M.getPlaylistInfo("allsongs")
    if allSongsInfo and allSongsInfo.songCount > 0 then
        table.insert(playlists, allSongsInfo)
    end
    
    -- Add individual playlists
    for playlistId, playlistData in pairs(M.playlists) do
        if type(playlistData) == "table" then
            table.insert(playlists, {
                id = playlistId,
                name = playlistData.name or playlistId,
                coverImage = playlistData.coverImage or "local://local/vehicles/common/album_covers/default_playlist.png",
                songCount = #(playlistData.songs or {})
            })
        end
    end
    
    print("Returning " .. #playlists .. " total playlists")
    return playlists
end

-- Clear loaded files cache (for debugging)
function M.clearCache()
    loadedFiles = {}
    M.playlists = {}
    print("Playlist cache cleared")
end

return M