QuadTree = {}
QuadTree.__index = QuadTree

function QuadTree.new(x, y, w, h, minSize)
	self = setmetatable({}, QuadTree)

	if w > minSize then
		self.child = {}
		self.child[0] = QuadTree.new(x, y, w * 0.5, h * 0.5)
		self.child[1] = QuadTree.new(x, y, w * 0.5, h * 0.5)
		self.child[2] = QuadTree.new(x, y, w * 0.5, h * 0.5)
		self.child[3] = QuadTree.new(x, y, w * 0.5, h * 0.5)
	end

	return self
end

function QuadTree:addItem(item) 
	-- does it fit inside childs?
	
end

setmetatable(QuadTree, { __call = function(_, ...) return QuadTree.new(...) end })