QuadTree = {}
QuadTree.__index = QuadTree

function QuadTree.new(x, y, w, h, minCellSize)
	local self = setmetatable({}, QuadTree)

	self.aabb = AABB(x, y, x + w, y +w)

	if w > minCellSize then
		self.children = {}
		self.children[0] = QuadTree.new(x, y, w * 0.5, h * 0.5, minCellSize)
		self.children[1] = QuadTree.new(x + w * 0.5, y, w * 0.5, h * 0.5, minCellSize)
		self.children[2] = QuadTree.new(x + w * 0.5, y + h * 0.5, w * 0.5, h * 0.5, minCellSize)
		self.children[3] = QuadTree.new(x, y + h * 0.5, w * 0.5, h * 0.5, minCellSize)
	else
		self.child = nil -- just to make it clear
	end

	self.list = list()

	-- total number of item in this (sub)tree
	self.length = 0

	return self
end

-- return true if the item fits inside this cell
function QuadTree:insert(item, aabb)
	-- it's not in our aabb 
	if not self.aabb:contains(aabb) then
		return false
	end

	-- else
	local inChild = false
	if self.children ~= nil then
		for i = 0, 3 do
			inChild = inChild or self.children[i]:insert(item, aabb)
		end
	end

	-- if it doesn't in any child, store it there
	if not inChild then
		self.list:push(item)
	end

	return true
end

function QuadTree:push(item) 
	-- compute the aabb once
	local res = self:insert(item, item:aabb())

	-- if it doesn't fit any where, store it there
	-- item in this list can be outside our AABB
	-- but just in case, store them here
	if not res then
		self.list:push(item)
	end

	self.length = self.length + 1
end

function QuadTree:_remove(item, aabb)
	-- it's not in our aabb 
	if not self.aabb:contains(aabb) then
		return false
	end

	-- else
	local inChild = false
	if self.children ~= nil then
		for i = 0, 3 do
			inChild = inChild or self.children[i]:_remove(item, aabb)
		end
	end

	-- if it doesn't in any child, it should be there
	if not inChild then
		self.list:remove(item)
	end

	return true
end

function QuadTree:remove(item)
	local res = self:_remove(item, item:aabb())

	-- same as insert, the item can lie outside our aabb
	-- but can have been inserted here
	if not res then
		self.list:remove(item)
	end

	self.length = self.length - 1
end

function QuadTree:length()
	return self.length
end

function QuadTree:query(aabb, t)
	if aabb:intersect(self.aabb) then
		-- add segments
		for s in self.list:iterate() do
			table.insert(t, s)
		end

		-- now, children
		if self.children ~= nil then
			for i = 0, 3 do
				self.children[i]:query(aabb, t)
			end
		end
	end
end

setmetatable(QuadTree, { __call = function(_, ...) return QuadTree.new(...) end })