
if not Harvest.Data then
	Harvest.Data = {}
end

-- This file handles updates of the serialized data. eg when something changes in the saveFile structure.
-- for instance after the DB update all itemIds for enchanting runes were removed.

local Harvest = _G["Harvest"]
local Data = Harvest.Data

-- updating the data can take quite some time
-- to prevent the game from freezing, we break each update process down into smaller parts
-- the smaller parts are executed with a small delay (see Harvest.OnUpdate(time) )
-- updating data as well as other heavy tasks such as importing data are added to the following queue
Harvest.updateQueue = {}
Harvest.updateQueue.first = 1
Harvest.updateQueue.afterLast = 1
function Harvest.IsUpdateQueueEmpty()
	return (Harvest.updateQueue.first == Harvest.updateQueue.afterLast)
end
-- adds a function to the back of the queue
function Harvest.AddToUpdateQueue(fun)
	assert(fun)
	if Harvest.IsUpdateQueueEmpty() then
		EVENT_MANAGER:UnregisterForUpdate("HarvestMap-Update")
		EVENT_MANAGER:RegisterForUpdate("HarvestMap-Update", 200, Harvest.UpdateUpdateQueue)
	end
	Harvest.updateQueue[Harvest.updateQueue.afterLast] = fun
	Harvest.updateQueue.afterLast = Harvest.updateQueue.afterLast + 1
end

function Harvest.AddToUpdateQueueIfNotOnTop(fun)
	if Harvest.updateQueue[Harvest.updateQueue.afterLast-1] == fun then return end
	Harvest.AddToUpdateQueue(fun)
end
-- adds a funciton to the front of the queue
function Harvest.AddToFrontOfUpdateQueue(fun)
	assert(fun)
	if Harvest.IsUpdateQueueEmpty() then
		EVENT_MANAGER:UnregisterForUpdate("HarvestMap-Update")
		EVENT_MANAGER:RegisterForUpdate("HarvestMap-Update", 200, Harvest.UpdateUpdateQueue)
	end
	Harvest.updateQueue.first = Harvest.updateQueue.first - 1
	Harvest.updateQueue[Harvest.updateQueue.first] = fun
end
-- executes the first function in the queue, if the player is activated yet
do
	local IsPlayerActivated = _G["IsPlayerActivated"]

	function Harvest.UpdateUpdateQueue() --shitty function name is shitty
		if not IsPlayerActivated() then return end
		
		local start = GetGameTimeMilliseconds()
		
		while GetGameTimeMilliseconds() - start < 1000 / 60 do
			local fun = Harvest.updateQueue[Harvest.updateQueue.first]
			Harvest.updateQueue[Harvest.updateQueue.first] = nil
			Harvest.updateQueue.first = Harvest.updateQueue.first + 1
			
			local success, errorString = pcall(fun)
			if not success then
				ZO_ERROR_FRAME:OnUIError(errorString)
				Harvest.updateQueue = {first = 1, afterLast = 1}
				EVENT_MANAGER:UnregisterForUpdate("HarvestMap-Update")
				return
			end

			if Harvest.IsUpdateQueueEmpty() then
				Harvest.updateQueue.first = 1
				Harvest.updateQueue.afterLast = 1
				Harvest.RedrawPins()
				EVENT_MANAGER:UnregisterForUpdate("HarvestMap-Update")
				return
			end
		end
	end
end

function Harvest.GetQueuePercent()
	return zo_floor((Harvest.updateQueue.first/Harvest.updateQueue.afterLast)*100)
end

------------------------
--#################################################
------------------------

local function ClearOldData()
	-- remove all data from before the save file refactoring
	local saveFile, accountWide
	for subModuleName, subModule in pairs(Data.subModules) do
		saveFile = _G[subModuleName.savedVarsName]
		if saveFile then
			if saveFile["Default"] then
				saveFile["Default"] = nil
			end
		end
	end
end

local function FixNF()
	if not HarvestNF_SavedVars then return end
	
	for map, mapData in pairs(HarvestNF_SavedVars.data) do
		local newFile = Data:GetSaveFile(map)
		if newFile.savedVars ~= HarvestNF_SavedVars then
			Data:ImportFromMap( map, mapData, newFile )
			HarvestNF_SavedVars.data[map] = nil
		end
	end
end

-- check if saved data is from an older version,
-- update the data if needed
function Data:UpdateDataVersion( saveFile )
	assert(not saveFile) -- in case someone is still using the import/export tool
	-- remove very old data
	ClearOldData()
	-- move nodes from NF to correct file
	-- this happen when there is for instance a new zone and HM isn't updated in time
	-- one example would be summerset, which was saved in NF for a long time
	FixNF()
	-- set file version flag
	for subModuleName, subModule in pairs(Data.subModules) do
		subModule.savedVars.dataVersion = Harvest.dataVersion
	end
end

