local Harvest = _G["Harvest"]

local ZoneCache = ZO_Object:Subclass()
Harvest.Data.ZoneCache = ZoneCache

function ZoneCache:New(...)
	local obj = ZO_Object.New(self)
	obj:Initialize(...)
	return obj
end

function ZoneCache:Initialize(zoneIndex)
	self.zoneIndex = zoneIndex
	self.mapCaches = {}
	self.estimatedNumOfPins = 0
end

function ZoneCache:AddCache(cache)
	local prevCache = self.mapCaches[cache.map]
	if prevCache == cache then
		return
	end
	if prevCache then
		prevCache.accessed = prevCache.accessed - 1
		self.mapCaches[cache.map] = nil
		--self.estimatedNumOfPins = self.estimatedNumOfPins - prevCache.lastNodeId
	else
		self.estimatedNumOfPins = self.estimatedNumOfPins + cache.lastNodeId
	end
	-- check if some nodes exist on both caches
	local pinTypeId, x, y, measurement, otherNode
	for map, otherCache in pairs(self.mapCaches) do
		measurement = otherCache.measurement
		for nodeId = 1, cache.lastNodeId do
			pinTypeId = cache.pinTypeId[nodeId]
			if pinTypeId then
				x = (cache.globalX[nodeId] - measurement.offsetX) / measurement.scaleX
				y = (cache.globalY[nodeId] - measurement.offsetY) / measurement.scaleY
				if x > 0 and x < 1 and y > 0 and y < 1 then
					otherNode = otherCache:GetMergeableNode(pinTypeId, x, y)
					if otherNode then
						cache.skipInRange[nodeId] = {cache = otherCache, nodeId = otherNode}
					end
				end
			end
		end
	end
	-- add cache
	self.mapCaches[cache.map] = cache
	cache.accessed = cache.accessed + 1
end

function ZoneCache:HasMapCache()
	return (next(self.mapCaches) ~= nil)
end

function ZoneCache:ForNearbyNodes(...)
	for _, mapCache in pairs(self.mapCaches) do
		mapCache:ForNearbyNodes(...)
	end
end

function ZoneCache:ForNodesInRange(...)
	for _, mapCache in pairs(self.mapCaches) do
		mapCache:ForNodesInRange(...)
	end
end

function ZoneCache:Dispose()
	for map, mapCache in pairs(self.mapCaches) do
		mapCache.accessed = mapCache.accessed - 1
		mapCache.skipInRange = {}
	end
	self.mapCaches = nil
end

function ZoneCache:DoesHandleMap(map)
	return self.mapCaches[map]
end
