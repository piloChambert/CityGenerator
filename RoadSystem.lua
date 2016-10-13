-- configuration
roadsParameters = {
	-- highway
	highwayLength = 50,
	highwayAngleRange = 0.5 * math.pi,
	highwayLookUpStepCount = 20,
	highwayLookUpRayStepCount = 20,
	highwayLookUpRayStepLength = 2000,
	highwayConnectionRatio = 0.5,
	highwayPriority = 1,
	highwayBranchProbability = 0.013,
	highwayChangeDirectionProbability = 0.2,
	highwayBranchStreetProbability = 0.5,
	highwayBranchStreetMinPopulation = 0.1,

	streetExtensionRatio = 0.2,

	-- streets
	streetLength = 80,
	streetPriority = 200,
	streetBranchProbability = 0.2
}

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

function Node:test()
	-- does nothing
end

setmetatable(Node, { __call = function(_, ...) return Node.new(...) end })

-- segments
Segment = {}
Segment.__index = Segment

function Segment.new(startNode, endNode, attr)
	local self = setmetatable({}, Segment)

	self._startNode = startNode
	self._startNode:addSegment(self)
	self._endNode = endNode
	self._endNode:addSegment(self)
	self.attr = attr

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

-- check intersection between 2 segments
function Segment:intersect(other)
	local Adir = self:dir()
	local Bdir = other:dir()
	local den = Adir * Bdir

	if math.abs(den) > 0.00000001 then
		-- I = A.pos + A.dir * u = B.pos + B.dir * v
		local diff = other:startPoint() - self:startPoint()

		local u = (diff * Bdir) / den
		local v = (diff * Adir) / den

		-- intersection
		return true, u, v
	end

	return false, -1, -1
end

function Segment:test()
	local len = self:dir():length()
	if len ~= len then
		print(self:startPoint(), self:endPoint())
	end

	assert(len == len)
end

setmetatable(Segment, { __call = function(_, ...) return Segment.new(...) end })

SegmentStub = {
	dir = Segment.dir,
	length = Segment.length,
	startPoint = Segment.startPoint,
	endPoint = Segment.endPoint,
	startNode = Segment.startNode,
	endNode = Segment.endNode,
	aabb = Segment.aabb,
	intersect = Segment.intersect
}
SegmentStub.__index = SegmentStub

function SegmentStub.new(startNode, endNode, attr)
	local self = setmetatable({}, SegmentStub)

	self._startNode = startNode
	self._endNode = endNode

	self.width = 1
	self.color = {r = 255, g = 255, b = 255}
	self.debugColor = {r = 255, g = 255, b = 255}
	self.attr = attr

	return self
end

function SegmentStub:setEndNode(endNode)
	self._endNode = endNode
end

function SegmentStub:setStartNode(startNode)
	self._startNode = startNode
end 

function SegmentStub:toSegment()
	local new = Segment(self._startNode, self._endNode, self.attr)
	new.color = self.color
	new.debugColor = self.debugColor
	new.width = self.width

	return new
end

setmetatable(SegmentStub, { __call = function(_, ...) return SegmentStub.new(...) end })

Road = {}
Road.__index = Road

function Road.new(seg, goalsFunc)
	local self = setmetatable({}, Road)

	self.segment = seg
	self.goalsFunc = goalsFunc

	return self
end

setmetatable(Road, { __call = function(_, ...) return Road.new(...) end })


RoadSystem = {}
RoadSystem.__index = RoadSystem

function RoadSystem.new(populationFunction, mapSize)
	local self = setmetatable({}, RoadSystem)

	self.populationAt = populationFunction

	self.mapSize = mapSize
	self.quadTree = QuadTree(-mapSize, -mapSize, mapSize * 2, mapSize * 2, 128)
	self.queue = PriorityQueue.new()

	-- create first node
	local startNode = Node(Vector(0, 0))
	self.quadTree:push(startNode)

	-- compute 2 directions
	local startAngle = self:bestDirection(Vector(0, 0), Vector(1, 0), roadsParameters.highwayLookUpRayStepLength, math.pi)
	local endNode0 = Node(startNode.position + Vector(1, 0):rotated(startAngle) * roadsParameters.highwayLength)
	local endNode1 = Node(startNode.position + Vector(-1, 0):rotated(startAngle) * roadsParameters.highwayLength)

	-- push possible segments
	self.queue:push(Road(SegmentStub(startNode, endNode0, {highway = true}), RoadSystem.globalGoalsHighway) , 0)
	self.queue:push(Road(SegmentStub(startNode, endNode1, {highway = true}), RoadSystem.globalGoalsHighway) , 0)


	return self
end

setmetatable(RoadSystem, { __call = function(_, ...) return RoadSystem.new(...) end })

-- Just step the road generation algorithm
function RoadSystem:step()
	if #self.queue > 0 then
		local road, t = self.queue:pop()
		local accepted = self:localConstraints(road)

		if accepted then
			-- add global goals
			road.goalsFunc(self, t + 1, road)
		end
	end
end

-- this compute the weighted population over a segment
function RoadSystem:populationInDirection(position, direction, length)
	local sum = 0

	for s = 1, roadsParameters.highwayLookUpRayStepCount do
		local dist = length * s / roadsParameters.highwayLookUpRayStepCount
		local p = position + direction * dist
		local pop = self.populationAt(p.x, p.y)
		sum = sum + pop / dist
	end

	return sum
end

-- Find the best direction according to a position, and direction, and an angle range
function RoadSystem:bestDirection(position, direction, length, angleRange)
	local bestAngle = -angleRange
	local bestSum = 0
	local angle = -angleRange

	for i = 1, roadsParameters.highwayLookUpStepCount do 
		-- sample population along the ray
		local newDir = direction:rotated(angle)
		local sum = self:populationInDirection(position, newDir, length)
		if sum > bestSum then
			bestSum = sum
			bestAngle = angle
		end

		angle = angle + (angleRange * 2) / roadsParameters.highwayLookUpStepCount
	end

	return bestAngle
end

function RoadSystem:globalGoalsHighway(t, road)
	local segment = road.segment
	local startPosition = segment:endPoint()
	local dir = segment:dir()
	local currentPop = self.populationAt(startPosition.x, startPosition.y)
	local startNode = segment:endNode()

	-- don't expand the road :)
	if segment.attr.done then
		return
	end

	-- change direction
	if math.random() < roadsParameters.highwayChangeDirectionProbability then
		-- choose best direction
		local bestAngle = self:bestDirection(startPosition, dir, 8000, math.pi * 0.01)
		local newEnd = Vector(startPosition + dir:rotated(bestAngle) * roadsParameters.highwayLength)
		self.queue:push(Road(SegmentStub(startNode, Node(newEnd), {highway = true}), RoadSystem.globalGoalsHighway), t)

	else
		-- go straight
		local newEnd = Vector(startPosition + dir * roadsParameters.highwayLength)
		self.queue:push(Road(SegmentStub(startNode, Node(newEnd), {highway = true}), RoadSystem.globalGoalsHighway), t)
	end

	-- branch highway
	local branchRight = false
	local branchLeft = false
	if math.random() < roadsParameters.highwayBranchProbability then
		local r = math.random()
		branchRight = r < 0.6666666
		branchLeft = r > 0.3333333

		if branchRight then
			local newEnd = Vector(startPosition + dir:rotated(math.pi * 0.5) * roadsParameters.highwayLength)
			self.queue:push(Road(SegmentStub(startNode, Node(newEnd), {highway = true}), RoadSystem.globalGoalsHighway), t + 1)	
		end

		if branchLeft then
			local newEnd = Vector(startPosition + dir:rotated(math.pi * -0.5) * roadsParameters.highwayLength)
			self.queue:push(Road(SegmentStub(startNode, Node(newEnd), {highway = true}), RoadSystem.globalGoalsHighway), t + 1)	
		end
	end

	-- branch street
	if currentPop >= roadsParameters.highwayBranchStreetMinPopulation and math.random() < roadsParameters.highwayBranchStreetProbability then
		local r = math.random()
		branchRight = r < 0.6666666 and not branchRight
		branchLeft = r > 0.3333333 and not branchLeft

		if branchRight then	
			local newEnd = Vector(startPosition + dir:rotated(math.pi * 0.5) * roadsParameters.streetLength)
			self.queue:push(Road(SegmentStub(startNode, Node(newEnd), {}), RoadSystem.globalGoalsStreet), t + 150)	
		end

		if branchLeft then
			local newEnd = Vector(startPosition + dir:rotated(math.pi * -0.5) * roadsParameters.streetLength)
			self.queue:push(Road(SegmentStub(startNode, Node(newEnd), {}), RoadSystem.globalGoalsStreet), t + 150)	
		end
	end
end

function RoadSystem:globalGoalsStreet(t, road)
	local segment = road.segment
	local startPosition = segment:endPoint()
	local dir = segment:dir()
	local currentPop = populationAt(startPosition.x, startPosition.y)
	local startNode = segment:endNode()

	-- don't expand the road :)
	if segment.attr.done then
		return
	end

	if currentPop > 0.1 then
		-- keep moving straight
		local newEnd = Vector(startPosition + dir * roadsParameters.streetLength)
		self.queue:push(Road(SegmentStub(startNode, Node(newEnd), {}), RoadSystem.globalGoalsStreet), t + 20)	

		if math.random() < roadsParameters.streetBranchProbability then
			local newEnd = Vector(startPosition + dir:rotated(math.pi * 0.5) * roadsParameters.streetLength)
			self.queue:push(Road(SegmentStub(startNode, Node(newEnd), {}), RoadSystem.globalGoalsStreet), t + 10)	
		end

		if math.random() < roadsParameters.streetBranchProbability then
			local newEnd = Vector(startPosition + dir:rotated(math.pi * -0.5) * roadsParameters.streetLength)
			self.queue:push(Road(SegmentStub(startNode, Node(newEnd), {}), RoadSystem.globalGoalsStreet), t + 10)	
		end
	end
end

-- The local constraints function
-- It prunes some segments (need work on that)
-- And check for intersection with existing road segments
function RoadSystem:localConstraints(road)
	local segment = road.segment

	-- rendering parameter
	if segment.attr.highway then
		segment.width = 16.0
		segment.color = {r = 255, g = 255, b = 255}
		segment.debugColor = {r = 255, g = 255, b = 255}
	else
		segment.width = 6.0
		segment.color = {r = 64, g = 64, b = 64}		
		segment.debugColor = {r = 255, g = 255, b = 255}
	end

	local listOfConcernSegments = {}
	local maxLength = segment:length() * (1.0 + math.max(roadsParameters.streetExtensionRatio, roadsParameters.highwayConnectionRatio))
	local queryEndNode = Node(segment:startPoint() + segment:dir() * maxLength)
	local querySegment = SegmentStub(Node(segment:startPoint()), queryEndNode)
	self.quadTree:query(querySegment:aabb(), listOfConcernSegments)

	-- RULE 1
	-- itersection with other segment
	local closestIntersectionDistance = road.segment:length()
	local closestIntersectionDistanceToOther = road.segment:length()
	local closestSegment = nil

	for  i, other in ipairs(listOfConcernSegments) do
		if getmetatable(other) == Segment and other:startNode() ~= segment:startNode() and other:endNode() ~= segment:startNode() then 
			local intersect, u, v = segment:intersect(other)

			-- intersection
			if intersect and u >= 0.0 and v >= 0.0 and u <= segment:length() and v <= other:length() then
				if u < closestIntersectionDistance then
					closestIntersectionDistance = u
					closestIntersectionDistanceToOther = v
					closestSegment = other
				end
			end
		end
	end

	if closestSegment ~= nil then
		-- to close to the start (shouldn't happen, but who knows?)
		if closestIntersectionDistance < 1.0 then
			-- give up!
			return false
		end

		-- too close to the start, we will snap with it
		if closestIntersectionDistanceToOther < 1.0 then
			segment:setEndNode(closestSegment:startNode())
			segment.debugColor = {r = 255, g = 255, b = 0}

			-- add it to the quadtree
			self.quadTree:push(segment:toSegment())

			-- doesn't expand the road
			segment.attr.done = true

			return true
		-- too close to the end, we will snap
		elseif closestSegment:length() - closestIntersectionDistanceToOther < 1.0 then
			segment:setEndNode(closestSegment:endNode())
			segment.debugColor = {r = 255, g = 255, b = 0}

			-- add it to the quadtree
			self.quadTree:push(segment:toSegment())

			-- doesn't expand the road
			segment.attr.done = true

			return true
		else
			-- create an itersection here
			-- split road
			local I = segment:startPoint() + segment:dir() * closestIntersectionDistance
			local newNode = Node(I)
			local endNode = closestSegment:endNode()

			-- add new node
			self.quadTree:push(newNode)

			-- update splitted segment
			self.quadTree:remove(closestSegment) -- we have to do it!
			closestSegment:setEndNode(newNode)
			self.quadTree:push(closestSegment) -- the aabb have changed!

			-- add new segment
			local newSegment = Segment(newNode, endNode, closestSegment.attr)
			newSegment.color = closestSegment.color
			newSegment.debugColor = {r = 0, g = 255, b = 0}
			newSegment.width = closestSegment.width
			self.quadTree:push(newSegment)

			-- correct this road segment
			segment.debugColor = {r = 0, g = 0, b = 255}

			-- add the segment
			segment:setEndNode(newNode)
			self.quadTree:push(segment:toSegment())

			-- doesn't expand the road
			segment.attr.done = true

			return true
		end
	end

	-- RULE 2 
	-- else check closest existing intersection
	local P = segment:endPoint() 
	closestIntersectionDistance = segment:length() * roadsParameters.highwayConnectionRatio
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
		self.quadTree:push(segment:toSegment())

		-- doesn't expand the road
		segment.attr.done = true

		return true
	end

	-- RULE 3
	-- check distance to the closest segment
	closestIntersectionDistance = segment:length() * (1.0 + roadsParameters.streetExtensionRatio)
	closestSegment = nil
	for i, other in ipairs(listOfConcernSegments) do
		if getmetatable(other) == Segment and other:startNode() ~= segment:startNode() and other:endNode() ~= segment:startNode() then
			local intersect, u, v = segment:intersect(other)

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
		self.quadTree:push(newNode)

		-- update splitted segment
		self.quadTree:remove(closestSegment) -- we have to do it!
		closestSegment:setEndNode(newNode)
		self.quadTree:push(closestSegment) -- the aabb have changed!

		-- add new segment
		local newSegment = Segment(newNode, endNode, closestSegment.attr)
		newSegment.color = closestSegment.color
		newSegment.debugColor = {r = 0, g = 255, b = 0}
		newSegment.width = closestSegment.width
		self.quadTree:push(newSegment)

		segment:setEndNode(newNode)

		-- add the segment
		self.quadTree:push(segment:toSegment())

		-- correct this road segment
		segment.debugColor = {r = 255, g = 0, b = 255}

		-- doesn't expand the road
		segment.attr.done = true

		return true
	end

	-- don't extend segments outside area
	local E = segment:endPoint()
	if math.abs(E.x) > self.mapSize or math.abs(E.y) > self.mapSize then
		segment.attr.done = true
	end

	-- add the segment
	self.quadTree:push(segment:endNode())
	self.quadTree:push(segment:toSegment())


	return true
end

-- prune node with only 1 segment (dead end) for street
-- recursive!
function RoadSystem:pruneNode(node)
	if #node.segments == 1 and not node.segments[1].attr.highway then
		-- remove segment and node 
		local s = node.segments[1]
		self.quadTree:remove(s)
		self.quadTree:remove(node)

		local otherNode = s:startNode()
		if otherNode == node then
			otherNode = s:endNode()
		end

		s:setStartNode(nil)
		s:setEndNode(nil)

		self:pruneNode(otherNode)
	end
end

function RoadSystem:pruneGraph()
	nodes = {}
	self.quadTree:query(AABB(-self.mapSize * 2, -self.mapSize * 2, self.mapSize * 4, self.mapSize * 4), nodes)

	for i, obj in ipairs(nodes) do
		if getmetatable(obj) == Node then
			self:pruneNode(obj)
		end
	end
end

-- remove node on straight lines without intersection
function RoadSystem:optimizeGraph()
	nodes = {}
	self.quadTree:query(AABB(-self.mapSize * 2, -self.mapSize * 2, self.mapSize * 4, self.mapSize * 4), nodes)

	for i, obj in ipairs(nodes) do
		if getmetatable(obj) == Node then

			if #obj.segments == 2 then
				local s0 = obj.segments[1]
				local s1 = obj.segments[2]

				-- remove node for straight roads
				if math.abs(s0:dir():dot(s1:dir())) > 0.9999 then
					local n0 = s0:startNode()
					if n0 == obj then
						n0 = s0:endNode()
					end

					local n1 = s1:startNode()
					if n1 == obj then
						n1 = s1:endNode()
					end

					self.quadTree:remove(s0)
					self.quadTree:remove(s1)
					self.quadTree:remove(obj)

					s0:setStartNode(nil)
					s0:setEndNode(nil)
					s1:setStartNode(nil)
					s1:setEndNode(nil)

					assert(n0 ~= n1)
					local s = Segment(n0, n1, s0.attr)
					s.width = s0.width 
					s.color = s0.color
					s.debugColor = s0.debugColor
					self.quadTree:push(s)
				end
			end
		end
	end
end

Line = {
	intersect = Segment.intersect
}
Line.__index = Line

function Line.new(pos, dir)
	local self = setmetatable({}, Line)
	self._pos = pos
	self._dir = dir

	return self
end

function Line:dir() 
	return self._dir
end

function Line:startPoint()
	return self._pos
end

function Line:endPoint()
	return self._pos + self._dir * 20.0
end


setmetatable(Line, { __call = function(_, ...) return Line.new(...) end })


function RoadSystem:computeRoadPolygons()
	nodes = {}
	self.quadTree:query(AABB(-self.mapSize * 2, -self.mapSize * 2, self.mapSize * 4, self.mapSize * 4), nodes)

	for i, node in ipairs(nodes) do
		if getmetatable(node) == Node then
			-- sorts segments

			sort = function(a, b)
				local ad = a:dir() 
				if a:endNode() == node then ad = -ad end
				local bd = b:dir() 
				if b:endNode() == node then bd = -bd end

				if ad.y > 0 then
					if bd.y < 0 then 
						return true
					end

					return ad.x > bd.x
				else
					if bd.y > 0 then
						return false
					end

					return ad.x < bd.x
				end
			end
			table.sort(node.segments, sort)

			node.vertices = {}
			node.lines = {}

			-- now compute intersection between consecutive segments
			for i = 0, #node.segments - 1 do 
				local s0 = node.segments[i + 1] -- correct starting index
				local dir0 = s0:dir()
				if s0:endNode() == node then dir0 = -dir0 end

				local s1 = node.segments[((i + 1) % #node.segments) + 1]
				local dir1 = s1:dir()
				if s1:endNode() == node then dir1 = -dir1 end

				local l0 = Line(node.position + dir0:rotated(math.pi * 0.5) * s0.width, dir0)
				local l1 = Line(node.position + dir1:rotated(math.pi * -0.5) * s1.width, dir1)

				table.insert(node.lines, {l0, l1, Line(node.position, dir0), Line(node.position, dir1)})

				local A = node.position + dir0 * 5
				local B = node.position + dir1 * 5
				local dl = Line(A, (B - A):normalized())

				local intersect, u, v = l0:intersect(l1)

				local v = nil

				if intersect then
					v = l0:startPoint() + l0:dir() * u
				else
					-- assume colinear
					v = l0:startPoint()
				end

				table.insert(node.vertices, v)

				if s0.vertices == nil then
					s0.vertices = {}
				end

				if s1.vertices == nil then
					s1.vertices = {}
				end

				if s0:startNode() == node then
					s0.vertices[2] = v
				else
					s0.vertices[0] = v
				end

				if s1:startNode() == node then
					s1.vertices[3] = v
				else
					s1.vertices[1] = v
				end

			end
		end
	end
end