--#!/usr/bin/lua
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
--[[ 

  main data structure

cwst - table: hold remote system information

cwst.uniqueName - string: unique name for remote system with underscores (e.g.
                  fernuni_www)

cwst.mounts - table: key: local-mountpath value: remote-path

cwst.ssh - table: ssh specific options
cwst.ssh.h - string: hostname
cwst.ssh.u - string: username
cwst.ssh.o - string: options
cwst.ssh.s - string: login shell

cwst.fds - table: filedescriptors for persistant ssh (named pipes)
cwst.fds.i - fds: input fds
cwst.fds.o - fds: output fds

--]]

-- global vars
lcmds = {
	exit = "exit fsbash",
	help = "show help menu",
	i = "interactive ssh login",
	c = "close Connection",
	ca = "close all connections",
	fs = "change working directory to sshfs path",
	--import = "import a name space from a remote system",
	lpwd = "get local working directory",
	lcd = "change local working directory",
	lls = "list local dir contents",
	lmount = "mount directory from remote system",
	lumount = "unmount directory from remote system",
	luadump = "dump internal data (only for debugging)",
	--XXX reactivate if needed but obsolute after sshfs introduced
	--mput = "upload files to remote host",
	--XXX reactivate if needed but obsolute after sshfs introduced
	--mget = "copy remote files to local host",
	sc = "show initial ssh connection parameters (only for debugging)",
	configreload = "reload config and regenerate sys/sshfs-directories",
}

function showhelp()
	print("[command]\t\t[description]")
	local h = {}
	for k, v in pairs(lcmds) do
		h[#h + 1] = k
	end
	table.sort(h)
	for i, n in pairs(h) do
		if (string.len(n) < 8) then
			print(n .. "\t\t" .. lcmds[n])
		elseif (string.len(n) < 16) then
			print(n .. "\t" .. lcmds[n])
		else
			print(n .. " " .. lcmds[n])
		end
	end
end

function openconf()
	rs = {}
	local home = execCMD("echo -n $HOME")
	-- change to inital path so dofile("file") works within the config
	ocwd = fs.currentdir()
	r, errstr = fs.chdir(initial_path)
	if r ~= true then
		print("\"" .. initial_path .. "\" - No such directory")
		print("Error: could not initialize config settings")
		return false
	end
	local sysconf = "fsbash.conf"
	if fs.attributes(initial_path .. "/." .. sysconf) ~= nil then
		fsbaconf = initial_path .. "/." .. sysconf
	elseif fs.attributes(initial_path .. "/" .. sysconf) ~= nil then
		fsbaconf = initial_path .. "/" .. sysconf
	elseif fs.attributes(home .. "/." .. sysconf) ~= nil then
		fsbaconf = home .. "/." .. sysconf
	elseif fs.attributes(home .. "/" .. sysconf) ~= nil then
		fsbaconf = home .. "/" .. sysconf
	elseif fs.attributes("/etc/" .. sysconf) ~= nil then
		fsbaconf = "/etc/" .. sysconf
	else
		print("Error: no configuration file (" .. sysconf .. ") found")
		os.exit(-1)
	end
	dofile(fsbaconf)
	fs.chdir(ocwd)
	systemfs = string.gsub(systemfs, "^~", os.getenv("HOME"))
	sshfs_base = string.gsub(sshfs_base, "^~", os.getenv("HOME"))
	-- zap trailing slashes
	systemfs = string.gsub(systemfs,"/$", "")
	sshfs_base = string.gsub(sshfs_base,"/$", "")
	return true
end

function execCMD(cmd)
	local f = io.popen(cmd)		-- runs command
	local o = f:read("*a")		-- read output of command

	f:close()
	return o
end

function execTEST(cmd)
	local f = io.popen(cmd)		-- runs command
	f:close()
end

function rexec(cwst, cwd, cmdline)
	local host = cwst.ssh.h
	if host == nil then
		print("Error: missing host specification")
		return
	end
	local opts = cwst.ssh.o or ""
	if opts ~= "" then
		trim(opts)
	end
	local user = cwst.ssh.u or os.getenv("USER")

	if not ssh_init(cwst, cwd) then
		return
	end
	return os.execute(sshcmd .. " -qt " .. opts .. " -S " .. cwd .. "/"
	    .. ".sshsock-" .. host .. "-" .. user .. " -l" .. user .. " "
	    .. host ..  " " .. cmdline)
	    -- XXX what to do with stderr?
	    -- .. " 2>/dev/null")
end

function genRemoteCMD(cwst, cmdline, spath)
	local host = cwst.ssh.h
	if host == nil then
		print("Error: missing host specification")
		return
	end
	local opts = cwst.ssh.o or ""
	if opts ~= "" then
		trim(opts)
	end
	local user = cwst.ssh.u or os.getenv("USER")

	return sshcmd .. " -tq " .. opts .. " -S " .. spath ..  ".sshsock-" 
	    .. host .. "-" .. user ..  "  -l" .. user .. " " .. host ..  " " 
	    .. cmdline
end

-- execute remote command and return nil in case of error
function pers_rexec(cwst, cmdline)
	local cmd = cmdline .. " 2>&1; echo DONE;"
	local output = ""
	local cwd = fs.currentdir()

	local fds = cwst.fds
	
	if not ssh_check_peristant_channel(ssh_getVars(cwst, cwd)) then
		print("Error: Persistant shell disconnected. Loosing state!")
		print("Reconnecting...")
		local err = os.execute(
		    ssh_build_fds_cmd(ssh_getVars(cwst, cwd), fds))
		if err ~= 0 then
			print("Error: no persistant shell connected")
			closeCON(cwst, cwd)
			return
		end
	end

	if fds == nil or fs.attributes(fds.d) == nil then
		print("Error: No fds connected")
		closeCON(cwst, cwd)
		return
	end

	--check if both files are named pipes
	local fattrib = lfs.attributes(fds.d .. "/in")
	if (fattrib == nil or fattrib.mode ~= "named pipe") then
		print("Error: write fd not hooked to named pipe.")
		closeCON(cwst, cwd)
		return
	end
	fattrib = lfs.attributes(fds.d .. "/out")
	if (fattrib == nil or fattrib.mode ~= "named pipe") then
		print("Error: read fd not hooked to named pipe.")
		closeCON(cwst, cwd)
		return
	end

	-- connect fds to named pipes
	if io.type(fds.i) ~= "file" then
		fds.i = assert(io.open(fds.d .. "/in", "w+"))
	end
	if io.type(fds.o) ~= "file" then
		fds.o = assert(io.open(fds.d .. "/out", "r+"))
	end

	fds.i:write(cmd .. "\n")
	fds.i:flush()

	while true do
		local line = fds.o:read("*l")
		if line == nil then 
			-- XXX do the reaper
			print("EPIPE: End of pipe.. exiting")
			os.exit(1)
		elseif string.match(line, "^DONE") ~= nil then
			break
		--elseif string.match(line, "echo DONE") ~= nil then
			-- XXX just ignore this line since its the cmd echoed
			-- by the executing shell
		else
			--io.write(line, "\n")
			output = output .. line .. "\n"
		end
	end

	return output
end

function sysfs_check()
	if fs.attributes(systemfs) == nil then
		return false
	end
	return true
end

function sysfs_create(systems, name)
	for k, v in pairs(systems) do
		if type(v)  == "table" then
			if v.ssh == nil then
				fs.mkdir(systemfs .. "/" .. k)
				sysfs_create(v, k)
			end
		else
			return
		end
		fs.mkdir(systemfs .. "/" .. k)
		if name ~= nil then
			os.execute("mv " .. systemfs .. "/" .. k .. " " ..
			    systemfs .. "/" .. name)
		end
	end
end

function getCWS(sys, dir, abspname)
		local s
		if abspname == nil then
			abspname = ""
		end
		--XXX find better solution?
		if string.match(dir, "^" .. systemfs) ~= nil then
			dir = string.gsub(dir, systemfs, "", 1)
			if dir == "" then
				return
			end
		end

		if string.match(dir, "^/") then
			if dir == "/" then
				return
			else
				s = string.match(dir, "[%w-_. ]+", 2)
			end
		else
			s = dir
		end

		if abspname == "" then
			abspname = s
		else
			abspname = abspname .. "_" .. s
		end

		-- cut dir off by one hierachy level
		local nextd = string.gsub(dir, "^/[%w-_. ]+", "", 1)

		if s == "" then
			return
		end

		if sys[s] ~= nil then
			sys[s].uniqueName = abspname
			if sys[s].ssh ~= nil then
				return s, sys[s]
			end
		else
			return
		end

		if nextd ~= "" then
			return getCWS(sys[s], nextd, abspname)
		end
end

function closeCON(cwst, cwd)
	local user = cwst.ssh.u or os.getenv("USER")
	os.execute("pkill -f '" .. sshcmd .. " -Nf -M -S " .. cwd .. "/"
	    .. ".sshsock-" .. cwst.ssh.h .. "-" .. user .. "'")
	print("Closed connection to: " .. cwst.ssh.h)
	if fds then
		cwst.fds.i:close()
		cwst.fds.o:close()
		os.execute("rm -rf " .. cwst.fds.d)
		cwst.fds = nil
	end
	os.execute("rm -f " .. cwd .. "/" .. ".sshsock-" .. cwst.ssh.h .. 
	    "-" .. user)
	fs.chdir(systemfs)
end

function closeALL()
	--umount all registered mount points
	for k in pairs(sshfs_mountpoints) do
		os.execute("fusermount -zu " .. k)
	end
	-- XXX this is very cruel since we could have non fsba processes with
	-- this signature - store ssh PIDs in cwst?
	-- kill old running master sshs
	os.execute("pkill -f '" .. sshcmd .. " -Nf -M -S'")
	os.execute("find " .. systemfs .. 
	    " -type d -name 'fifos*' | xargs rm -rf")
	os.execute("find " .. systemfs .. 
	    " -type f -name '.sshsock-*' | xargs rm -f")
	fs.chdir(systemfs)
end

function check_cmdline(cmdline, cwst, cwd)
	local name

	--check table for cmdline entry 
	if lcmds[cmdline] == nil then
		return -1
	end

	if cwst ~= nil then
		name = cwst.ssh.h
	end
	if cmdline == "exit" then
		-- XXX 
		closeALL()
		os.exit(0)
		return true
	elseif cmdline == "help" then
		showhelp()
		return true
	elseif cmdline == "lcd" then
		r, errstr = fs.chdir(systemfs)
		if r ~= true then
			print("\"" .. npath .. "\" - No such directory")
			return false
		end
		return true
	elseif cmdline == "sc" then
		if cwst then
			local c = ssh_getVars(cwst, cwd)
			print(ssh_build_init_cmd(c))
			print(ssh_build_fds_cmd(c, cwst.fds))
		end
		return true
	elseif cmdline == "c" then
		if name ~= nil and cwd ~= nil then
			closeCON(cwst, cwd)
		else
			print("Error: no CWS in path to close")
			return false
		end
		return true
	elseif cmdline == "ca" then
		closeALL()
		return true
	elseif cmdline == "lpwd" then
		os.execute("pwd")
		return true
	--interactive login
	elseif cmdline == "i" then
		if cwst ~= nil then
			rexec(cwst, cwd, "")
		else
			print("No CWS selected for interactive login")
		end
		return true
	elseif cmdline == "configreload" then
		-- check if there are sshfs-dirs mounted by the user
		local o = sshfs_check_mounts()
		if o ~= nil then
			print("Error: the following remote filesystems are "
			    .. "still mounted:")
			print(o)
			print("Please unmount before reinitializing config!")
			return false
		end
		--reinit config file vars
		if not openconf() then
			return false
		end
		fs.chdir(os.getenv("HOME"))
		os.execute("rm -rf " .. sshfs_base)
		if os.execute("mkdir -p " .. sshfs_base) ~= 0 then
			print("Unable to create sshfs direcotry: " ..
			    sshfs_base)
			--XXX bail out here?
			-- os.exit(1)
		end
		sshfs_create(rs)

		os.execute("rm -rf " .. systemfs)
		if os.execute("mkdir -p " .. systemfs) ~= 0 then
			print("Unable to create systemfs direcotry: " ..
			    systemfs)
			--XXX bail out here?
			-- os.exit(1)
		end
		sysfs_create(rs)
		fs.chdir(systemfs)

		--regenerate ssh_config
		ssh_config = systemfs .. "/.ssh_config"
		local fd = assert(io.open(ssh_config, "w+"))
		ssh_config_create(fd, rs, "")
		fd:close()
		return true
	--cmdline registered but not treated here
	else
		return -1
	end
end

function check_cmd(cmd, cmdline, cws, cwst)
	if lcmds[cmd] == nil then
		return -1
	end
	if cmd == "lcd" then
		-- XXX code duplication move to function?
		local dir = string.gsub(cmdline,
		    "^.*[%s]+([^%s]+)[%s]*$", "%1", 1)
		local r = normalizepath(dir)
		local npath = ""
		for k, v in ipairs(r) do
			--npath = npath .. "/" .. v
			npath = npath .. v
		end
		-- XXX should we check for ncws and init ssh here also?
		local r, errstr = fs.chdir(npath)
		if r ~= true then
			print("\"" .. npath .. "\" - No such directory")
			return false
		end
		return true
	elseif cmd == "fs" then
		local fsdir
		if not cwst then
			fsdir = sshfs_base
		else
			local syspath = string.gsub(cwst.uniqueName, 
			    '_', '/')
			fsdir = sshfs_base .. "/" .. syspath
		end
		local r, errstr = fs.chdir(fsdir)
		if r ~= true then
			print("\"" .. fsdir .. "\" - No such directory")
			return false
		end
		return true
	elseif cmd == "lls" then
		local op = string.gsub(cmdline, "^lls[%s]*", "")
		if op == "" then
			os.execute("ls")
		else
			os.execute("ls " .. op)
		end
		return true
	elseif cmd == "mput" or cmd == "mget" then
		-- -p for preserve rights -r recursive
		local flags = ""
		local ret
		cmdline, ret = string.gsub(cmdline, "[%s]+-h[%s]*", " ")
		if ret ~= 0 then
			print(cmd .. " [-h] [-p] [-r] src ... dst")
			return true
		end
		cmdline, ret = string.gsub(cmdline, "[%s]+-p[%s]+", " ")
		if ret ~= 0 then
			flags = flags .. " -p "
		end
		cmdline, ret = string.gsub(cmdline, "[%s]+-r[%s]+", " ")
		if ret ~= 0 then
			flags = flags .. " -r "
		end
		cmdline = string.gsub(cmdline, "^" .. cmd, "")
		local src = trim(string.gsub(cmdline, "[^%s]+$", ""), "%s")
		local dst = "."
		if string.match(src, "^[%s]*$") then
			src = trim(string.match(cmdline, "[^%s]+$"))
		else
			dst = trim(string.match(cmdline, "[^%s]+$"))
		end
		if not src or not dst then
			print("usage: " .. cmd .. " src ... dst")
			return false
		end

		if cmd == "mput" then
			-- no absoulte path in src -> add cwd
			if not string.match(src, "^/") then
				local cwd = fs.currentdir()
				src = cwd .. "/" .. src
			end
			local ndst = mput(cwst, dst)
			if ndst == nil then
				print("Error: no file found for: "
				    .. dst)
				return
			end
			rcp(cwst, cwd, src, ndst, flags, "put")
		elseif cmd == "mget" then
			local nsrc = mget(cwst, src)
			if nsrc == nil then
				print("Error: no file found for: "
				     .. src)
				return
			end
			rcp(cwst, cwd, nsrc, dst, flags, "get")
		end
		return true
	elseif cmd == "lmount" then
		if cmdline == "lmount" then
			--XXX option to show only specific mountpoints?
			--XXX should we show the mounted sshfses?
			--print("Directory not a system path")
			--XXX only print fuse.sshfes mounted by luash
			print_mounted_sshfs()
			return false
		end
		local s = split(cmdline, "%s")
		local rdir
		if not s[2] then
			print("Error: missing remote mount path definition")
			return false
		end
		local path = s[2]
		local rpath, spath, syspath
		if cwst == nil then
			local path_t = normalizepath(path)
			local bp = ""
			for k,v in ipairs(path_t) do
				bp = bp .. v
			end
			cws, cwst = getCWS(rs, bp)

			if cwst ~= nil then
				syspath = string.gsub(cwst.uniqueName, '_', '/')
				spath = systemfs .. "/" .. syspath
				rpath = string.gsub(bp, "^" .. spath .. "/", "")
			else
				print("Error: not a remote directory: " .. path)
				return false
			end
		-- absolute path
		elseif string.match(path, '^/') then
			rpath = path
		else
			rpath = getrcwd(cwst) .. "/" .. path
		end

		syspath = string.gsub(cwst.uniqueName, '_', '/')
		local ldir = sshfs_base .. "/" .. syspath

		if not s[3] then
			if rpath ~= "/" then
				-- use last part of rpath as local mount dir
				local d = split(rpath, "/")
				ldir = ldir .. "/" ..  d[#d]
			else
				ldir = ldir .. "/all"
			end
		elseif string.match(s[3], "^/") then
			ldir = s[3]
		else
			ldir = ldir .. "/" .. s[3]
		end

		if cws then
			if fs.attributes(ldir) == nil then
				local ret = fs.mkdir(ldir)
				if not ret then
					print("Unable to create local "
					.. "direcotry: " ..  ldir)
					return false
				end
			end
			    
			if not sshfs_mount(cws, cwst, ldir, rpath) then
				return false
			else
				print("Mounted remotedir: " .. rpath .. 
				    " locally to: " .. ldir)
			end
		else
			print("Error: " .. cwd .. " not a system "
			    .. "directory")
		end
--[[
			--XXX should we change to the mounted dir?
			local r, errstr = fs.chdir(sshfs_dir)
			if r ~= true then
				print("\"" .. sshfs_dir .. 
				    "\" - No such directory")
				return false
			end
--]]
			return true
	elseif cmd == "lumount" then
		--XXX should we show the dirs that could be unmounted?
		if cmdline == "lumount" then
			--XXX only print fuse.sshfes mounted by luash
			print_mounted_sshfs()
			return true
		end
		local ldir = string.gsub(cmdline,
		    "^%s*" .. cmd .. "[%s]+([^%s]+)[%s]*$", "%1", 1)

		if os.execute("fusermount -zu " .. ldir) ~= 0 then
			print("Error: unable to unmount: " .. ldir)
			return false
		end

		sshfs_mountpoints[ldir] = nil
		local ret = fs.rmdir(ldir)
		if not ret then
			print("Error: Could not remove local "
			    .. "mount directory: " .. ldir)
			return false
		end
		return true
	-- the printout will be delayed until shortly before cmd exec in main
	elseif cmd == "luadump" then
		local depth = nil
		local s = split(cmdline, "%s")
		if s[3] ~= nil then
			depth = tonumber(s[3])
		end
		vardump(getvarvalue(s[2], depth))
		return true
	-- cmd registered but not treated try to exec later
	else
		return -1
	end
end

-- transform cmds like /systemfs/host/ls to according remote cmds
function cmdlineSub(cmdline)
	local cmds = split(cmdline, "|")

	for k,cmd in ipairs(cmds) do
		cmd = trim(cmd)
		local path = string.match(cmd, "^[^%s]*")
		local dir = string.match(path, "^(.*)/")
		if dir ~= nil then
			local cws, cwst
			local path_t = normalizepath(path)
			local bp = ""
			--[[for k,v in ipairs(path_t) do
				-- no slash in the end
				if k == #path_t then
					bp = bp .. v
				else
					bp = bp .. v .. "/"
				end
			end--]]
			for k,v in ipairs(path_t) do
				bp = bp .. v
			end
			cws, cwst = getCWS(rs, bp)

			if cwst ~= nil then
				cmd = string.gsub(cmd, "^[^%s]*", bp)
				local syspath = string.gsub(cwst.uniqueName, 
				    '_', '/') .. "/"
				local spath = systemfs .. "/" .. syspath
				local rcmd = ""
				if (string.match(cmd, '^/')) then
					rcmd = string.gsub(cmd, spath, "")
				else
					rcmd = string.gsub(cmd, syspath, "")
				end

				cmds[k] =  genRemoteCMD(cwst, rcmd, spath)
			end
		end
	end
	local final_cmdline = ""
	for k,cmd in ipairs(cmds) do
		final_cmdline = final_cmdline .. cmd
		if k < #cmds then
			final_cmdline = final_cmdline .. " | "
		end
	end
	return final_cmdline
end

function mainLoop()
	local cwd = fs.currentdir()
	-- cws is the name of the current working system (string)
	-- cwst is the table connected to the name in the config file (table)
	local cws, cwst = getCWS(rs, cwd)
	local user

	if cwst ~= nil then
		user = cwst.ssh.u or os.getenv("USER")
	end

	-- don't print promt
	if not ppromt then
		-- noop
	-- print remote promt
	elseif cws ~= nil then
		local rcwd = getrcwd(cwst)
		if rcwd ~= nil then
			local p = string.match(rcwd, "[^/]+$") or "/"
			
			io.write("fsbash:" .. user .. "@" .. cws .. ":" ..
			    p .. "$ ")
		else
			--io.write("fsbash:" .. user .. "@" .. cws .. "$ ")
			return false
		end
	-- print local promt
	else
		io.write("fsbash# ")
	end

	s.signal("SIGINT", "ignore")
	local cmdline = io.read()
	s.signal("SIGINT", "default")

	-- no more input coming from inputstream
	if cmdline == nil then
		os.exit()
	end

	-- zap whiteos
	cmdline = trim(cmdline)
	-- don't allow empty lines (e.g. on CTRL-C)
	if cmdline == "" and ppromt then
		return false
	elseif  cmdline == "" and ppromt == 0 then

	end

	-- check if complete cmdline registered 
	-- as local command
	local c = check_cmdline(cmdline, cwst, cwd)
	if c ~= -1 then
		return c
	end

	-- check if cmd is registered  as local cmd
	local cmd = string.match(cmdline, "^%a+")	-- get argv[0] aka cmd
	local c =  check_cmd(cmd, cmdline, cws, cwst)
	if c ~= -1 then
		return c
	end
	if cmdline == "pwd" then
		if cwst ~= nil then
			--remote exec
			io.write(pers_rexec(cwst, cmdline) or "\n")
		else
			io.write(cwd, "\n")
		end
	elseif cmd == "cd" then
		--on single cd jump to homedir in case of remote and to systemfs
		--in case of local execution
		if cmdline == "cd" and not cwst then
			local r, errstr = fs.chdir(systemfs)
			if r ~= true then
				print("\"" .. npath .. "\" - No such directory")
				return false
			end
			return true
		end

		local dir = string.gsub(cmdline, "^.*[%s]+([^%s]+)[%s]*$",
		    "%1", 1)
		
		local r = normalizepath(dir)
		local npath = ""
		for k, v in ipairs(r) do
			--npath = npath .. "/" .. v
			npath = npath .. v
		end

		if npath == "" then
			npath = "/"
		end

		local ncws, ncwst = getCWS(rs, npath)
		local nname = ""
		if ncwst ~= nil then
			nname = ncwst.ssh.h
		end

		if cwst ~= nil then
			-- remote exec
			io.write(pers_rexec(cwst, cmdline) or "\n")
		elseif ncws == nil then
			-- local execution
			local r, errstr = fs.chdir(npath)
			if r ~= true then
				print("\"" .. npath .. "\" - No such directory")
				return false
			end
--[[
		-- we need to setup ssh path
		elseif cws == nil then
			ssh_init(ncwst, npath)
			local r, errstr = fs.chdir(npath)
			if r ~= true then
				print("\"" .. npath .. "\" - No such directory")
				return false
			end
--]]
		elseif ncws ~= nil then
			local r, errstr = fs.chdir(npath)
			if r ~= true then
				print("\"" .. npath .. "\" - No such directory")
				return false
			end
			cwd = fs.currentdir()
			if not ssh_init(ncwst, cwd) then
				return false
			end
		elseif cws ~= nil then
			print("Error: " .. cmdline .. " not jet supported")
			return false
		end
		return true
	elseif cws ~= nil then
		cmdline = "'" .. cmdline .. "'"
		rexec(cwst, cwd, cmdline)
	else
		cmdline = cmdlineSub(cmdline)
		--XXX errorhandling
		os.execute(cmdline)
	end
	return true
end

-- global variables
fs = require("lfs")
s = require("signal")
fsba = require("fsba")
rs = nil
ppromt = true
-- debug table
d = {}
-- table where sshfs mounts get registered
sshfs_mountpoints = {}

-- read config file
initial_path = fs.currentdir()
openconf()

dofile("fsbautil.lua")
dofile("ssh_funcs.lua")

-- check if we were called with a file argument on the command line
local temp
if #arg == 1 then
	local file = arg[1]
	--no absoulte pathname given
	if string.match(file, "^/") == nil then
		local dir = fs.currentdir()
		file = dir .. "/" .. file
	end
	local attr = fs.attributes(file)
		if attr  ~= nil then
		if attr.mode == "file" then
			temp = io.input()   -- save current input 
			io.input(file)    -- open new current file
		else
			print("Error: " .. file .. ": not a regular file")
			return 1
		end
	else
		print("Error: " .. file .. ": file not found")
		return 1
	end
	ppromt = false
end

--XXX this should get integrated into sysfs path
if sshfs_check_dir() == false then
	if os.execute("mkdir -p " .. sshfs_base) ~= 0 then
		print("Unable to create sshfs direcotry: " ..
		    sshfs_base)
		--XXX bail out here?
		-- os.exit(1)
	end
	fs.chdir(sshfs_base)
	sshfs_create(rs)
end

--XXX should we always create process local vfs to imitate private namespaces?
-- populate virtual filesystems
if sysfs_check() == false then
	if os.execute("mkdir -p " .. systemfs) ~= 0 then
		print("Unable to create systemfs direcotry: " ..
		    systemfs)
		--XXX bail out here?
		-- os.exit(1)
	end
	fs.chdir(systemfs)
	sysfs_create(rs)
else
	fs.chdir(systemfs)
end

ssh_config = systemfs .. "/.ssh_config"
local fd = assert(io.open(ssh_config, "w+"))
ssh_config_create(fd, rs, "")
fd:close()

if fsba.isatty(io.stdin) == 0 then
	ppromt = false
end

while 1 do
	mainLoop()
end
io.input():close()        -- close current file
io.input(temp)            -- restore previous current file
