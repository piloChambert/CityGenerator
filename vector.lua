Vector = {}
Vector.__index = Vector

function Vector.new(arg0, arg1) 
	local x = 0
	local y = 0

	if arg1 == nil then
		-- copy constructor
		x = arg0.x
		y = arg0.y
	else
		x = arg0
		y = arg1
	end

	return setmetatable({x = x or 0, y = y or 0}, Vector)
end

function Vector.__tostring(v)
	return "(" .. v.x .. ", " .. v.y ..")"
end

function Vector.__add(v1, v2)
	return Vector(v1.x + v2.x, v1.y + v2.y)
end

function Vector.__sub(v1, v2)
	return Vector(v1.x - v2.x, v1.y - v2.y)
end

function Vector.__mul(v, m)
	if type(m) == "number" then
		return Vector(v.x * m, v.y * m)
	end

	-- else cross product
	return v.x * m.y - v.y * m.x
end

function Vector.__unm(v)
	return Vector(-v.x, -v.y)
end

function Vector.__eq(v1, v2)
	return v1.x == v2.x and v1.y == v2.y
end

function Vector:dot(v)
	return self.x * v.x + self.y * v.y
end

function Vector:lenSQ()
	return self:dot(self)
end

function Vector:length()
	return math.sqrt(self:lenSQ())
end

function Vector:normalized() 
	local l = self:length()
	return Vector(self.x / l, self.y / l)
end

function Vector:rotated(angle)
	local cs = math.cos(angle)
	local sn = math.sin(angle)

	return Vector(self.x * cs - self.y * sn, self.x * sn + self.y * cs)
end

setmetatable(Vector, { __call = function(_, ...) return Vector.new(...) end })