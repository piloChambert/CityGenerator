PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

function PriorityQueue.new()
	local self = setmetatable({}, PriorityQueue)

	return self
end

function PriorityQueue:push(obj, priority)
	-- insert at the end
	table.insert(self, {["object"] = obj, ["priority"] = priority})

	--print(obj, priority)

	local idx = #self -- position of the new item
	local parent = (idx - idx%2) / 2

	while idx > 1 and self[idx].priority <= self[parent].priority do 
		-- swap item
		self[idx], self[parent] = self[parent], self[idx]
		idx = parent
		parent = (idx - idx%2) / 2
	end
end

function PriorityQueue:pop()
	if #self == 0 then
		return nil
	end

	if #self < 2 then
		local res = table.remove(self)
		return res.object, res.priority
	end

	-- get the result
	local res = self[1]

	-- update the heap
	if #self > 1 then
		-- move last element to top
		self[1] = table.remove(self)

		-- and move it down
		local idx = 1
		local c1 = idx * 2
		local c2 = idx * 2 + 1

		while c2 <= #self and not (self[idx].priority < self[c1].priority and self[idx].priority < self[c2].priority) do
			if self[c1].priority < self[c2].priority and self[idx].priority >= self[c1].priority then
				-- swap
				self[idx], self[c1] = self[c1], self[idx]
				idx = c1
			elseif self[idx].priority >= self[c2].priority then
				-- swap
				self[idx], self[c2] = self[c2], self[idx]
				idx = c2
			end

			c1 = idx * 2
			c2 = idx * 2 + 1
		end

		-- we can have only c1
		if c1 < #self and self[idx].priority >= self[c1].priority then
			--swap
			self[idx], self[c1] = self[c1], self[idx]
		end
	end

	return res.object, res.priority
end