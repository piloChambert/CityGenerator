
require "PriorityQueue"
require "perlin"
require "vector"
require "list"
require "aabb"
require "QuadTree"

local cameraX = 0
local cameraY = 0
local zoom = 0.08
local showPopulationMap = false
local showDebugColor = false

-- Node 
Node = {}
Node.__index = Node

function Node.new(position)
	local self = setmetatable({}, Node)
	self.position = position

	self.segments = {}

	return self
end

function Node:aabb()
	return AABB(self.position.x, self.position.y, self.position.x, self.position.y)
end

function Node:addSegment(segment)
	table.insert(self.segments, segment)
end

function Node:removeSegment(segment)
	local segIdx = -1
	for i, v in ipairs(self.segments) do
		if v == segment then
			segIdx = i
			break
		end
	end

	table.remove(self.segments, segIdx)
end

setmetatable(Node, { __call = function(_, ...) return Node.new(...) end })

-- segments
Segment = {}
Segment.__index = Segment

function Segment.new(startNode, endNode)
	local self = setmetatable({}, Segment)

	self.startNode = startNode
	self.endNode = endNode

	self.width = 1
	self.color = {r = 255, g = 255, b = 255}

	return self
end

function Segment:dir()
	return (self.endNode.position - self.startNode.position):normalized()
end

function Segment:length()
	return (self.endNode.position - self.startNode.position):length()
end

function Segment:startPoint()
	return self.startNode.position
end

function Segment:endPoint() 
	return self.endNode.position
end

function Segment:aabb() 
	local minX = math.min(self.startNode.position.x, self.endNode.position.x)
	local maxX = math.max(self.startNode.position.x, self.endNode.position.x)
	local minY = math.min(self.startNode.position.y, self.endNode.position.y)
	local maxY = math.max(self.startNode.position.y, self.endNode.position.y)

	return AABB(minX, minY, maxX, maxY)
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

mapSize = 4096

-- configuration
roadsParameters = {
	-- highway
	highwayLength = 100,
	highwayAngleRange = 0.5 * math.pi,
	highwayLookUpStepCount = 20,
	highwayLookUpRayStepCount = 20,
	highwayLookUpRayStepLength = 2000,
	highwayConnectionDistance = 20, 
	highwayPriority = 1,
	highwayBranchProbability = 0.05,

	streetExtensionRatio = 0.8,

	-- streets
	streetLength = 50,
	streetPriority = 200,
	streetBranchProbability = 0.08
}

-- return the population at a point
populationImage = love.graphics.newImage("population.png")
function populationAt(x, y)
	--[[
	local freq = 4096
	local n = math.pow(math.max(0, noise(x / freq + 2048, y / freq + 2048, 0)), 0.8)

	return n
	]]

	local w, h = populationImage:getDimensions()
	local _x = (x + mapSize) / (2 * mapSize) * w
	local _y = (y + mapSize) / (2 * mapSize) * h

	if _x < 0 or _y < 0 or _x > w or _y > h then
		return 0
	end

	local r, g, b, a = populationImage:getData():getPixel(_x, _y)

	return r / 255.0
end

-- check intersection between 2 segments
function intersectSegment(A, B)
	local Adir = A:dir()
	local Bdir = B:dir()
	local den = Adir * Bdir

	if math.abs(den) > 0.0 then
		-- I = A.pos + A.dir * u = B.pos + B.dir * v
		local diff = B:startPoint() - A:startPoint()

		local u = (diff * Bdir) / den
		local v = (diff * Adir) / den

		-- intersection
		return true, u, v
	end

	return false, nil, nil
end

-- The local constraints function
-- It prunes some segments (need work on that)
-- And check for intersection with existing road segments
function localConstraints(road)
	local segment = road.segment

	-- rendering parameter
	if road.attr.highway then
		segment.width = 10.0
		segment.color = {r = 255, g = 255, b = 255}
		segment.debugColor = {r = 255, g = 255, b = 255}
	else
		segment.width = 5.0
		segment.color = {r = 64, g = 64, b = 64}		
		segment.debugColor = {r = 255, g = 255, b = 255}
	end

	local listOfConcernSegments = {}
	quadTree:query(segment:aabb():extend(roadsParameters.highwayConnectionDistance), listOfConcernSegments)

	-- RULE 1
	-- itersection with other segment
	local closestIntersectionDistance = road.segment:length()
	local closestSegment = nil
	for  i, other in ipairs(listOfConcernSegments) do
		if getmetatable(other) == Segment and other.startNode ~= segment.startNode and other.endNode ~= segment.startNode then 
			local intersect, u, v = intersectSegment(segment, other)

			-- intersection
			if intersect and u > 0.0001 and v > 0.0001 and u < segment:length() and v < other:length() then
				if u < closestIntersectionDistance then
					closestIntersectionDistance = u
					closestSegment = other
				end
			end
		end
	end

	if closestSegment ~= nil then
		-- create an itersection here
		-- split road
		local I = segment.startNode.position + segment:dir() * closestIntersectionDistance
		local newNode = Node(I)
		local endNode = closestSegment.endNode

		local s0 = Segment(closestSegment.startNode, newNode)
		s0.color = closestSegment.color
		s0.debugColor = {r = 0, g = 255, b = 0}
		s0.width = closestSegment.width

		local s1 = Segment(newNode, endNode)
		s1.color = closestSegment.color
		s1.debugColor = {r = 0, g = 255, b = 0}
		s1.width = closestSegment.width

		-- remove splitte edge
		quadTree:remove(closestSegment)
		quadTree:push(newNode)
		quadTree:push(s0)
		quadTree:push(s1)

		-- correct this road segment
		segment.debugColor = {r = 0, g = 0, b = 255}

		-- add the segment
		segment.endNode = newNode
		quadTree:push(segment)

		-- doesn't expand the road
		road.attr.done = true

		return true
	end

	-- RULE 2 
	-- else check closest existing intersection
	local P = segment:endPoint() 
	closestIntersectionDistance = roadsParameters.highwayConnectionDistance
	local closestIntersection = nil
	for i, other in ipairs(listOfConcernSegments) do
		if getmetatable(other) == Node and other ~= segment.startNode then
			local d = (other.position - segment.endNode.position):length()
			if d < closestIntersectionDistance then
				closestIntersectionDistance = d
				closestIntersection = other
			end
		end
	end

	if closestIntersection ~= nil then
		segment.endNode = closestIntersection
		segment.debugColor = {r = 255, g = 255, b = 0}

		-- add it to the quadtree
		quadTree:push(segment)

		-- doesn't expand the road
		road.attr.done = true

		return true
	end

	-- RULE 3
	-- check distance to the closest segment
	closestIntersectionDistance = segment:length() * roadsParameters.streetExtensionRatio
	closestSegment = nil
	for i, other in ipairs(listOfConcernSegments) do
		if getmetatable(other) == Segment and other.startNode ~= segment.startNode and other.endNode ~= segment.startNode then
			local intersect, u, v = intersectSegment(segment, other)

			-- intersection
			if intersect and u > 0.0001 and v > 0.0001 and v < other:length() then
				if u < closestIntersectionDistance then
					closestIntersectionDistance = u
					closestSegment = other
				end
			end
		end
	end

	if closestSegment ~= nil then
		-- create an itersection here
		-- split road
		local I = segment.startNode.position + segment:dir() * closestIntersectionDistance
		local newNode = Node(I)
		local endNode = closestSegment.endNode

		local s0 = Segment(closestSegment.startNode, newNode)
		s0.debugColor = {r = 0, g = 255, b = 255}
		s0.color = closestSegment.color
		s0.width = closestSegment.width

		local s1 = Segment(newNode, endNode)
		s1.debugColor = {r = 0, g = 255, b = 255}
		s1.color = closestSegment.color
		s1.width = closestSegment.width

		-- remove splitte edge
		quadTree:remove(closestSegment)
		quadTree:push(newNode)
		quadTree:push(s0)
		quadTree:push(s1)

		-- add the segment
		quadTree:push(segment)

		-- correct this road segment
		segment.debugColor = {r = 255, g = 0, b = 255}

		-- doesn't expand the road
		road.attr.done = true

		return true
	end

	-- don't extend segments outside area
	local E = segment.endNode.position
	if math.abs(E.x) > mapSize or math.abs(E.y) > mapSize then
		road.attr.done = true
	end

	-- add the segment
	quadTree:push(segment.endNode)
	quadTree:push(segment)


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

-- Find the best direction according to a position, and direction, and an angle range
function bestDirection(position, direction, length, angleRange)
	local bestAngle = -angleRange
	local bestSum = 0
	local angle = -angleRange

	for i = 1, roadsParameters.highwayLookUpStepCount do 
		-- sample population along the ray
		local newDir = direction:rotated(angle)
		local sum = populationInDirection(position, newDir, length)
		if sum > bestSum then
			bestSum = sum
			bestAngle = angle
		end

		angle = angle + (angleRange * 2) / roadsParameters.highwayLookUpStepCount
	end

	return bestAngle
end

-- The global goals function
-- NEED WORK :)
function globalGoals(queue, t, road)
	local segment = road.segment
	local attr = road.attr
	local startPosition = segment:endPoint()
	local dir = segment:dir()
	local currentPop = populationAt(startPosition.x, startPosition.y)
	local startNode = segment.endNode

	-- don't expand the road :)
	if attr.done then
		return
	end

	if attr.highway then
		if love.math.random() < roadsParameters.highwayBranchProbability and currentPop > 0.1 then
			queue:push(Road(Segment(startNode, Node(Vector(startPosition + dir:rotated(math.pi * 0.5) * roadsParameters.highwayLength))), {highway = true}), t + roadsParameters.highwayPriority)
		end

		if love.math.random() < roadsParameters.highwayBranchProbability and currentPop > 0.1 then
			queue:push(Road(Segment(startNode, Node(Vector(startPosition + dir:rotated(math.pi * -0.5) * roadsParameters.highwayLength))), {highway = true}), t + roadsParameters.highwayPriority)
		end

		-- look for next population
		if currentPop > 1.8 then
			local bestAngle = math.max(-roadsParameters.highwayAngleRange, math.min(roadsParameters.highwayAngleRange, bestDirection(startPosition, dir, roadsParameters.highwayLookUpRayStepLength, math.pi * 0.1)))

			-- push the best angle
			queue:push(Road(Segment(startNode, Node(Vector(startPosition + dir:rotated(bestAngle) * roadsParameters.highwayLength))), {highway = true}), t + roadsParameters.highwayPriority)
		else
			local bestAngle = bestDirection(startPosition, dir, 150, math.pi * 0.5)

			if bestAngle < 0.0 then
				bestAngle = bestAngle + math.pi * 0.5
			else
				bestAngle = bestAngle - math.pi * 0.5
			end
			-- push the best angle
			queue:push(Road(Segment(startNode, Node(Vector(startPosition + dir:rotated(bestAngle) * roadsParameters.highwayLength))), {highway = true}), t + roadsParameters.highwayPriority)
		end
	elseif currentPop > 0.0 then
		-- keep forward
		queue:push(Road(Segment(startNode, Node(Vector(startPosition + dir * roadsParameters.streetLength))), {}), t+roadsParameters.streetPriority)
	end

	-- street branching
	if currentPop > 0.0 then
		if math.random() < roadsParameters.streetBranchProbability then
			queue:push(Road(Segment(startNode, Node(Vector(startPosition + dir:rotated(math.pi * -0.5) * roadsParameters.streetLength))), {}), t+roadsParameters.streetPriority + 2)
		end

		if math.random() < roadsParameters.streetBranchProbability then
			queue:push(Road(Segment(startNode, Node(Vector(startPosition + dir:rotated(math.pi * 0.5) * roadsParameters.streetLength))), {}), t+roadsParameters.streetPriority + 2)
		end
	end
end

-- Just step the road generation algorithm
function step()
	if #queue > 0 then
		local road, t = queue:pop()
		local accepted = localConstraints(road)

		if accepted then
			-- add global goals
			globalGoals(queue, t + 1, road)
		end
	end
end

function love.load()
	-- setup screen
	love.window.setMode(1280, 720, {resizable = true})

	quadTree = QuadTree(-mapSize, -mapSize, mapSize * 2, mapSize * 2, 128)
	queue = PriorityQueue.new()

	-- create first node
	local startNode = Node(Vector(0, 0))
	quadTree:push(startNode)

	-- compute 2 directions
	local startAngle = bestDirection(Vector(0, 0), Vector(1, 0), roadsParameters.highwayLookUpRayStepLength, math.pi)
	local endNode0 = Node(startNode.position + Vector(1, 0):rotated(startAngle) * roadsParameters.highwayLength)
	local endNode1 = Node(startNode.position + Vector(-1, 0):rotated(startAngle) * roadsParameters.highwayLength)

	-- push possible segments
	queue:push(Road(Segment(startNode, endNode0), {highway = true}) , 0)
	queue:push(Road(Segment(startNode, endNode1), {highway = true}) , 0)
end

function love.update(dt)
	-- quit
	if love.keyboard.isDown("escape") then
		love.event.quit()
	end

	for i = 1, 100 do
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

	if key == "s" then
		step()
	end
end

function love.wheelmoved(x, y)
	zoom = math.max(0.1, math.min(10, zoom + y))
	print(y)
end

function drawQuadTree(node)
	-- draw child first
	if node.children ~= nil then
		drawQuadTree(node.children[0])
		drawQuadTree(node.children[1])
		drawQuadTree(node.children[2])
		drawQuadTree(node.children[3])
	end

	for seg in node.list:iterate() do
		if getmetatable(seg) == Segment then
			if showDebugColor then
				love.graphics.setColor(seg.debugColor.r, seg.debugColor.g, seg.debugColor.b, 255)
			else
				love.graphics.setColor(seg.color.r, seg.color.g, seg.color.b, 255)
			end
			love.graphics.setLineWidth(seg.width * zoom)
			love.graphics.line(seg.startNode.position.x, seg.startNode.position.y, seg.endNode.position.x, seg.endNode.position.y)
		end
	end
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

	-- draw road quadTree
	love.graphics.push()
	love.graphics.translate(cx, cy)
	love.graphics.scale(zoom, zoom)

	drawQuadTree(quadTree)
		
	love.graphics.pop()

	love.graphics.setColor(255, 255, 255, 255)
	love.graphics.print("Segments: " .. quadTree.length, 10, 10)
	love.graphics.print("Queue size: " .. #queue, 10, 25)

	love.graphics.print("'p' to show population", 10, h-40)
	love.graphics.print("'c' to toggle debug color ", 10, h-25)

end