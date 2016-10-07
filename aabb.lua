AABB = {}
AABB.__index = AABB

function AABB.new(minX, minY, maxX, maxY)
	local self = setmetatable({}, AABB)
	self.minX = minX
	self.minY = minY
	self.maxX = maxX
	self.maxY = maxY	

	return self
end

function AABB:extend(size)
	return AABB(self.minX - size, self.minY - size, self.maxX + size, self.maxY + size)
end

function AABB:contains(other)
	if other.minX >= self.minX and other.maxX <= self.maxX and other.minY >= self.minY and other.maxY <= self.maxY then
		return true
	end

	-- else
	return false
end

function AABB:intersect(other)
	local Tx = (self.minX + self.maxX) * 0.5 - (other.minX + other.maxX) * 0.5
	local Ty = (self.minY + self.maxY) * 0.5 - (other.minY + other.maxY) * 0.5

	local width = (self.maxX - self.minX) * 0.5 + (other.maxX - other.minX) * 0.5
	local height = (self.maxY - self.minY) * 0.5 + (other.maxY - other.minY) * 0.5

	if math.abs(Tx) < width and math.abs(Ty) < height then
		return true
	end

	return false
end

setmetatable(AABB, { __call = function(_, ...) return AABB.new(...) end })