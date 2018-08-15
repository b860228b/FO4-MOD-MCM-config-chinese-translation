local Lib3D = LibStub("Lib3D2")
local GPS = LibStub("LibGPS2")

if not Harvest.Data then
	Harvest.Data = {}
end

local Harvest = _G["Harvest"]
local Data = Harvest.Data
local CallbackManager = Harvest.callbackManager
local Events = Harvest.events

Data.dataDefault = {
	data = {},
	dataVersion = Harvest.dataVersion,
	-- table below is only added for backward compatibility with the merge website, until it gets updated
	--["Default"] = {
	--	["@MergeCompatibility"] = {
	--		["$AccountWide"] = {
	--			["nodes"] =  {
	--				["data"] =  {},
	--				["dataVersion"] = 16,
	--			},
	--		},
	--	},
	--},
}
Data.subModules = {}

local addOnNameToGlobal = {
	HarvestMapAD = "HarvestAD",
	HarvestMapEP = "HarvestEP",
	HarvestMapDC = "HarvestDC",
	HarvestMapDLC = "HarvestDLC",
	HarvestMapNF = "HarvestNF",
	HarvestMap = "Harvest"
}
local addOnNameToZones = {
	HarvestMapAD = {
		["auridon"] = true,
		["grahtwood"] = true,
		["greenshade"] = true,
		["malabaltor"] = true,
		["reapersmarch"] = true
	},
	HarvestMapEP = {
		["bleakrock"] = true,
		["stonefalls"] = true,
		["deshaan"] = true,
		["shadowfen"] = true,
		["eastmarch"] = true,
		["therift"] = true
	},
	HarvestMapDC = {
		["glenumbra"] = true,
		["stormhaven"] = true,
		["rivenspire"] = true,
		["alikr"] = true,
		["bangkorai"] = true
	},
	HarvestMapDLC = {
		--imperialcity, part of cyrodiil
		["wrothgar"] = true,
		["thievesguild"] = true,
		["darkbrotherhood"] = true,
		--dungeonthingy, does that one even have a prefix?
		["vvardenfell"] = true,
		-- 2nd dungeon thingy
		["clockwork"] = true,
		["summerset"] = true,
	},
}

function Data:CheckSubModule(addOnName)
	local globalVarName = addOnNameToGlobal[addOnName]
	if not globalVarName then return end
	
	subModule = {}
	subModule.zones = addOnNameToZones[addOnName]
	self.subModules[globalVarName] = subModule
	
end

local function addMissing(result, template)
	for key, value in pairs(template) do
		if type(value) == "table" then
			result[key] = result[key] or {}
			addMissing(result[key], value)
		else
			result[key] = result[key] or value
		end
	end
end

function Data:LoadSavedVars()
	-- load data stored in submodules
	local savedVarName
	for subModuleName, module in pairs(self.subModules) do
		savedVarName = subModuleName .. "_SavedVars"
		_G[savedVarName] = _G[savedVarName] or {}
		module.savedVars = _G[savedVarName]
		module.savedVarsName = savedVarName
		
		if not module.savedVars.firstLoaded then
			module.savedVars.firstLoaded = GetTimeStamp()
		end
		module.savedVars.lastLoaded = GetTimeStamp()
	end
	self.backupSavedVars = self.subModules["Harvest"]
	
	self:AddMissingFields()
end

function Data:AddMissingFields()
	for subModuleName, module in pairs(self.subModules) do
		addMissing(module.savedVars, self.dataDefault)
	end
end

function Data:ClearCaches()
	self.currentZoneCache = nil
	self.mapCaches = {}
	self.numCaches = 0
	CallbackManager:FireCallbacks(Events.SETTING_CHANGED, "cacheCleared")
end

function Data:Initialize()
	-- cache the ACE deserialized nodes
	-- this way changing maps multiple times will create less lag
	self.mapCaches = {}
	self.numCaches = 0
	
	-- load nodes
	Harvest.AddToUpdateQueue(function() self:LoadSavedVars() end)
	
	-- check if saved data is from an older version,
	-- update the data if needed
	Harvest.AddToUpdateQueue(function() self:UpdateDataVersion() end)
	
	-- move data to correct save files
	-- if AD was disabled while harvesting in AD, everything was saved in self.savedvars
	-- when ad is enabled, everything needs to be moved to that save file
	-- HOWEVER, only execute this after the save files were updated!
	Harvest.AddToUpdateQueue(function() self:MoveData() end)
	
	-- when the time setting is changed, all caches need to be reloaded
	local clearCache = function(event, setting, value)
		if setting == "applyTimeDifference" then
			self:ClearCaches()
		end
	end
	CallbackManager:RegisterForEvent(Events.SETTING_CHANGED, clearCache)
	CallbackManager:RegisterForEvent(Events.NODE_DISCOVERED, function(event, map, x, y, z, measurement, zoneIndex, pinTypeId)
		self:SaveNode(map, x, y, z, measurement, zoneIndex, pinTypeId)
	end)
	
	EVENT_MANAGER:RegisterForEvent("HarvestMapNewZone", EVENT_PLAYER_ACTIVATED, function() self:OnPlayerActivated() end)
end

function Data:IsNodeDataValid( map, x, y, z, measurement, zoneIndex, pinTypeId )
	if not map then
		Harvest.Debug( "SaveData failed: map is nil" )
		return false
	end
	if type(x) ~= "number" or type(y) ~= "number" then
		Harvest.Debug( "SaveData failed: coordinates aren't numbers" )
		return false
	end
	if not measurement then
		Harvest.Debug( "SaveData failed: measurement is nil" )
		return false
	end
	if not pinTypeId then
		Harvest.Debug( "SaveData failed: pin type id is nil" )
		return false
	end
	if Harvest.IsMapBlacklisted( map ) then
		Harvest.Debug( "SaveData failed: map " .. tostring(map) .. " is blacklisted" )
		return
	end
	if x <= 0 or x >= 1 or y <= 0 or y >= 1 then
		Harvest.Debug( "SaveData failed: coords are outside of the map" )
		return
	end
	return true
end

-- this function tries to save the given data
-- this function is only used by the harvesting part of HarvestMap
function Data:SaveNode( map, x, y, z, measurement, zoneIndex, pinTypeId )
	local pinTypeIdAlias = Harvest.PINTYPE_ALIAS[pinTypeId]
	if pinTypeIdAlias then
		self:SaveNode( map, x, y, z, measurement, zoneIndex, pinTypeIdAlias )
	end
	
	
	if not self:IsNodeDataValid( map, x, y, z, measurement, zoneIndex, pinTypeId ) then return end
	if not Harvest.IsPinTypeSavedOnGather( pinTypeId ) then return end
	
	
	local saveFile = self:GetSaveFile( map )
	if not saveFile then return end
	saveFile = saveFile.savedVars
	-- save file tables might not exist yet
	saveFile.data[ map ] = saveFile.data[ map ] or {}
	saveFile.data[ map ][ pinTypeId ] = saveFile.data[ map ][ pinTypeId ] or {}

	local cache = self.mapCaches[map]
	if not cache then return end
	
	local stamp = GetTimeStamp()
	
	-- if the pintype is not already in the cache, just add the node to the savefile
	-- it will be merged the next time the pin type is loaded to the cache
	local ignoreCache = not cache.nodesOfPinType[pinTypeId]
	if not ignoreCache then
		-- If we have found this node already then we don't need to save it again
		local nodeId = cache:GetMergeableNode( pinTypeId, x, y )
		if nodeId then
			local x, y, z, stamp, nodeVersion, globalX, globalY, flags = cache:Merge(nodeId, x, y, z, stamp, Harvest.nodeVersion)
			-- serialize the node for the save file
			local nodeIndex = cache.nodeIndex[ nodeId ]
			saveFile.data[ map ][ pinTypeId ][ nodeIndex ] = self:Serialize( x, y, z, stamp, nodeVersion, globalX, globalY, flags )
			
			CallbackManager:FireCallbacks(Events.NODE_UPDATED, map, pinTypeId, nodeId, cache)
			Harvest.Debug( "data was merged with a previous node" )
			return
		end
	end
	
	-- we need to save the data in serialized form in the save file,
	-- but also as deserialized table in the cache table for faster access.
	local nodeIndex = (#saveFile.data[ map ][ pinTypeId ]) + 1
	
	local globalX, globalY, flags
	if ignoreCache then
		globalX = cache.measurement.scaleX * x + cache.measurement.offsetX
		globalY = cache.measurement.scaleY * y + cache.measurement.offsetY
		flags = nil
	else
		nodeId = cache:Add( pinTypeId, nodeIndex, x, y, z, stamp, Harvest.nodeVersion )
		globalX = cache.globalX[nodeId]
		globalY = cache.globalY[nodeId]
		flags = cache.flags[nodeId]
	end
	
	saveFile.data[ map ][ pinTypeId ][nodeIndex] = self:Serialize( x, y, z, stamp, Harvest.nodeVersion, globalX, globalY, flags )
	
	if not ignoreCache then
		CallbackManager:FireCallbacks( Events.NODE_ADDED, map, pinTypeId, nodeId, cache )
	end
	
	Harvest.Debug( "data was saved as a new node" )
end

-- imports all the nodes on 'map' from the table 'data' into the save file table 'saveFile'
-- if checkPinType is true, data will be skipped if Harvest.IsPinTypeSavedOnImport(pinTypeId) returns false
function Data:ImportFromMap( map, newMapData, saveFile, checkPinType )
	
	local existingData = saveFile.savedVars.data
	-- nothing to merge, data can simply be copied
	if existingData[ map ] == nil then
		existingData[ map ] = newMapData
		return
	end
	existingData = existingData[ map ]
	
	for _, pinTypeId in ipairs(Harvest.PINTYPES) do
		if newMapData[ pinTypeId ] then
			if (not checkPinType) or Harvest.IsPinTypeSavedOnImport( pinTypeId ) then
				if existingData[ pinTypeId ] == nil then
					-- nothing to merge for this pin type, just copy the data
					existingData[ pinTypeId ] = newMapData[ pinTypeId ]
				else
					local existingPinTypeData = existingData[ pinTypeId ]
					for nodeIndex, node in pairs( newMapData[ pinTypeId ] ) do
						table.insert(existingPinTypeData, node)
					end
				end
			end
		end
	end
	-- as new data was added to the map, the appropiate cache has to be cleared
	local existingCache = self.mapCaches[map]
	if existingCache then
		self.mapCaches[map] = nil
		self.numCaches = self.numCaches - 1
		CallbackManager:FireCallbacks(Events.SETTING_CHANGED, "cacheCleared", map)
	end
end

-- returns the correct table for the map (HarvestMap, HarvestMapAD/DC/EP save file tables)
-- will return HarvestMap's table if the correct table doesn't currently exist.
-- ie the HarvestMapAD addon isn't currently active
function Data:GetSaveFile( map )
	return self:GetSpecialSaveFile( map ) or self.backupSavedVars
end

-- returns the correct (external) table for the map or nil if no such table exists
function Data:GetSpecialSaveFile( map )
	local zone = string.gsub( map, "/.*$", "" )
	for subModuleName, subModule in pairs(self.subModules) do
		if subModule.zones and subModule.zones[ zone ] then
			return subModule
		end
	end
	if self.subModules["HarvestNF"] then
		for name, zones in pairs(addOnNameToZones) do
			if zones[map] then
				return nil
			end
		end
		return self.subModules["HarvestNF"]
	end
	return nil
end

-- this function moves data from the HarvestMap addon to HarvestMapAD/DC/EP
function Data:MoveData()
	for map, data in pairs( self.backupSavedVars.savedVars.data ) do
		local zone = string.gsub( map, "/.*$", "" )
		local file = self:GetSpecialSaveFile( map )
		if file ~= nil then
			self:ImportFromMap( map, data, file )
			self.backupSavedVars.savedVars.data[ map ] = nil
		end
	end
end

-- data is stored as strings
-- this functions deserializes the strings and saves the results in the cache
function Data:LoadToCache(pinTypeId, cache)
	
	cache:InitializePinType(pinTypeId)
	local map = cache.map
	local measurement = cache.measurement
	
	if not measurement then
		Harvest.Debug("could not load cache for map " .. tostring(map))
		Harvest.Debug("no measurement given!")
		return
	end
	
	local saveFile = self:GetSaveFile(map)
	
	Harvest.Debug("filling cache for map " .. tostring(map))
	Harvest.Debug("filling cache for pintype " .. tostring(pinTypeId))
	Harvest.Debug("loading data from file " .. tostring(saveFile.savedVarsName))
	
	saveFile = saveFile.savedVars
	saveFile.data[ map ] = (saveFile.data[ map ]) or {}
	saveFile.data[ map ][ pinTypeId ] = (saveFile.data[ map ][ pinTypeId ]) or {}
	local serializedNodes = saveFile.data[ map ][ pinTypeId ]

	local currentTimestamp = GetTimeStamp()
	local maxTimeDifference = Harvest.GetMaxTimeDifference() * 3600
	local minGameVersion = Harvest.GetMinGameVersion()
	
	local numAdded, numRemoved, numMerged = 0, 0, 0
	
	local valid, updated
	local success, x, y, z, names, timestamp, version, globalX, globalY, flags
	-- deserialize the nodes
	for nodeIndex, node in pairs( serializedNodes ) do
		success, x, y, z, timestamp, version, globalX, globalY, flags = self:Deserialize( node, pinTypeId )
		if not success then--or not x or not y then
			Harvest.AddToErrorLog("invalid node:" .. x)
			serializedNodes[nodeIndex] = nil
		else
			valid = true
			updated = false
			-- remove nodes that are too old (either number of days or patch)
			if maxTimeDifference > 0 and currentTimestamp - timestamp > maxTimeDifference then
				valid = false
				Harvest.AddToErrorLog("outdated node:" .. map .. node )
			end
			
			if minGameVersion > 0 and zo_floor(version / 1000) < minGameVersion then
				valid = false
				Harvest.AddToErrorLog("outdated node:" .. map .. node )
			end
			
			-- remove close nodes (ie duplicates on cities)
			if valid then
				local nodeId = cache:GetMergeableNode( pinTypeId, x, y, false )
				if nodeId then
					x, y, z, timestamp, version, globalX, globalY = cache:Merge(nodeId, x, y, z, timestamp, version, globalX, globalY, flags)
					-- update the old node
					serializedNodes[cache.nodeIndex[nodeId] ] = self:Serialize(x, y, z, timestamp, version, globalX, globalY, flags)
					Harvest.AddToErrorLog("node was merged:" .. map .. node )
					numMerged = numMerged + 1
					valid = false -- set this to false, so the node isn't added to the cache
				end
			end
			
			if valid then
				cache:Add(pinTypeId, nodeIndex, x, y, z, timestamp, version, globalX, globalY, flags)
				numAdded = numAdded + 1
				if updated then
					serializedNodes[nodeIndex] = self:Serialize(x, y, z, timestamp, version, globalX, globalY, flags)
				end
			else
				numRemoved = numRemoved + 1
				serializedNodes[nodeIndex] = nil
			end
		end
	end
	
	Harvest.Debug("added " .. numAdded .. " nodes")
	Harvest.Debug("merged " .. numMerged .. " nodes")
	Harvest.Debug("removed " .. numRemoved .. " entries (includes merged nodes)")
end

-- loads the nodes to cache and returns them
function Data:GetMapCache(pinTypeId, map, measurement, zoneIndex, forceZoneIndex)
	if (not map) or (not measurement) or (not zoneIndex) then
		Harvest.Debug("map, measurement or zoneId missing")
		return
	end
	
	if not Harvest.IsUpdateQueueEmpty() then return end
	-- if the current map isn't in the cache, create the cache
	if not self.mapCaches[map] then
		if not measurement or not zoneIndex then return end
		
		local cache = Data.MapCache:New(map, measurement, zoneIndex)
		
		self.mapCaches[map] = cache
		self.numCaches = self.numCaches + 1
		
		local oldest = cache
		local oldestMap
		for i = 1, self.numCaches - Harvest.GetMaxCachedMaps() do
			for map, cache in pairs(self.mapCaches) do
				if cache.time < oldest.time and cache.accessed == 0 then
					oldest = cache
					oldestMap = map
				end
			end
			
			if not oldestMap then break end
			
			Harvest.Debug("Clear cache for map " .. oldestMap)
			self.mapCaches[oldestMap] = nil
			oldest = cache
			self.numCaches = self.numCaches - 1
		end
		
		-- fill the newly created cache with data
		for _, pinTypeId in ipairs(Harvest.PINTYPES) do
			if Harvest.IsPinTypeVisible(pinTypeId) then
				self:LoadToCache(pinTypeId, cache)
			end
		end
		
		if self.currentZoneCache and zoneIndex == self.currentZoneCache.zoneIndex then
			self.currentZoneCache:AddCache(cache)
			CallbackManager:FireCallbacks(Events.MAP_ADDED_TO_ZONE, cache, self.currentZoneCache)
		end
		
		return cache
	end
	local cache = self.mapCaches[map]
	-- if there was a pin type given, make sure the given pin type is in the cache
	if pinTypeId then
		self:CheckPinTypeInCache(pinTypeId, cache)
	else
		for _, pinTypeId in ipairs(Harvest.PINTYPES) do
			if Harvest.IsPinTypeVisible(pinTypeId) then
				self:CheckPinTypeInCache(pinTypeId, cache)
			end
		end
	end
	
	if forceZoneIndex and cache.zoneIndex ~= zoneIndex then
		cache.zoneIndex = zoneIndex
		if self.currentZoneCache and zoneIndex == self.currentZoneCache.zoneIndex then
			self.currentZoneCache:AddCache(cache)
			CallbackManager:FireCallbacks(Events.MAP_ADDED_TO_ZONE, cache, self.currentZoneCache)
		end
	end

	return cache
end

function Data:GetCurrentZoneCache()
	return self.currentZoneCache
end

function Data:OnPlayerActivated()
	local zoneIndex = GetUnitZoneIndex("player")
	if not self.currentZoneCache or self.currentZoneCache.zoneIndex ~= zoneIndex then
		if self.currentZoneCache then
			self.currentZoneCache:Dispose()
		end
		
		self.currentZoneCache = self.ZoneCache:New(zoneIndex)
		for map, mapCache in pairs(self.mapCaches) do
			if mapCache.zoneIndex == zoneIndex then
				self.currentZoneCache:AddCache(mapCache)
			end
		end
		
		self:BuildHierachy()
		
		local map, x, y, measurement = Harvest.GetLocation()
		local pinTypeId = nil
		local forceZoneIndex = true
		Data:GetMapCache(pinTypeId, map, measurement, zoneIndex, forceZoneIndex)
		
		CallbackManager:FireCallbacks(Events.NEW_ZONE_ENTERED, self.currentZoneCache, measurement.distanceCorrection)
		
	end
end

function Data.BuildHierachy()
	Harvest.Debug("request building hierachy")
	if not Harvest.IsUpdateQueueEmpty() then
		Harvest.AddToUpdateQueueIfNotOnTop(Data.BuildHierachy)
		return
	end
	
	local mapCanged = (SetMapToPlayerLocation() == SET_MAP_RESULT_MAP_CHANGED)
	while (MapZoomOut() == SET_MAP_RESULT_MAP_CHANGED) do
		local newParentMapName = GetMapTileTexture()
		-- failsave to prevent endless loops caused by API bugs
		if lastParentMapName == newParentMapName then break end
		
		local measurement = GPS:GetCurrentMapMeasurements()
		if not measurement then break end
		
		local parentZoneIndex = GetCurrentMapZoneIndex()
		if parentZoneIndex ~= Data.currentZoneCache.zoneIndex then break end
		local parentMap = Harvest.GetMap()
		
		measurement = Harvest.Combine3DInfoWithMeasurement( GetMapType(), parentMap, measurement, parentZoneIndex)
		
		local pinTypeId = nil
		Data:GetMapCache(pinTypeId, parentMap, measurement, parentZoneIndex)
	end
	SetMapToPlayerLocation()
	if mapCanged then
		CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged")
	end
end

function Data:CheckPinTypeInCache(pinTypeId, mapCache)
	if not mapCache.nodesOfPinType[pinTypeId] then
		self:LoadToCache(pinTypeId, mapCache)
	end
end
