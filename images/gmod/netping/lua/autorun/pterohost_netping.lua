AddCSLuaFile()

local PLAYER = FindMetaTable("Player")
if not PLAYER then return end

local enginePing = PLAYER.PterohostEnginePing or PLAYER.Ping
PLAYER.PterohostEnginePing = enginePing
PLAYER.EnginePing = enginePing

local NW_KEY = "pth_netping"
local cvEnabled = CreateConVar("pterohost_netping", "1", { FCVAR_REPLICATED }, "Show network latency instead of engine latency")

function PLAYER:Ping()
	if cvEnabled:GetBool() then
		local v = self:GetNW2Int(NW_KEY, -1)
		if v > 0 then return v end
	end
	return enginePing(self)
end

if CLIENT then return end

local cvTickFactor = CreateConVar("pterohost_netping_tickfactor", "1", { FCVAR_ARCHIVE }, "", 0, 4)
local cvIcmp = CreateConVar("pterohost_netping_icmp", "1", { FCVAR_ARCHIVE }, "", 0, 1)

local DIR = "pterohost_netping"
local TARGETS = DIR .. "/targets.txt"
local RESULTS = DIR .. "/rtt.txt"
local ICMP_TTL = 15
local OVERHEAD_TTL = 600
local FLOOR = 5
local WINDOW = 5

local icmp = {}
local history = {}
local overhead, overheadAt = nil, 0
local lastTick, tickAvg = nil, nil
local lastTargets = ""

local function median(t)
	local n = #t
	if n == 0 then return nil end
	local c = {}
	for i = 1, n do c[i] = t[i] end
	table.sort(c)
	if n % 2 == 1 then return c[(n + 1) / 2] end
	return (c[n / 2] + c[n / 2 + 1]) / 2
end

local function isPublicIPv4(ip)
	local a, b, c, d = string.match(ip or "", "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return false end
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
	if a > 255 or b > 255 or c > 255 or d > 255 then return false end
	if a == 0 or a == 10 or a == 127 or a >= 224 then return false end
	if a == 100 and b >= 64 and b <= 127 then return false end
	if a == 169 and b == 254 then return false end
	if a == 172 and b >= 16 and b <= 31 then return false end
	if a == 192 and b == 168 then return false end
	return true
end

local function playerIP(ply)
	local addr = ply:IPAddress() or ""
	return string.match(addr, "^([^:]+)") or addr
end

local function tickMs()
	if tickAvg then return tickAvg * 1000 end
	return engine.TickInterval() * 1000
end

local function readIcmp()
	local raw = file.Read(RESULTS, "DATA")
	if not raw then return end
	local now = os.time()
	for ip, rtt, ts in string.gmatch(raw, "([%d%.]+)%s+([%d%.]+)%s+(%d+)") do
		rtt, ts = tonumber(rtt), tonumber(ts)
		if rtt and ts and now - ts <= ICMP_TTL then
			icmp[ip] = { rtt = rtt, ts = ts }
		end
	end
	for ip, e in pairs(icmp) do
		if now - e.ts > ICMP_TTL then icmp[ip] = nil end
	end
end

local function writeTargets()
	local ips, seen = {}, {}
	for _, ply in ipairs(player.GetHumans()) do
		local ip = playerIP(ply)
		if isPublicIPv4(ip) and not seen[ip] then
			seen[ip] = true
			ips[#ips + 1] = ip
		end
	end
	table.sort(ips)
	local body = table.concat(ips, "\n")
	if body ~= "" then body = body .. "\n" end
	if body == "" and lastTargets == "" then return end
	lastTargets = body
	if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
	file.Write(TARGETS, body)
end

local function freshIcmp(ply)
	if not cvIcmp:GetBool() then return nil end
	local e = icmp[playerIP(ply)]
	if e and os.time() - e.ts <= ICMP_TTL then return e.rtt end
	return nil
end

local function update()
	local now = os.time()
	local samples = {}
	local raw = {}

	for _, ply in ipairs(player.GetHumans()) do
		local eng = enginePing(ply)
		if eng and eng > 0 then
			local net = freshIcmp(ply)
			raw[ply] = { eng = eng, net = net }
			if net then samples[#samples + 1] = math.max(0, eng - net) end
		end
	end

	local m = median(samples)
	if m then overhead, overheadAt = m, now end
	local useOverhead = overhead and now - overheadAt <= OVERHEAD_TTL

	for ply, r in pairs(raw) do
		local v
		if r.net then
			v = r.net
		elseif useOverhead then
			v = r.eng - overhead
		else
			v = r.eng - cvTickFactor:GetFloat() * tickMs()
		end
		v = math.min(r.eng, math.max(FLOOR, v))

		local id = ply:UserID()
		local h = history[id] or {}
		h[#h + 1] = v
		while #h > WINDOW do table.remove(h, 1) end
		history[id] = h

		local out = math.Round(median(h))
		if ply:GetNW2Int(NW_KEY, -1) ~= out then ply:SetNW2Int(NW_KEY, out) end
	end
end

hook.Add("Tick", "pterohost_netping", function()
	local now = SysTime()
	if lastTick then
		local dt = now - lastTick
		if dt > 0 and dt < 1 then
			tickAvg = tickAvg and (tickAvg * 0.99 + dt * 0.01) or dt
		end
	end
	lastTick = now
end)

hook.Add("PlayerDisconnected", "pterohost_netping", function(ply)
	history[ply:UserID()] = nil
end)

timer.Create("pterohost_netping_io", 5, 0, function()
	writeTargets()
	readIcmp()
end)

timer.Create("pterohost_netping_update", 2, 0, update)
