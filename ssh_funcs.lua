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
-- check for usable Master ssh connection
function ssh_check(cwd, host, user)
	if fs.attributes(cwd .. "/" .. ".sshsock-" .. host .. "-" .. user)
	    == nil then
		-- kill old running master sshs
		os.execute("pkill -f '" .. sshcmd .. " -Nf -M -S " .. cwd .. "/"
		    .. ".sshsock-" .. host .. "-" .. user ..  "'")
		return false
	end
	-- check if Master Process is running
	-- if not rm stale socket file
	local exitcode = os.execute(sshcmd .. " -O check -S " .. cwd .. "/" ..
	    ".sshsock-" .. host .. "-" .. user .. " " .. host ..
	    " 2>&1 | grep -q \'^Master running\'")
	if exitcode ~= 0 then
		execCMD("rm " .. cwd .. "/" .. ".sshsock-"
		    .. host .. "-" .. user)
		return false
	end
	-- check if persistant shell connection is running
	-- if not rm fds
	
	
	return true
end

function ssh_getVars(cwst, cwd)
	local cmdset = { user = "", host = "", opts = "", shell = ""}
	cmdset.cwd = cwd
	cmdset.host = cwst.ssh.h
	if cmdset.host == nil then
		print("Error: missing host specification")
		return
	end
	cmdset.opts = cwst.ssh.o or ""
	cmdset.user = cwst.ssh.u or os.getenv("USER")
	cmdset.shell = cwst.ssh.s or loginshell
	if cmdset.opts ~= "" then
		trim(cmdset.opts)
	end
	-- XXX these OPTS should be made configurable not static
	cmdset.opts = cmdset.opts .. " -oConnectTimeout=10"
	cmdset.opts = cmdset.opts .. " -oServerAliveInterval=10"
	cmdset.opts = trim(cmdset.opts)

	return cmdset
end

-- c represents the cmdset
function ssh_build_init_cmd(c)
	return  sshcmd .. " -Nf -M -S " .. c.cwd .. "/" ..
		".sshsock-" .. c.host .. "-" .. c.user
		.. " " .. c.opts .. " -l" .. c.user .. " "
		.. c.host .. " 2>&1"
end

function ssh_build_fds_cmd(c, fds)
	return  "(" .. sshcmd .. " -q " .. c.opts .. " -S " .. c.cwd .. "/"
	    .. ".sshsock-" .. c.host .. "-" .. c.user .. " -l" .. c.user .. " "
	    .. c.host ..  " " .. c.shell .. " < " .. fds.d .. "/in" ..
	    " > " ..  fds.d ..  "/out 2>&1 )&"
	    --"/out 2>/dev/null &)")
end

function ssh_check_peristant_channel(c)
	local cmd = "pgrep -f '^" .. sshcmd .. " -q " .. c.opts .. " -S "
            .. c.cwd .. "/" .. ".sshsock-" .. c.host .. "-" .. c.user .. " -l"
	    .. c.user .. " " .. c.host .. " " .. c.shell .. "'"
	local check = execCMD(cmd)
	if #check == 0 then
		return false
	end
	return check
end

--[[
set up multi-usable Master ssh connection
set up filedescriptors for stateful shell connection
--]]
function ssh_init(cwst, cwd)
	local c = ssh_getVars(cwst, cwd)

	if ssh_check(cwd, c.host, c.user) == false then
		print("Connecting to host: " .. c.host)
		local err = os.execute(ssh_build_init_cmd(c))
		if err ~= 0 then
			return
		end
	end

	if ssh_check_peristant_channel(c) then
		return true
	end

	local fds = cwst.fds
	if fds == nil then
		fds = { d = "", i = "", o = "" }
	end

	if fds.d == "" then
		fds.d = trim(execCMD("mktemp -d " .. cwd .. 
		    "/fifos.XXXXXXXXXXX"), "\n")
		os.execute("mknod " .. fds.d .. "/in p")
		os.execute("mknod " .. fds.d .. "/out p")
	end

	if io.type(fds.i) ~= "file" then
		fds.i = io.open(fds.d .. "/in", "w+")
	end
	if io.type(fds.o) ~= "file" then
		fds.o = io.open(fds.d .. "/out", "r+")
	end
	cwst.fds = fds

	fds.i:write("stty -echo \n")
	fds.i:flush()

	s.signal("SIGINT", "ignore")
	if os.execute(ssh_build_fds_cmd(c, fds)) ~= 0 then
		print("Error: could not fork persistant ssh process")
	end
	s.signal("SIGINT", "default")
	return true
end

function ssh_config_create(fd, systems, unique_host)
	for k, v in pairs(systems) do
		if type(v)  ~= "table" then
			return
		end

		if v.ssh == nil then
			if unique_host == "" then
				unique_host = k
			else
				unique_host = unique_host .. "-" .. k
			end
			ssh_config_create(fd, v, unique_host)
		else
			if unique_host == "" then
				unique_host = k
			else
				unique_host = unique_host .. "-" .. k
			end
			--XXX error checking if no hostname!
			if v.ssh.h == nil then
				print("Error: missing hostname " .. 
				    "for host: " .. unique_host)
			else
				fd:write("Host " .. unique_host .. "\n")
				fd:write("  Hostname " .. v.ssh.h .. "\n")

				user = v.ssh.u or os.getenv("USER")
				fd:write("  User " .. user .. "\n")

				fd:write("\n")

				fd:flush()
			--unique_host = string.gsub(unique_host, "\-?%w-$", "", 1)
			end
		end
		unique_host = string.gsub(unique_host, "\-?%w-$", "", 1)
	end
end

function sshfs_build_cmd(cwst, sshfs_dir, rsshfs_dir)
	local hostident = cwst.ssh.h
	local user = cwst.ssh.u or os.getenv("USER")
	local sshfs_opts = ""
	if cwst.fs ~= null then
		sshfs_opts = cwst.fs
	end
	if not rsshfs_dir then
		rsshfs_dir = "/"
	end
	local r = sshfs .. " " .. user .. "@" .. hostident .. ":" ..  rsshfs_dir
	    .. " " .. sshfs_dir .. " " .. sshfs_opts
	return r
end

function sshfs_check_dir()
	if fs.attributes(sshfs_base) == nil then
		return false
	end
	return true
end

function sshfs_check_mounts()
	local o = execCMD("mount | grep 'fuse.sshfs' | grep " .. sshfs_base)
	if string.len(o) == 0 then
		return nil
	end
	return o
end

function sshfs_mount(cws, cwst, ldir, rdir)
	local err = os.execute(sshfs_build_cmd(cwst, ldir, rdir))
	if err ~= 0 then
		print("Error: couldn't import remote fs to " .. ldir)
		return false
	end
	sshfs_mountpoints[ldir] = rdir
	return ldir
end

function sshfs_create(systems, name)
	for k, v in pairs(systems) do
		if type(v)  == "table" then
			if v.ssh == nil then
				fs.mkdir(sshfs_base .. "/" .. k)
				sshfs_create(v, k)
			end
		else
			return
		end
		fs.mkdir(sshfs_base .. "/" .. k)
		if name ~= nil then
			os.execute("mv " .. sshfs_base .. "/" .. k .. " " ..
			    sshfs_base .. "/" .. name)
		end
	end
end

function print_mounted_sshfs()
	os.execute("mount | grep 'fuse.sshfs' | grep " .. sshfs_base)
end
