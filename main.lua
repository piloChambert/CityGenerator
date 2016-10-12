
require "PriorityQueue"
require "perlin"
require "vector"
require "list"
require "aabb"
require "QuadTree"
require "RoadSystem"

local cameraX = 0
local cameraY = 0
local zoom = 0.08
local showPopulationMap = false
local showDebugColor = false


local mapSize = 4096

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

local roadSystem = nil 
function love.load()
	-- setup screen
	love.window.setMode(1280, 720, {resizable = true})

	roadSystem = RoadSystem(populationAt, mapSize)
end

function love.update(dt)
	-- quit
	if love.keyboard.isDown("escape") then
		love.event.quit()
	end

	local finished = #roadSystem.queue == 0

	for i = 1, 10 do
		roadSystem:step()
	end

	if not finished and #roadSystem.queue == 0 then
		roadSystem:pruneGraph()

		-- optimise the graph (ie remove nodes in straight roads)
		roadSystem:optimizeGraph()

		-- compute road polygons
		roadSystem:computeRoadPolygons()
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
				love.graphics.setColor(obj.color.r, obj.color.g, obj.color.b, 255)
			end
			love.graphics.setLineWidth(1 / zoom)
			love.graphics.line(obj:startPoint().x, obj:startPoint().y, obj:endPoint().x, obj:endPoint().y)
		elseif getmetatable(obj) == Node then
			--[[
			if #obj.segments > 2 then
				love.graphics.setColor(255, 0, 0, 255)
				love.graphics.circle("fill", obj.position.x, obj.position.y, 10, 8)
			else
				love.graphics.setColor(255, 255, 255, 255)
				love.graphics.circle("fill", obj.position.x, obj.position.y, 10, 8)
			end
			]]

			if obj.vertices then
				love.graphics.setColor(255, 255, 255, 255)

				for i, v in ipairs(obj.vertices) do
					love.graphics.circle("fill", v.x, v.y, 4 / zoom, 8)			
				end

				for i, l in ipairs(obj.lines) do
					local e = l:startPoint() + l:dir() * 20.0
					love.graphics.setLineWidth(1 / zoom)
					love.graphics.line(l:startPoint().x, l:startPoint().y, e.x, e.y)
				end
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

	drawQuadTree(roadSystem.quadTree)
		
	love.graphics.pop()

	love.graphics.setColor(255, 255, 255, 255)
	love.graphics.print("Segments: " .. roadSystem.quadTree.length, 10, 10)
	love.graphics.print("Queue size: " .. #roadSystem.queue, 10, 25)

	love.graphics.print("'p' to show population", 10, h-40)
	love.graphics.print("'c' to toggle debug color ", 10, h-25)

end