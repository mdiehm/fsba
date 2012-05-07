--
-- Copyright (c) 2011 Mischa Diehm <md@mailq.de>
--
-- Permission to use, copy, modify, and distribute this software for any
-- purpose with or without fee is hereby granted, provided that the above
-- copyright notice and this permission notice appear in all copies.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
-- WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
-- ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
-- WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
-- ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
-- OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
--
-- STRINGHELPER

-- Compatibility: Lua-5.0 - from lua-users.org
function split(str, delim, maxNb)
    -- Eliminate bad cases...
    if string.find(str, delim) == nil then
        return { str }
    end
    if maxNb == nil or maxNb < 1 then
        maxNb = 0    -- No limit
    end
    local result = {}
    local pat = "(.-)" .. delim .. "()"
    local nb = 0
    local lastPos
    for part, pos in string.gfind(str, pat) do
        nb = nb + 1
        result[nb] = part
        lastPos = pos
        if nb == maxNb then break end
    end
    -- Handle the last field
    if nb ~= maxNb then
        result[nb + 1] = string.sub(str, lastPos)
    end
    return result
end

function trim(str, s)
	if str == nil then
		return
	end

	s = s or "%s+"
	str = string.gsub(str, "^" .. s .. "", "")
	str = string.gsub(str, s .. "$", "")
	return str
end


-- DIRECTORYPATH

function splitpath(path)
	local elements = {}
	for element in path:gmatch("/[^/]*") do
		table.insert(elements, element)
	end
	return elements
end

function normalizepath(path)
	-- if we got a relative path get cwd first
	if path:match("^/") == nil then
		local lcwd = fs.currentdir()
		if lcwd == nil then
			return nil
		end
		path = lcwd .. "/" .. path
	end

	path = splitpath(path)
	local resolved = {}
	for k, v in ipairs(path) do
		if v == "/.." then
			table.remove(resolved)
		elseif v == "/." then
			table.remove(resolved, k)
		else
			table.insert(resolved, v)
		end

	end
	return resolved
end

function getrcwd(cwst)
	local o = pers_rexec(cwst, "pwd")
	if o ~= nil then
		return(string.gsub(o, "\n$", ""))
	end
	return
end


-- FILETRANSFER

function mput(cwst, dst)
	local rdst = ""
	local rcwd = getrcwd(cwst)
	if string.match(dst, "^~") then
		local h = pers_rexec(cwst, "echo $HOME")
		if h ~= nil then
			h = string.gsub(h, "\n$", "")
			rdst = h ..  string.sub(dst, 2)
		end
	elseif not string.match(dst, "^/") then
		if rcwd ~= nil then
			rdst = rcwd .. "/" .. rdst
		else
			return
		end
	else
		rdst = dst
	end
	return rdst
end

function mget(cwst, src)
	local rsrc = ""
	local rcwd = getrcwd(cwst)
	for p in string.gmatch(src, "[^%s]+") do
		if string.match(p, "^~") then
			local h = pers_rexec(cwst, "echo $HOME")
			if h ~= nil then
				h = string.gsub(h, "\n$", "")
				rsrc = rsrc .. " " ..  h ..  string.sub(p, 2)
			end
		elseif not string.match(src, "^/") then
				if rcwd == nil then
					return
				end
				rsrc = rsrc .. " " .. rcwd .. "/" .. p
		else
				rsrc = rsrc .. " " .. p
		end
	end
	return rsrc
end

function rcp(cwst, cwd, src, dst, flags, d)
	local host = cwst.ssh.h
	if host == nil then
		print("Error: missing host specification")
		return
	end

	local user = cwst.ssh.u or os.getenv("USER")

	if not ssh_init(cwst, cwd) then
		return
	end

	local err = -1
	if d == "put" then
		err = os.execute(scpcmd .. " -q " .. flags .. " -oControlPath=" ..
		    cwd ..  "/" .. ".sshsock-" .. host .. "-" .. user .. " " ..
		    src ..  " " ..  user .. "@" ..  host ..  ":" .. dst)
		    -- XXX what to do with stderr?
		    -- .. " 2>/dev/null")
		-- sometimes err is way off so try to smoothen
	elseif d == "get" then
		local rsrc = ""
		for p in string.gmatch(src, "[^%s]+") do
				rsrc = rsrc .. " " .. user .. "@" .. host .. ":"
				    .. p
		end
		err = os.execute(scpcmd .. " -q " .. flags .. " -oControlPath=" ..
		    cwd ..  "/" .. ".sshsock-" .. host .. "-" .. user .. " " ..
		    rsrc .. " " ..  dst)
		    -- XXX what to do with stderr?
		    -- .. " 2>/dev/null")
		-- sometimes err is way off so try to smoothen
	else
		return
	end
	if err ~= 0 and err < 255 then
		print("Error  executing " .. "\"" ..
		    cmdline .. "\" errcode: " .. err)
		return
	end

	return true
end

-- from luagems book
function vardump(value, depth, key)
	local linePrefix = ""
	local spaces = ""

	if key ~= nil then
		linePrefix = "["..key.."] = "
	end

	if depth == nil then
		depth = 0
	else
		depth = depth + 1
		for i=1, depth do 
			spaces = spaces .. "  " 
		end
	end

	if type(value) == 'table' then
		mTable = getmetatable(value)
		if mTable == nil then
			print(spaces ..linePrefix.."(table) ")
		else
			print(spaces .."(metatable) ")
			value = mTable
		end		
		for tableKey, tableValue in pairs(value) do
			vardump(tableValue, depth, tableKey)
		end
	elseif type(value) == 'function' or type(value) == 'thread' or 
	    type(value)	== 'userdata' or value == nil then
		print(spaces..tostring(value))
	else
		print(spaces..linePrefix.."("..type(value)..") "..
		    tostring(value))
	end
end

function getvarvalue(name)
	local value, found

	-- try local variables
	local i = 1
	while true do
		local n, v = debug.getlocal(2, i)
		if not n then break end
		if n == name then
			value = v
			found = true
		end
		i = i + 1
	end
	if found then return value end

	-- try upvalues
	local func = debug.getinfo(2).func
	i = 1
	while true do
		local n, v = debug.getupvalue(func, i)
		if not n then break end
		if n == name then
			return v
		end
		i = i + 1
	end

	-- not found; get global
	return getfenv(func)[name]
end
