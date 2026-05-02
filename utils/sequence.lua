local seq = {}

local function iterable(sequence)
	local function _run_predicates(input)
		local steps = { [0]=input }
		for _,p in pairs(sequence.predicates) do
			local result = p.predicate(input)
			if p.filter and result == nil then
				break
			end
			table.insert(steps, result)
		end
		-- steps should contain as many results as there were predicates
		-- if there are less, the input value got filtered out
		return #steps == #sequence.predicates, steps[#sequence.predicates]
	end
	local function _iter(sequence_, idx)
		for i=idx,#sequence_.items do
			local success, result = _run_predicates(sequence_.items[i])
			if success then
				return i+1, result
			end
		end
	end
	return _iter, sequence, 1
end

function Sequence(args)
	return setmetatable({ items = args, predicates = {} }, { __index = seq })
end

function seq:collect()
	local collection = {}
	for _,item in iterable(self) do
		table.insert(collection, item)
	end
	return collection
end

function seq:filter(predicate)
	table.insert(self.predicates, { filter = true, predicate = function(x) if predicate(x) then return x end end })
	return self
end

function seq:map(mapper)
	table.insert(self.predicates, { filter = false, predicate = mapper} )
	return self
end

function seq:foreach(habbening)
	for _,v in pairs(self:collect()) do
		habbening(v)
	end
end

function seq:find_first(predicate)
	for k,v in iterable(self) do
		if predicate(v) == true then
			return k,v
		end
	end
end

function seq:reduce(reducer)
	local function _reduce(a,b) return a and reducer(a,b) or b end
	local result = nil
	for _,v in pairs(self:collect()) do
		result = _reduce(result, v)
	end
	return result
end

seq.TO_NUMBER = function(x) return tonumber(x) end
seq.ADD = function(a,b) return a+b end
return seq
