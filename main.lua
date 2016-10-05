
require "PriorityQueue"
require "perlin"
require "vector"
require "list"

local cameraX = 0
local cameraY = 0
local zoom = 1

-- segments
Segment = {}
Segment.__index = Segment

function Segment.new(pos, dir, len)
	local self = setmetatable({}, Segment)

	self.pos = Vector(pos.x, pos.y)

	self.dir = dir:normalized() -- who knows, it can be a non normalized vector
	self.length = len

	self.width = 1
	self.color = {r = 255, g = 255, b = 255}

	return self
end

setmetatable(Segment, { __call = function(_, ...) return Segment.new(...) end })

Road = {}
Road.__index = Road

function Road.new(seg, attr)
	local self = setmetatable({}, Road)

	self.segment = seg
	self.attr = attr

	return self
end

setmetatable(Road, { __call = function(_, ...) return Road.new(...) end })


-- configuration
roadsParameters = {
	maxRoads = 1000,

	-- highway
	highwayLength = 150,
	highwayAngleRange = 0.01 * math.pi,
	highwayLookUpStepCount = 20,
	highwayLookUpRayStepCount = 20,
	highwayLookUpRayStepLength = 20000,
	highwayConnectionDistance = 40, 

	-- streets
	streetLength = 150
}

-- return the population at a point
function populationAt(x, y)
	local freq = 4096
	local n = math.pow(math.max(0, noise(x / freq + 2048, y / freq + 2048, 0)), 0.8)

	return n
end

function intersectSegment(A, B)
	local den = A.dir * B.dir

	if math.abs(den) > 0.0 then
		-- I = A.pos + B.dir * u = B.pos + B.dir * v
		local diff = B.pos - A.pos

		local u = (diff * B.dir) / den
		local v = (diff * A.dir) / den

		-- intersection
		if u > 0.00001 and u < A.length and v > 0.0001 and v < B.length then
			return true, u, v
		end
	end

	return false, nil, nil
end

function localConstraints(road)
	local segment = road.segment

	if road.attr.highway then
		segment.width = 8.0
	end

	-- PRUNNING
	-- if there's a segment connected and almost the same direction
	-- don't geneate a road
	for other in segments:iterate() do
		if (segment.pos - other.pos):length() < 20.0 and math.abs(segment.dir:dot(other.dir)) > 0.6 then
			return false
		end
	end

	-- RULE 1
	-- itersection with other segment
	local closestIntersectionDistance = road.segment.length
	local closestSegment = nil
	for other in segments:iterate() do
		local intersect, u, v = intersectSegment(segment, other)

		-- intersection
		if intersect then
			if u < closestIntersectionDistance then
				closestIntersectionDistance = u
				closestSegment = other
			end
		end
	end

	if closestSegment ~= nil then
		-- create an itersection here
		-- split road
		local I = segment.pos + segment.dir * closestIntersectionDistance
		local E = closestSegment.pos + closestSegment.dir * closestSegment.length -- end of splited segment

		local s0 = Segment(closestSegment.pos, (I - closestSegment.pos):normalized(), (I - closestSegment.pos):length())
		s0.color = {r = 0, g = 255, b = 0}
		s0.width = closestSegment.width

		local s1 = Segment(I, (E - I):normalized(), (E - I):length())
		s1.color = {r = 0, g = 255, b = 0}
		s1.width = closestSegment.width

		segments:remove(closestSegment)
		segments:push(s0)
		segments:push(s1)


		-- correct this road segment
		segment.length = closestIntersectionDistance
		segment.color = {r = 0, g = 0, b = 255}

		return true
	end

	-- RULE 2 
	-- else check closest existing intersection
	local P = segment.pos + segment.dir * segment.length
	closestIntersectionDistance = roadsParameters.highwayConnectionDistance
	local closestIntersection = nil
	for other in segments:iterate() do
		if (P - other.pos):length() < closestIntersectionDistance then
			closestIntersectionDistance = (P - other.pos):length()
			closestIntersection = other.pos
		elseif (P - (other.pos + other.dir * other.length)):length() < closestIntersectionDistance then
			closestIntersectionDistance = (P - (other.pos + other.dir * other.length)):length()
			closestIntersection = other.pos + other.dir * other.length
		end
	end

	if closestIntersection ~= nil then
		local V = closestIntersection - segment.pos
		segment.dir = V:normalized()
		segment.length = V:length()
		segment.color = {r = 255, g = 255, b = 0}
	end

	-- RULE 3

	-- color
	if road.attr.highway then
		segment.color = {r = 255, g = 255, b = 255}
	else
		segment.color = {r = 127, g = 127, b = 127}		
	end

	return true
end

function bestDirection(position, direction, angleRange)
	local bestAngle = -angleRange
	local bestSum = 0
	local angle = -angleRange

	for i = 1, roadsParameters.highwayLookUpStepCount do 
		local newDir = direction:rotated(angle)

		-- sample population along the ray
		local sum = 0
		for s = 1, roadsParameters.highwayLookUpRayStepCount do
			local dist = roadsParameters.highwayLookUpRayStepLength * s / roadsParameters.highwayLookUpRayStepCount
			local p = position + newDir * dist
			local pop = populationAt(p.x, p.y)
			sum = sum + pop / dist
		end

		if sum > bestSum then
			bestSum = sum
			bestAngle = angle
		end

		angle = angle + (angleRange * 2) / roadsParameters.highwayLookUpStepCount
	end

	return bestAngle
end

function globalGoals(queue, t, road)
	local segment = road.segment
	local attr = road.attr
	local newPosition = segment.pos + segment.dir * segment.length
	local dir = segment.dir
	local currentPop = populationAt(newPosition.x, newPosition.y)

	if attr.highway then
		-- split?
		local leftSplit = attr.leftSplit - roadsParameters.highwayLength
		local rightSplit = attr.rightSplit - roadsParameters.highwayLength

		if attr.leftSplit < 0 and love.math.random() < 0.1 then
			queue:push(Road(Segment(newPosition, dir:rotated(math.pi * 0.5), roadsParameters.highwayLength), {highway = true, leftSplit = 2000, rightSplit = 2000}), t + 20)
			leftSplit = 2000		
		end

		if attr.rightSplit < 0 and love.math.random() < 0.1 then
			queue:push(Road(Segment(newPosition, dir:rotated(math.pi * -0.5), roadsParameters.highwayLength), {highway = true, leftSplit = 2000, rightSplit = 2000}), t + 20)
			rightSplit = 2000
		end

		-- look for next population
		local bestAngle = math.max(-roadsParameters.highwayAngleRange, math.min(roadsParameters.highwayAngleRange, bestDirection(newPosition, dir, math.pi * 0.1)))

		-- push the best angle
		queue:push(Road(Segment(newPosition, dir:rotated(bestAngle), roadsParameters.highwayLength), {highway = true, leftSplit = leftSplit, rightSplit = rightSplit }), t+20)

		if currentPop > 0.0 then
			-- generate streets
			queue:push(Road(Segment(newPosition, dir:rotated(math.pi * 0.5), roadsParameters.streetLength), {}), t + 60)		
			queue:push(Road(Segment(newPosition, dir:rotated(math.pi * -0.5), roadsParameters.streetLength), {}), t + 60)					
		end
	else
		if currentPop > 0.0 then
			-- keep going forward
			queue:push(Road(Segment(newPosition, dir, roadsParameters.streetLength), {}), t + 60)
		end

		-- 90° intersection
		queue:push(Road(Segment(newPosition, dir:rotated(math.pi * 0.5), roadsParameters.streetLength * 0.5), {}), t + 60)		
		queue:push(Road(Segment(newPosition, dir:rotated(math.pi * -0.5), roadsParameters.streetLength * 0.5), {}), t + 60)		
	end
	


end

function love.load()
	-- setup screen
	love.window.setMode(1280, 720)

	segments = list()
	local queue = PriorityQueue.new()

	local startAngle = bestDirection(Vector(0, 0), Vector(1, 0), math.pi)
	queue:push(Road(Segment(Vector(0, 0), Vector(1, 0):rotated(startAngle), roadsParameters.highwayLength), {highway = true, leftSplit = 500, rightSplit = 500}) , 0)

	while #queue > 0 and segments.length < roadsParameters.maxRoads do
		local road, t = queue:pop()
		local accepted = localConstraints(road)

		if accepted then
			segments:push(road.segment)

			-- add global goals
			globalGoals(queue, t + 1, road)
		end
	end
end

function love.update(dt)
	-- quit
	if love.keyboard.isDown("escape") then
		love.event.quit()
	end
end

function love.mousemoved(x, y, dx, dy, istouch)
	if love.mouse.isDown("r") then
		cameraX = cameraX - dx / zoom
		cameraY = cameraY - dy / zoom
	end
end

function love.mousepressed( x, y, button, istouch )
	if button == "wu" then
		zoom = zoom * 1.1
	elseif button == "wd" then
		zoom = zoom * 0.9	
	end
end

function love.wheelmoved(x, y)
	zoom = math.max(0.1, math.min(10, zoom + y))
	print(y)
end

function love.draw()
	--drawMap()

	local w, h = love.window.getDimensions()
	for y = 0, math.ceil(h / 16) do
		for x = 0, math.ceil(w / 16) do
			local n = populationAt(x * 16 / zoom + cameraX, y * 16 / zoom + cameraY)
			love.graphics.setColor(n * 255, n * 255 * 0.2, n * 255 * 0.2, 255)
			love.graphics.rectangle("fill", x * 16 - 8, y * 16 - 8, 16, 16)
		end
	end

	love.graphics.push()
	love.graphics.translate(-cameraX * zoom, -cameraY * zoom)
	love.graphics.scale(zoom, zoom)
	for seg in segments:iterate() do
		love.graphics.setColor(seg.color.r, seg.color.g, seg.color.b, 255)
		love.graphics.setLineWidth(seg.width)
		love.graphics.line(seg.pos.x, seg.pos.y, seg.pos.x + seg.dir.x * seg.length, seg.pos.y + seg.dir.y * seg.length)
	end
	
	love.graphics.pop()
end