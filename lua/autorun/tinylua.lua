tinylua = setmetatable({}, { __call = function(self, ...) return self.Wrap(...) end})
local STORAGE = setmetatable({}, {__mode = "k"})
local INTERNAL = {}
local META = {}

local function pack(...) -- Convenient argument packer
	local len, tbl = select('#', ...), {...}
	local packFuncs = {}

	function packFuncs.unpack()
		return unpack(tbl, 1, len)
	end

	return setmetatable(tbl, {
		__index = function(self, index) 
			return packFuncs[index] or tbl[index]
		end,
		__call = function(...)
			return len, tbl
		end
	})
end

local function getStorage(input)
	return STORAGE[getmetatable(input)]
end

local function Wrap(input)
	local key = newproxy()
	local values = {}
	local meta = {}

	for ind, val in pairs(input)do
		values[(tonumber(ind) and val or ind)] = val
	end

	for ind, val in pairs(META) do
		meta[ind] = val
	end

	STORAGE[key] = {}
	meta.__metatable = key
	return setmetatable(values, meta)
end

local function performCall(tbl, callback)
	local results = {}
	local errors = {}
	local calls = 0

	local iterKey, iterValue = nil, nil
	while true do
		local succ, err = pcall(function()
			while true do
				iterKey, iterValue = next(tbl, iterKey)
				if iterKey == nil then break end
				calls = calls + 1

				callback(results, iterKey, iterValue)
			end
		end)

		if not succ then errors[iterKey] = err end
		if iterKey == nil then break end
	end

	if table.Count(errors) == calls and calls ~= 0 then
		for _, error in pairs(errors) do
			MsgC(Color(235, 111, 111), "[tinylua] "..error)
			break
		end
	end

	local result = Wrap(results)
	getStorage(result)["errors"] = errors
	return result
end

function META:__index(index)
	if INTERNAL[index] then
		return function(_, ...)
			return INTERNAL[index](self, ...)
		end
	end

	return performCall(self, function(results, source, ent)
		local target = ent[index]

		if isfunction(target) then
			results[source] = function(_, ...)
				return target(ent, ...)
			end
		else
			results[source] = target
		end
	end)
end

function META:__newindex(index, value)
	performCall(self, function(results, source, ent)
		ent[index] = value
	end)
end

function META:__call(...)
	local args = pack(...)
	
	if table.Count(self) == 0 then
		MsgC(Color(247, 160, 0), "[tinylua] Nothing to call!")
	end

	return performCall(self, function(results, source, ent)
		if isfunction(ent) then
			local rets = pack(ent(args:unpack()))
			if #rets ~= 1 then
				for _, ret in pairs(rets) do
					table.insert(results, ret)
				end
			else
				results[source] = rets[1]
			end
		end
	end)
end

-- Exposed Functions
tinylua.Wrap = Wrap

-- INTERNAL Extensions
local function buildParser(input)
	if isfunction(input) then return input end
	local argStr, funcStr = input:match("(.-)->(.+)")
	
	if argStr and funcStr then
		local codeFull = string.format("return function(%s) \n return %s \n end", argStr, funcStr)
		local funcFactory = CompileString(codeFull, "funcfactory")
		
		if funcFactory then
			return funcFactory()
		end
	end
end

function INTERNAL:map(input)
	local eval = buildParser(input)
	return performCall(self, function(results, source, ent)
		local rets = pack(eval(ent, source))
		if #rets ~= 1 then
			for _, val in pairs(rets) do
				table.insert(results, val)
			end
		else
			results[source] = rets[1]
		end
	end)
end

function INTERNAL:filter(input)
	local eval = buildParser(input)
	return performCall(self, function(results, source, ent)
		if eval(ent, source) then
			results[source] = ent
		end
	end)
end

function INTERNAL:errors()
	return (getStorage(self).errors or {})
end

function INTERNAL:get()
	return table.ClearKeys(self)
end