local parentAddOnName = ...

local callbackMixin = LibContainer.mixins.callback
local eventMixin = LibContainer.mixins.event
local bagSlots = LibContainer.constants.bagSlots

local parentMixin = {}
--[[ Parent:GetCategories()
Returns a (filtered) table of all categories.  
The table is indexed by the category index and valued with the Category data table.

Any categories that has been ignored on the Parent will not be included.
--]]
function parentMixin:GetCategories()
	local categories = CopyTable(LibContainer:GetCategories())
	for key in next, self.categoriesIgnored do
		categories[key] = nil
	end

	return categories
end

local function ADDON_LOADED(self, name)
	if(name ~= parentAddOnName) then
		return
	end

	self:CreateContainers()

	self:UnregisterEvent('ADDON_LOADED')
end

local function BAG_UPDATE(self, bagID)
	if(not self:GetBag(bagID)) then
		if(not bagSlots[self.containerType][bagID]) then
			-- bag doesn't belong to this container type
			return
		end

		-- create the bag if it doesn't exist
		self:CreateBag(bagID)
	end

	if(not self:GetBag(BACKPACK_CONTAINER)) then
		-- BAG_UPDATE doesn't ever fire for container 0 on load, trigger it manually
		self:TriggerEvent('BAG_UPDATE', BACKPACK_CONTAINER)
	end

	-- running updates on every BAG_UPDATE has severe performance issues, especially
	-- when this event occurs multiple times in quick succession.
	-- we cache the bags that were updated (dirty) and let them update once the
	-- barrage of events are over
	self.dirtyBags[bagID] = true
end

local function BAG_UPDATE_DELAYED(self)
	-- this event always fires after BAG_UPDATE(s) are done, a perfect time to
	-- perform updates on "dirty" bags
	for bagID in next, self.dirtyBags do
		self:GetBag(bagID):UpdateSlots()
	end

	-- we'll only update containers once all the slots are done updating.
	-- this is because we mark slots as "dirty" in the same fashion as with bags to
	-- avoid unneccessary updates to containers
	self:UpdateContainers()

	table.wipe(self.dirtyBags)
end

local function ITEM_LOCK_CHANGED(self, bagID, slotIndex)
	local Bag = self:GetBag(bagID)
	if(Bag) then
		if(slotIndex) then
			Bag:GetSlot(slotIndex):UpdateLock()
		end
	end
end

local function BAG_UPDATE_COOLDOWN(self)
	if(self:IsVisible()) then -- try to avoid useless updates
		for bagID, Bag in next, self:GetBags() do
			Bag:UpdateCooldowns()
		end
	end
end

local function QUEST_ACCEPTED(self)
	for bagID, Bag in next, self:GetBags() do
		Bag:UpdateSlots()
	end
end

local function UNIT_QUEST_LOG_CHANGED(self, unit)
	if(unit == 'player') then
		self:TriggerEvent('QUEST_ACCEPTED')
	end
end

local parents = {}
--[[ LibContainer:New(containerType[, name][, parent])
Creates and returns a new Parent.

* containerType - type of Parent to represent (string, 'bags'|'bank')
* name          - name of the Parent (string, optional, default = parent AddOn name + containerType)
* parent        - parent for the Parent frame (frame|string, optional, default = UIParent)
--]]
function LibContainer:New(containerType, name, parent)
	assert(type(containerType) == 'string', 'New: containerType must be a string.')
	containerType = containerType:lower()
	assert(containerType == 'bags' or containerType == 'bank', 'New: containerType must be either \'bags\' or \'bank\'.')
	assert(not parents[containerType], 'New: only one container of the same type may exist.')

	if(name) then
		assert(type(name) == 'string', 'New: name must be a string if used.')
		assert(not _G[name], 'New: object with name already exists.')
	else
		name = string.format('%s_%s', parentAddOnName, containerType:gsub('^%l', string.upper))
	end

	if(parent) then
		if(type(parent) == 'string') then
			assert(_G[parent], 'New: parent must exist if used.')
		else
			assert(type(parent) == 'table', 'New: parent must be a frame if used.')
		end
	else
		parent = UIParent
	end

	local Parent = Mixin(CreateFrame('Frame', name, parent), parentMixin, callbackMixin, eventMixin)
	Parent:SetSize(1, 1) -- needs a size for child frames to even show up
	Parent:RegisterEvent('ADDON_LOADED', ADDON_LOADED)
	Parent:RegisterEvent('BAG_UPDATE', BAG_UPDATE)
	Parent:RegisterEvent('BAG_UPDATE_DELAYED', BAG_UPDATE_DELAYED)
	Parent:RegisterEvent('ITEM_LOCK_CHANGED', ITEM_LOCK_CHANGED)
	Parent:RegisterEvent('BAG_UPDATE_COOLDOWN', BAG_UPDATE_COOLDOWN)
	Parent:RegisterEvent('QUEST_ACCEPTED', QUEST_ACCEPTED)
	Parent:RegisterEvent('UNIT_QUEST_LOG_CHANGED', UNIT_QUEST_LOG_CHANGED)

	if(containerType == 'bank') then
		Parent:RegisterEvent('PLAYERBANKSLOTS_CHANGED', PLAYERBANKSLOTS_CHANGED)
		Parent:RegisterEvent('PLAYERBANKBAGSLOTS_CHANGED', PLAYERBANKBAGSLOTS_CHANGED)
		Parent:RegisterEvent('PLAYERREAGENTBANKSLOTS_CHANGED', PLAYERREAGENTBANKSLOTS_CHANGED)
		Parent:RegisterEvent('REAGENTBANK_PURCHASED', REAGENTBANK_PURCHASED)
		Parent:RegisterEvent('BANKFRAME_OPENED', BANKFRAME_OPENED)
		Parent:RegisterEvent('BANKFRAME_CLOSED', BANKFRAME_CLOSED)
	end

	Parent.containerType = containerType
	Parent.categoriesIgnored = {}
	Parent.dirtyBags = {}

	parents[containerType] = Parent
	return Parent
end

LibContainer.mixins.parent = parentMixin