
require "PriorityQueue"
require "perlin"
require "vector"
require "list"

local cameraX = 0
local cameraY = 0
local zoom = 0.08
local showPopulationMap = false
local showDebugColor = false

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

function Segment:endPoint() 
	return self.pos + self.dir * self.length
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
	maxRoads = 1000000,

	-- highway
	highwayLength = 100,
	highwayAngleRange = 0.5 * math.pi,
	highwayLookUpStepCount = 20,
	highwayLookUpRayStepCount = 20,
	highwayLookUpRayStepLength = 20000,
	highwayConnectionDistance = 10, 
	highwayPriority = 1,

	-- streets
	streetLength = 50,
	streetPriority = 200
}

-- return the population at a point
function populationAt(x, y)
	local freq = 4096
	local n = math.pow(math.max(0, noise(x / freq + 2048, y / freq + 2048, 0)), 0.8) + 0.1

	return n
end

function intersectSegment(A, B)
	local den = A.dir * B.dir

	if math.abs(den) > 0.0 then
		-- I = A.pos + A.dir * u = B.pos + B.dir * v
		local diff = B.pos - A.pos

		local u = (diff * B.dir) / den
		local v = (diff * A.dir) / den

		-- intersection
		return true, u, v
	end

	return false, nil, nil
end

function localConstraints(road)
	local segment = road.segment

	if road.attr.highway then
		segment.width = 10.0
		segment.color = {r = 255, g = 255, b = 255}
		segment.debugColor = {r = 255, g = 255, b = 255}
	else
		segment.width = 5.0
		segment.color = {r = 64, g = 64, b = 64}		
		segment.debugColor = {r = 255, g = 255, b = 255}
	end

	-- PRUNNING
	-- discard segment if there's one to close with the same orientation
	for other in segments:iterate() do
		if math.abs(other.dir:dot(segment.dir)) > 0.9 then
			local d0 = math.max((segment.pos - other.pos):length(), (segment.pos - other:endPoint()):length())
			local d1 = math.max((segment:endPoint() - other.pos):length(), (segment:endPoint() - other:endPoint()):length())			

			if math.max(d0, d1) < segment.length then
				return false
			end
		end
	end


	-- RULE 1
	-- itersection with other segment
	local closestIntersectionDistance = road.segment.length
	local closestSegment = nil
	for other in segments:iterate() do
		local intersect, u, v = intersectSegment(segment, other)

		-- intersection
		if intersect and u > 0.0001 and v > 0.0001 and u < segment.length and v < other.length then
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
		s0.color = closestSegment.color
		s0.debugColor = {r = 0, g = 255, b = 0}
		s0.width = closestSegment.width

		local s1 = Segment(I, (E - I):normalized(), (E - I):length())
		s1.color = closestSegment.color
		s1.debugColor = {r = 0, g = 255, b = 0}
		s1.width = closestSegment.width

		-- remove splitte edge
		segments:remove(closestSegment)
		segments:push(s0)
		segments:push(s1)


		-- correct this road segment
		segment.length = closestIntersectionDistance
		segment.debugColor = {r = 0, g = 0, b = 255}

		-- doesn't expand the road
		road.attr.done = true

		return true
	end

	-- RULE 2 
	-- else check closest existing intersection
	local P = segment:endPoint() 
	closestIntersectionDistance = roadsParameters.highwayConnectionDistance
	local closestIntersection = nil
	for other in segments:iterate() do
		if (P - other.pos):length() < closestIntersectionDistance then
			closestIntersectionDistance = (P - other.pos):length()
			closestIntersection = other.pos
		end

		if (P - other:endPoint()):length() < closestIntersectionDistance then
			closestIntersectionDistance = (P - other:endPoint()):length()
			closestIntersection = other:endPoint()
		end
	end

	if closestIntersection ~= nil then
		local V = closestIntersection - segment.pos
		segment.dir = V:normalized()
		segment.length = V:length()
		segment.debugColor = {r = 255, g = 255, b = 0}

		-- doesn't expand the road
		road.attr.done = true

		return true
	end

	-- RULE 3
	-- check distance to the closest segment
	closestIntersectionDistance = 100--roadsParameters.highwayConnectionDistance
	closestSegment = nil
	for other in segments:iterate() do
		local intersect, u, v = intersectSegment(segment, other)

		-- intersection
		if intersect and u > 0.0001 and v > 0.0001 and v < other.length then
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
		local E = closestSegment:endPoint() -- end of splited segment

		local s0 = Segment(closestSegment.pos, (I - closestSegment.pos):normalized(), (I - closestSegment.pos):length())
		s0.debugColor = {r = 0, g = 255, b = 255}
		s0.color = closestSegment.color
		s0.width = closestSegment.width

		local s1 = Segment(I, (E - I):normalized(), (E - I):length())
		s1.debugColor = {r = 0, g = 255, b = 255}
		s1.color = closestSegment.color
		s1.width = closestSegment.width

		-- remove splitte edge
		segments:remove(closestSegment)
		segments:push(s0)
		segments:push(s1)


		-- correct this road segment
		segment.length = closestIntersectionDistance
		segment.debugColor = {r = 255, g = 0, b = 255}

		-- doesn't expand the road
		road.attr.done = true

		return true
	end

	-- don't extend segments outside area
	local E = segment:endPoint()
	if math.abs(E.x) > 4096 or math.abs(E.y) > 4096 then
		road.attr.done = true
	end

	return true
end

-- this compute the weighted population over a segment
function populationInDirection(position, direction, length)
	local sum = 0

	for s = 1, roadsParameters.highwayLookUpRayStepCount do
		local dist = length * s / roadsParameters.highwayLookUpRayStepCount
		local p = position + direction * dist
		local pop = populationAt(p.x, p.y)
		sum = sum + pop / dist
	end

	return sum
end

function bestDirection(position, direction, angleRange)
	local bestAngle = -angleRange
	local bestSum = 0
	local angle = -angleRange

	for i = 1, roadsParameters.highwayLookUpStepCount do 
		-- sample population along the ray
		local newDir = direction:rotated(angle)
		local sum = populationInDirection(position, newDir, roadsParameters.highwayLookUpRayStepLength)
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
	local newPosition = segment:endPoint()
	local dir = segment.dir
	local currentPop = populationAt(newPosition.x, newPosition.y)

	-- don't expand the road :)
	if attr.done then
		return
	end

	if attr.highway then
		-- split?
		local split = 1500
		local leftSplit = attr.leftSplit - roadsParameters.highwayLength
		local rightSplit = attr.rightSplit - roadsParameters.highwayLength

		if attr.leftSplit < 0 and love.math.random() < 0.1 then
			queue:push(Road(Segment(newPosition, dir:rotated(math.pi * 0.5), roadsParameters.highwayLength), {highway = true, leftSplit = split, rightSplit = split}), t + roadsParameters.highwayPriority)
			leftSplit = split		
		end

		if attr.rightSplit < 0 and love.math.random() < 0.1 then
			queue:push(Road(Segment(newPosition, dir:rotated(math.pi * -0.5), roadsParameters.highwayLength), {highway = true, leftSplit = split, rightSplit = split}), t + roadsParameters.highwayPriority)
			rightSplit = split
		end

		-- look for next population
		local bestAngle = math.max(-roadsParameters.highwayAngleRange, math.min(roadsParameters.highwayAngleRange, bestDirection(newPosition, dir, math.pi * 0.1)))

		-- push the best angle
		queue:push(Road(Segment(newPosition, dir:rotated(bestAngle), roadsParameters.highwayLength), {highway = true, leftSplit = leftSplit, rightSplit = rightSplit }), t+roadsParameters.highwayPriority)
	elseif currentPop > 0.0 then
		-- keep forward
		queue:push(Road(Segment(newPosition, dir, roadsParameters.streetLength), {}), t+roadsParameters.streetPriority)
	end

	-- street branching
	if currentPop > 0.0 then
		if math.random() < 0.1 then
			queue:push(Road(Segment(newPosition, dir:rotated(math.pi * -0.5), roadsParameters.streetLength), {}), t+roadsParameters.streetPriority + 2)
		end

		if math.random() < 0.1 then
			queue:push(Road(Segment(newPosition, dir:rotated(math.pi * 0.5), roadsParameters.streetLength), {}), t+roadsParameters.streetPriority + 2)
		end
	end
end

function step()
	if #queue > 0 and segments.length < roadsParameters.maxRoads then
		local road, t = queue:pop()
		local accepted = localConstraints(road)

		if accepted then
			segments:push(road.segment)

			-- add global goals
			globalGoals(queue, t + 1, road)
		end
	end
end

function love.load()
	-- setup screen
	love.window.setMode(1280, 720)

	segments = list()
	queue = PriorityQueue.new()

	local startAngle = bestDirection(Vector(0, 0), Vector(1, 0), math.pi)
	queue:push(Road(Segment(Vector(0, 0), Vector(1, 0):rotated(startAngle), roadsParameters.highwayLength), {highway = true, leftSplit = 500, rightSplit = 500}) , 0)
	queue:push(Road(Segment(Vector(0, 0), Vector(-1, 0):rotated(startAngle), roadsParameters.highwayLength), {highway = true, leftSplit = 500, rightSplit = 500}) , 0)

--[[
	while #queue > 0 and segments.length < roadsParameters.maxRoads do
		local road, t = queue:pop()
		local accepted = localConstraints(road)

		if accepted then
			segments:push(road.segment)

			-- add global goals
			globalGoals(queue, t + 1, road)
		end
	end
	]]
end

function love.update(dt)
	-- quit
	if love.keyboard.isDown("escape") then
		love.event.quit()
	end

	for i = 1, 10 do
		step()
	end
end

function love.mousemoved(x, y, dx, dy, istouch)
	if love.mouse.isDown("l") then
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

function love.keypressed(key)
	if key == "p" then
		showPopulationMap = not showPopulationMap
	end

	if key == "c" then
		showDebugColor = not showDebugColor
	end
end

function love.wheelmoved(x, y)
	zoom = math.max(0.1, math.min(10, zoom + y))
	print(y)
end

function love.draw()
	--drawMap()

	local w, h = love.window.getDimensions()
	local cx = w * 0.5 - cameraX * zoom
	local cy = h * 0.5 - cameraY * zoom

	-- draw population map
	if showPopulationMap then
		for y = 0, math.ceil(h / 16) do
			for x = 0, math.ceil(w / 16) do
				local n = populationAt((x * 16 - cx) / zoom, (y * 16 - cy) / zoom)
				love.graphics.setColor(n * 255, n * 255 * 0.2, n * 255 * 0.2, 255)
				love.graphics.rectangle("fill", x * 16 - 8, y * 16 - 8, 16, 16)
			end
		end
	end

	love.graphics.push()
	love.graphics.translate(cx, cy)
	love.graphics.scale(zoom, zoom)
	for seg in segments:iterate() do
		if showDebugColor then
			love.graphics.setColor(seg.debugColor.r, seg.debugColor.g, seg.debugColor.b, 255)
		else
			love.graphics.setColor(seg.color.r, seg.color.g, seg.color.b, 255)
		end
		love.graphics.setLineWidth(seg.width * zoom)
		love.graphics.line(seg.pos.x, seg.pos.y, seg.pos.x + seg.dir.x * seg.length, seg.pos.y + seg.dir.y * seg.length)
	end
	
	love.graphics.pop()

	love.graphics.setColor(255, 255, 255, 255)
	love.graphics.print("Segments: " .. segments.length, 10, 10)
	love.graphics.print("Queue size: " .. #queue, 10, 25)

	love.graphics.print("'p' to show population", 10, h-40)
	love.graphics.print("'c' to toggle debug color ", 10, h-25)

end