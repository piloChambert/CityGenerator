
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

	self._startNode = startNode
	self._startNode:addSegment(self)
	self._endNode = endNode
	self._endNode:addSegment(self)

	self.width = 1
	self.color = {r = 255, g = 255, b = 255}
	self.debugColor = {r = 255, g = 255, b = 255}

	return self
end

function Segment:dir()
	return (self._endNode.position - self._startNode.position):normalized()
end

function Segment:length()
	return (self._endNode.position - self._startNode.position):length()
end

function Segment:startPoint()
	return self._startNode.position
end

function Segment:endPoint() 
	return self._endNode.position
end

function Segment:startNode()
	return self._startNode
end

function Segment:endNode()
	return self._endNode
end

function Segment:setEndNode(endNode)
	if self._endNode then
		self._endNode:removeSegment(self)
	end

	self._endNode = endNode

	if self._endNode then
		self._endNode:addSegment(self)
	end
end

function Segment:setStartNode(startNode)
	if self._startNode then
		self._startNode:removeSegment(self)
	end

	self._startNode = startNode

	if self._startNode then
		self._startNode:addSegment(self)
	end
end

function Segment:aabb() 
	local minX = math.min(self:startPoint().x, self:endPoint().x)
	local maxX = math.max(self:startPoint().x, self:endPoint().x)
	local minY = math.min(self:startPoint().y, self:endPoint().y)
	local maxY = math.max(self:startPoint().y, self:endPoint().y)

	return AABB(minX, minY, maxX, maxY)
end

setmetatable(Segment, { __call = function(_, ...) return Segment.new(...) end })

Road = {}
Road.__index = Road

function Road.new(seg, attr, goalsFunc)
	local self = setmetatable({}, Road)

	self.segment = seg
	self.attr = attr
	self.goalsFunc = goalsFunc

	return self
end

setmetatable(Road, { __call = function(_, ...) return Road.new(...) end })

mapSize = 4096

-- configuration
roadsParameters = {
	-- highway
	highwayLength = 50,
	highwayAngleRange = 0.5 * math.pi,
	highwayLookUpStepCount = 20,
	highwayLookUpRayStepCount = 20,
	highwayLookUpRayStepLength = 2000,
	highwayConnectionDistance = 20, 
	highwayPriority = 1,
	highwayBranchProbability = 0.02,
	highwayChangeDirectionProbability = 0.05,

	streetExtensionRatio = 0.2,

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

	return false, -1, -1
end

-- The local constraints function
-- It prunes some segments (need work on that)
-- And check for intersection with existing road segments
listOfConcernSegments = {}
function localConstraints(road)
	local segment = road.segment

	-- rendering parameter
	if road.attr.highway then
		segment.width = 16.0
		segment.color = {r = 255, g = 255, b = 255}
		segment.debugColor = {r = 255, g = 255, b = 255}
	else
		segment.width = 8.0
		segment.color = {r = 64, g = 64, b = 64}		
		segment.debugColor = {r = 255, g = 255, b = 255}
	end

	for i,v in ipairs(listOfConcernSegments) do
		v.selected = false
	end

	listOfConcernSegments = {}
	local maxLength = segment:length() + math.max(segment:length() * roadsParameters.streetExtensionRatio, roadsParameters.highwayConnectionDistance)
	local queryEndNode = Node(segment:startPoint() + segment:dir() * maxLength)
	local querySegment = Segment(Node(segment:startPoint()), queryEndNode)
	quadTree:query(querySegment:aabb(), listOfConcernSegments)

	for i,v in ipairs(listOfConcernSegments) do
		v.selected = true
	end

	-- RULE 1
	-- itersection with other segment
	local closestIntersectionDistance = road.segment:length()
	local closestSegment = nil

	for  i, other in ipairs(listOfConcernSegments) do
		if getmetatable(other) == Segment and other:startNode() ~= segment:startNode() and other:endNode() ~= segment:startNode() then 
			local intersect, u, v = intersectSegment(segment, other)
			-- intersection
			if intersect and u >= 0.0 and v >= 0.0 and u <= segment:length() and v <= other:length() then
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
		local I = segment:startPoint() + segment:dir() * closestIntersectionDistance
		local newNode = Node(I)
		local endNode = closestSegment:endNode()

		-- add new node
		quadTree:push(newNode)

		-- update splitted segment
		quadTree:remove(closestSegment) -- we have to do it!
		closestSegment:setEndNode(newNode)
		quadTree:push(closestSegment) -- the aabb have changed!

		-- add new segment
		local newSegment = Segment(newNode, endNode)
		newSegment.color = closestSegment.color
		newSegment.debugColor = {r = 0, g = 255, b = 0}
		newSegment.width = closestSegment.width
		quadTree:push(newSegment)

		-- correct this road segment
		segment.debugColor = {r = 0, g = 0, b = 255}

		-- add the segment
		segment:setEndNode(newNode)
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
		if getmetatable(other) == Node then
			if (#other.segments > 2 or (other.position - P):length() < 1.0) and other ~= segment:startNode() then
				local dist = (other.position - segment:endPoint()):length()
				if dist < closestIntersectionDistance then
					closestIntersectionDistance = dist
					closestIntersection = other
				end
			end
		end
	end

	if closestIntersection ~= nil then
		segment:setEndNode(closestIntersection)
		segment.debugColor = {r = 255, g = 255, b = 0}

		-- add it to the quadtree
		quadTree:push(segment)

		-- doesn't expand the road
		road.attr.done = true

		return true
	end

	-- RULE 3
	-- check distance to the closest segment
	closestIntersectionDistance = segment:length() * (1.0 + roadsParameters.streetExtensionRatio)
	closestSegment = nil
	for i, other in ipairs(listOfConcernSegments) do
		if getmetatable(other) == Segment and other:startNode() ~= segment:startNode() and other:endNode() ~= segment:startNode() then
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
		local I = segment:startPoint() + segment:dir() * closestIntersectionDistance
		local newNode = Node(I)
		local endNode = closestSegment:endNode()

		-- add new node
		quadTree:push(newNode)

		-- update splitted segment
		quadTree:remove(closestSegment) -- we have to do it!
		closestSegment:setEndNode(newNode)
		quadTree:push(closestSegment) -- the aabb have changed!

		-- add new segment
		local newSegment = Segment(newNode, endNode)
		newSegment.color = closestSegment.color
		newSegment.debugColor = {r = 0, g = 255, b = 0}
		newSegment.width = closestSegment.width
		quadTree:push(newSegment)

		segment:setEndNode(newNode)

		-- add the segment
		quadTree:push(segment)

		-- correct this road segment
		segment.debugColor = {r = 255, g = 0, b = 255}

		-- doesn't expand the road
		road.attr.done = true

		return true
	end

	-- don't extend segments outside area
	local E = segment:endPoint()
	if math.abs(E.x) > mapSize or math.abs(E.y) > mapSize then
		road.attr.done = true
	end

	-- add the segment
	quadTree:push(segment:endNode())
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

function globalGoalsHighway(t, road)
	local segment = road.segment
	local attr = road.attr
	local startPosition = segment:endPoint()
	local dir = segment:dir()
	local currentPop = populationAt(startPosition.x, startPosition.y)
	local startNode = segment:endNode()

	-- don't expand the road :)
	if attr.done then
		return
	end

	-- change direction
	if math.random() < roadsParameters.highwayChangeDirectionProbability then
		-- choose best direction
		local bestAngle = bestDirection(startPosition, dir, 8000, math.pi * 0.25)
		local newEnd = Vector(startPosition + dir:rotated(bestAngle) * roadsParameters.highwayLength)
		queue:push(Road(Segment(startNode, Node(newEnd)), {highway = true}, globalGoalsHighway), t)

	else
		-- go straight
		local newEnd = Vector(startPosition + dir * roadsParameters.highwayLength)
		queue:push(Road(Segment(startNode, Node(newEnd)), {highway = true}, globalGoalsHighway), t)
	end

	-- branch?
	if math.random() < roadsParameters.highwayBranchProbability then
		local newEnd = Vector(startPosition + dir:rotated(math.pi * 0.5) * roadsParameters.highwayLength)
		queue:push(Road(Segment(startNode, Node(newEnd)), {highway = true}, globalGoalsHighway), t + 1)	
	end

	if math.random() < roadsParameters.highwayBranchProbability then
		local newEnd = Vector(startPosition + dir:rotated(math.pi * -0.5) * roadsParameters.highwayLength)
		queue:push(Road(Segment(startNode, Node(newEnd)), {highway = true}, globalGoalsHighway), t + 1)	
	end

end

-- The global goals function
-- NEED WORK :)
function globalGoals(t, road)
	local segment = road.segment
	local attr = road.attr
	local startPosition = segment:endPoint()
	local dir = segment:dir()
	local currentPop = populationAt(startPosition.x, startPosition.y)
	local startNode = segment:endNode()

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

function optimizeGraph()
	nodes = {}
	quadTree:query(AABB(-mapSize * 2, -mapSize * 2, mapSize * 4, mapSize * 4), nodes)

	for i, obj in ipairs(nodes) do
		if getmetatable(obj) == Node then

			if #obj.segments == 2 then
				local s0 = obj.segments[1]
				local s1 = obj.segments[2]

				if math.abs(s0:dir():dot(s1:dir())) > 0.99 then
					local n0 = s0:startNode()
					if n0 == obj then
						n0 = s0:endNode()
					end

					local n1 = s1:startNode()
					if n1 == obj then
						n1 = s1:endNode()
					end

					quadTree:remove(s0)
					quadTree:remove(s1)
					quadTree:remove(obj)

					s0.marked = true
					s1.marked = true

					s0:setStartNode(nil)
					s0:setEndNode(nil)
					s1:setStartNode(nil)
					s1:setEndNode(nil)

					assert(n0 ~= n1)
					local s = Segment(n0, n1)
					quadTree:push(s)
				end
			end
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
			road.goalsFunc(t + 1, road)
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
	queue:push(Road(Segment(startNode, endNode0), {highway = true}, globalGoalsHighway) , 0)
	queue:push(Road(Segment(startNode, endNode1), {highway = true}, globalGoalsHighway) , 0)

	while quadTree.length < 2541 do
		step()
	end
end

function love.update(dt)
	-- quit
	if love.keyboard.isDown("escape") then
		love.event.quit()
	end

	local finished = #queue == 0

	for i = 1, 100 do
		step()
	end

	if not finished and #queue == 0 then
		-- optimise the graph (ie removed nodes)
		optimizeGraph()
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

	for obj in node.list:iterate() do
		if getmetatable(obj) == Segment then
			if showDebugColor then
				love.graphics.setColor(obj.debugColor.r, obj.debugColor.g, obj.debugColor.b, 255)
			else
				if obj.selected then
					love.graphics.setColor(255, 0, 0, 255)
				else
					love.graphics.setColor(obj.color.r, obj.color.g, obj.color.b, 255)
				end
			end
			--love.graphics.setLineWidth(obj.width)
			love.graphics.line(obj:startPoint().x, obj:startPoint().y, obj:endPoint().x, obj:endPoint().y)
		elseif getmetatable(obj) == Node then
			if #obj.segments > 2 then
				love.graphics.setColor(255, 0, 0, 255)
				love.graphics.circle("fill", obj.position.x, obj.position.y, 10, 8)
			else
				love.graphics.setColor(255, 255, 255, 255)
				love.graphics.circle("fill", obj.position.x, obj.position.y, 10, 8)
			end

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