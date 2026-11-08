-- Tests for lua/autorun/pterohost_netping.lua under plain LuaJIT with GMod API stubs.
-- Usage: luajit pterohost_netping.test.lua <path to pterohost_netping.lua>

local addon = assert(arg[1], "path to addon")

local pass, fail = 0, 0
local function check(name, expected, actual)
	if expected == actual then
		pass = pass + 1
		print("ok   " .. name)
	else
		fail = fail + 1
		print("FAIL " .. name .. "\n  expected: " .. tostring(expected) .. "\n  actual:   " .. tostring(actual))
	end
end

local function env(realm, opts)
	opts = opts or {}
	local E = {}
	setmetatable(E, { __index = _G })
	E.SERVER = realm == "server"
	E.CLIENT = realm == "client"
	E.FCVAR_REPLICATED, E.FCVAR_ARCHIVE = 1, 2
	E.AddCSLuaFile = function() end

	local PLAYER = {}
	PLAYER.__index = PLAYER
	PLAYER.Ping = function(self) return self.eng end
	PLAYER.IPAddress = function(self) return self.ip end
	PLAYER.UserID = function(self) return self.id end
	PLAYER.GetNW2Int = function(self, k, d) local v = self.nw[k]; if v == nil then return d end return v end
	PLAYER.SetNW2Int = function(self, k, v) self.nw[k] = v end
	E.FindMetaTable = function(n) if n == "Player" then return PLAYER end end

	local cvars = {}
	E.CreateConVar = function(name, def)
		local c = { v = opts[name] or def }
		function c:GetBool() return tonumber(self.v) ~= 0 end
		function c:GetFloat() return tonumber(self.v) end
		cvars[name] = c
		return c
	end

	local players = {}
	E.player = { GetHumans = function() return players end }

	local hooks, timers = {}, {}
	E.hook = { Add = function(ev, id, fn) hooks[ev] = fn end }
	E.timer = { Create = function(id, d, r, fn) timers[id] = fn end }

	local files = {}
	E.file = {
		Read = function(p) return files[p] end,
		Write = function(p, s) files[p] = s end,
		IsDir = function() return true end,
		CreateDir = function() end,
	}
	E.engine = { TickInterval = function() return opts.tick or (1 / 22) end }
	local clock = 1000
	E.SysTime = function() return clock end
	E.os = { time = function() return opts.now or 1700000000 end }
	E.math = setmetatable({ Round = function(x) return math.floor(x + 0.5) end }, { __index = math })
	E.table, E.string = table, string

	local chunk = assert(loadfile(addon))
	setfenv(chunk, E)
	chunk()

	local api = { E = E, PLAYER = PLAYER, files = files, hooks = hooks, timers = timers, cvars = cvars }
	function api.add(id, ip, eng)
		local p = setmetatable({ id = id, ip = ip, eng = eng, nw = {} }, PLAYER)
		players[#players + 1] = p
		return p
	end
	function api.tick(dt)
		clock = clock + dt
		if hooks.Tick then hooks.Tick() end
	end
	return api
end

local NOW = 1700000000

do
	local a = env("server", { now = NOW })
	local p = a.add(1, "203.0.113.7:27005", 100)
	local bot = a.add(2, "10.0.0.5:27005", 100)
	a.timers.pterohost_netping_io()
	check("targets: public IP written, private skipped", "203.0.113.7\n", a.files["pterohost_netping/targets.txt"])

	a.files["pterohost_netping/rtt.txt"] = "203.0.113.7 40.2 " .. NOW .. "\n"
	a.timers.pterohost_netping_io()
	a.timers.pterohost_netping_update()
	check("ICMP value wins", 40, p:Ping())
	check("engine ping still reachable", 100, p:EnginePing())
	check("overhead calibrates private-IP player", 40, bot:Ping())
end

do
	local a = env("server", { now = NOW })
	local p = a.add(1, "203.0.113.7:27005", 30)
	a.files["pterohost_netping/rtt.txt"] = "203.0.113.7 80 " .. NOW .. "\n"
	a.timers.pterohost_netping_io()
	a.timers.pterohost_netping_update()
	check("never above engine ping", 30, p:Ping())
end

do
	local a = env("server", { now = NOW })
	local p = a.add(1, "203.0.113.7:27005", 100)
	a.files["pterohost_netping/rtt.txt"] = "203.0.113.7 40 " .. (NOW - 60) .. "\n"
	a.timers.pterohost_netping_io()
	for _ = 1, 10 do a.tick(0.045) end
	a.timers.pterohost_netping_update()
	check("stale ICMP ignored, one tick subtracted", 55, p:Ping())
end

do
	local a = env("server", { now = NOW })
	local p = a.add(1, "198.51.100.1:27005", 20)
	for _ = 1, 10 do a.tick(0.045) end
	a.timers.pterohost_netping_update()
	check("floor at 5 ms", 5, p:Ping())
end

do
	local a = env("server", { now = NOW })
	local p = a.add(1, "198.51.100.1:27005", 0)
	a.timers.pterohost_netping_update()
	check("connecting player keeps engine value", 0, p:Ping())
end

do
	local a = env("server", { now = NOW, pterohost_netping = "0" })
	local p = a.add(1, "203.0.113.7:27005", 100)
	a.files["pterohost_netping/rtt.txt"] = "203.0.113.7 40 " .. NOW .. "\n"
	a.timers.pterohost_netping_io()
	a.timers.pterohost_netping_update()
	check("pterohost_netping 0 shows engine ping", 100, p:Ping())
end

do
	local a = env("server", { now = NOW })
	local p = a.add(1, "203.0.113.7:27005", 100)
	local samples = { 40, 41, 300, 39, 40 }
	for _, s in ipairs(samples) do
		a.files["pterohost_netping/rtt.txt"] = "203.0.113.7 " .. s .. " " .. NOW .. "\n"
		a.timers.pterohost_netping_io()
		a.timers.pterohost_netping_update()
	end
	check("median smooths a spike", 40, p:Ping())
end

do
	local a = env("client")
	local p = a.add(1, "", 100)
	check("client without NW value: engine ping", 100, p:Ping())
	p.nw.pth_netping = 42
	check("client with NW value", 42, p:Ping())
	check("server-only hooks not registered on client", nil, a.hooks.Tick)
end

do
	local a = env("server", { now = NOW })
	local first = a.PLAYER.Ping
	local chunk = assert(loadfile(addon))
	setfenv(chunk, a.E)
	chunk()
	local p = a.add(1, "198.51.100.1:27005", 77)
	check("reload keeps the real engine ping", 77, p:EnginePing())
	check("reload replaces Ping again", true, a.PLAYER.Ping ~= nil and first ~= nil)
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
