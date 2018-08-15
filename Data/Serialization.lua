
if not Harvest.Data then
	Harvest.Data = {}
end

local Harvest = _G["Harvest"]
local Data = Harvest.Data

local tonumber = _G["tonumber"]
local assert = _G["assert"]
local gmatch = string.gmatch
local tostring = _G["tostring"]
local insert = table.insert
local format = string.format
local concat = table.concat

-- constants/enums for the node encoding format
Data.LOCAL_X = "1"
Data.LOCAL_Y = "2"
Data.WORLD_Z = "3"
Data.ITEMS = "4"
Data.TIME = "5"
Data.VERSION = "6"
Data.GLOBAL_X = "7"
Data.GLOBAL_Y = "8"

local function GetNumberValue(getNextChunk)
	local number
	local typ, data = getNextChunk()
	if typ == "^N" then
		number = tonumber(data)
	elseif typ == "^F" then
		local typ2, data2 = getNextChunk()
		assert(typ2 == "^f")
		local mantissa = tonumber(data)
		local exponent = tonumber(data2)
		number = mantissa * (2^exponent)
	end
	return number
end

local function Deserialize(serializedData, pinTypeId)
	local x, y, z, globalX, globalY, timestamp, version, flags
	
	local getNextChunk = gmatch(serializedData, "(-?%d*%.?%d*),?")
	
	x = tonumber(getNextChunk()) or 0
	y = tonumber(getNextChunk()) or 0
	z = tonumber(getNextChunk()) or 0
	timestamp = tonumber(getNextChunk()) or 0
	version = tonumber(getNextChunk()) or 0
	globalX = tonumber(getNextChunk()) or 0
	globalY = tonumber(getNextChunk()) or 0
	flags = tonumber(getNextChunk()) or 0
	
	if (x == 0) then return false, "invalid x " .. serializedData end
	if (y == 0) then return false, "invalid y " .. serializedData end
	--if (z == 0) then return false, "invalid z " .. serializedData end
	if z == 0 then z = nil end
	--if (timestamp == 0) then return false, "invalid time " .. serializedData end
	--if (version == 0) then return false, "invalid version " .. serializedData end
	--if timestamp > 1512767392 then -- new nodes require global coords
	--	if (globalX == 0) then return false, "invalid globalx " .. serializedData end
	--	if (globalZ == 0) then return false, "invalid globaly " .. serializedData end
	--end
	if globalX == 0 then globalX = nil end
	if globalY == 0 then globalY = nil end
	
	return true, x, y, z, timestamp, version, globalX, globalY, flags
end

function Data:Deserialize(serializedData, pinTypeId)
	return Deserialize(serializedData, pinTypeId)
end

function Data:Serialize(x, y, z, timestamp, version, globalX, globalY, flags)
	local parts = {}
	insert(parts, format("%.4f", x or 0))
	insert(parts, format("%.4f", y or 0))
	insert(parts, format("%.1f", z or 0))
	
	insert(parts, tostring(timestamp or 0))
	insert(parts, tostring(version or 0))
	
	insert(parts, format("%.7f", globalX or 0))
	insert(parts, format("%.7f", globalY or 0))
	
	insert(parts, tostring(flags or 0))
	
	return concat(parts, ",")
end
