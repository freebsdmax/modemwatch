module("luci.controller.modemwatch", package.seeall)

local fs = require "nixio.fs"
local sys = require "luci.sys"
local http = require "luci.http"
local jsonc = require "luci.jsonc"
local i18n = require "luci.i18n"
local uci = require "luci.model.uci"
local dispatcher = require "luci.dispatcher"

local function send_json(data)
	http.prepare_content("application/json")
	http.write(jsonc.stringify(data))
end

function index()
	if not fs.access("/etc/config/modemwatch") then
		return
	end

	entry({"admin", "modem"}, firstchild(), _("Modem"), 60).dependent = false

	entry({"admin", "modem", "modemwatch"},
		template("modemwatch/status"),
		_("Modem LTE 4G"), 60).acl_depends = { "luci-app-modemwatch" }

	entry({"admin", "modem", "modemwatch", "status"},
		template("modemwatch/status"), _("Status"), 10).leaf = true

	entry({"admin", "modem", "modemwatch", "signal"},
		template("modemwatch/signal"), _("Signal"), 15).leaf = true

	entry({"admin", "modem", "modemwatch", "log"},
		template("modemwatch/log"), _("Log"), 17).leaf = true

	entry({"admin", "modem", "modemwatch", "modem_settings"},
		template("modemwatch/modem_settings"), _("Modem settings"), 20).leaf = true

	entry({"admin", "modem", "modemwatch", "network_scan"},
		template("modemwatch/network_scan"), _("Network search"), 25).leaf = true

	entry({"admin", "modem", "modemwatch", "config"},
		cbi("modemwatch/config"), _("Settings"), 30).leaf = true

	entry({"admin", "modem", "modemwatch", "status_json"},
		call("action_status")).leaf = true

	entry({"admin", "modem", "modemwatch", "signal_json"},
		call("action_signal")).leaf = true

	entry({"admin", "modem", "modemwatch", "read_config"},
		call("action_read_config")).leaf = true

	entry({"admin", "modem", "modemwatch", "at_cmd"},
		call("action_at")).leaf = true

	entry({"admin", "modem", "modemwatch", "band_info"},
		call("action_band_info")).leaf = true

	entry({"admin", "modem", "modemwatch", "band_set"},
		call("action_band_set")).leaf = true

	entry({"admin", "modem", "modemwatch", "scan_start"},
		call("action_scan_start")).leaf = true

	entry({"admin", "modem", "modemwatch", "scan_status"},
		call("action_scan_status")).leaf = true

	entry({"admin", "modem", "modemwatch", "scan_stop"},
		call("action_scan_stop")).leaf = true

	entry({"admin", "modem", "modemwatch", "mccmnc_update"},
		call("action_mccmnc_update")).leaf = true

	entry({"admin", "modem", "modemwatch", "mccmnc_status"},
		call("action_mccmnc_status")).leaf = true

	entry({"admin", "modem", "modemwatch", "operator_info"},
		call("action_operator_info")).leaf = true

	entry({"admin", "modem", "modemwatch", "scan_select"},
		call("action_scan_select")).leaf = true

	entry({"admin", "modem", "modemwatch", "check"},
		call("action_check")).leaf = true

	entry({"admin", "modem", "modemwatch", "reboot"},
		call("action_reboot")).leaf = true

	entry({"admin", "modem", "modemwatch", "restart"},
		call("action_restart")).leaf = true

	entry({"admin", "modem", "modemwatch", "modem_info"},
		call("action_modem_info")).leaf = true

	entry({"admin", "modem", "modemwatch", "logs"},
		call("action_logs")).leaf = true
end

local function read_status()
	local data = {}
	local f = io.open("/var/run/modemwatch/status", "r")
	if f then
		for line in f:lines() do
			local k, v = line:match("^([^=]+)=(.*)$")
			if k then
				data[k] = v
			end
		end
		f:close()
	end
	return data
end

local function service_running()
	local pid = fs.readfile("/var/run/modemwatch/pid")
	if pid then
		pid = pid:gsub("%s+", "")
		if pid:match("^%d+$") and sys.call("kill -0 " .. pid .. " 2>/dev/null") == 0 then
			return true
		end
	end
	return false
end

local function config_values()
	local cursor = uci.cursor()
	return cursor:get_all("modemwatch", "main") or {}
end

local function read_wan_stats()
	local cursor = uci.cursor()
	local iface = cursor:get("modemwatch", "main", "wan_iface") or "wan"
	local device = cursor:get("network", iface, "device") or iface
	local function read_bytes(path)
		local value = fs.readfile(path)
		local s = (value or ""):gsub("%s+", "")
		return tonumber(s) or 0
	end
	local rx = read_bytes("/sys/class/net/" .. device .. "/statistics/rx_bytes")
	local tx = read_bytes("/sys/class/net/" .. device .. "/statistics/tx_bytes")
	return rx, tx, device
end

local load_mccmnc
local lookup_operator_info
local format_operator

local function check_token()
	local token = http.formvalue("token")
	if not token or token ~= dispatcher.context.authtoken then
		http.status(403, "Forbidden")
		send_json({ ok = false, error = i18n.translate("invalid token") })
		return false
	end
	return true
end

function action_status()
	local data = read_status()
	data.ok = true
	data.service_running = service_running()
	data.server_time = os.time()
	data.config = config_values()
	local rx, tx, dev = read_wan_stats()
	data.wan_rx_bytes = rx
	data.wan_tx_bytes = tx
	data.wan_total_bytes = rx + tx
	if not data.wan_device or data.wan_device == "" then
		data.wan_device = dev
	end
	local op, net, country, plmn = format_operator(data.operator, data.network)
	data.operator = op
	data.network = net
	if country ~= "" then
		data.operator_country = country
	end
	if plmn ~= "" then
		data.operator_mccmnc = plmn
	end
	send_json(data)
end

function action_signal()
	local out = sys.exec("/usr/bin/modemwatch.sh signal 2>&1")
	local data = {}
	for line in (out or ""):gmatch("[^\r\n]+") do
		local k, v = line:match("^([^=]+)=(.*)$")
		if k then
			data[k] = v
		end
	end
	local cursor = uci.cursor()
	data.signal_interval = cursor:get("modemwatch", "main", "signal_interval") or "5"
	data.ok = true
	data.server_time = os.time()
	local status = read_status()
	local raw_op = data.operator or status.operator
	local op, net, country, plmn = format_operator(raw_op, data.network)
	data.operator = op
	data.network = net
	if country ~= "" then
		data.operator_country = country
	end
	if plmn ~= "" then
		data.operator_mccmnc = plmn
	end
	send_json(data)
end

local function shellquote(s)
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

function action_read_config()
	if not check_token() then
		return
	end
	local out = sys.exec("/usr/bin/modemwatch.sh read 2>&1")
	send_json({ ok = true, output = out })
end

function action_at()
	if not check_token() then
		return
	end
	local cmd = http.formvalue("cmd")
	if not cmd or cmd == "" then
		send_json({ ok = false, error = i18n.translate("empty AT command") })
		return
	end
	local out = sys.exec("/usr/bin/modemwatch.sh at " .. shellquote(cmd) .. " 2>&1")
	send_json({ ok = true, output = out })
end

local BAND_NAMES = {
	[1] = "FDD 2100 MHz", [3] = "FDD 1800 MHz", [5] = "FDD 850 MHz",
	[7] = "FDD 2600 MHz", [8] = "FDD 900 MHz", [20] = "FDD 800 MHz",
	[28] = "FDD 700 MHz", [38] = "TDD 2600 MHz", [40] = "TDD 2300 MHz",
	[41] = "TDD 2500 MHz"
}
local BAND_LIST = { 1, 3, 5, 7, 8, 20, 28, 38, 40, 41 }

local function hex_to_number(hex)
	local h = hex:gsub("^0[xX]", "")
	local n = 0
	for i = 1, #h do
		local d = tonumber(h:sub(i, i), 16)
		if not d then
			return 0
		end
		n = n * 16 + d
	end
	return n
end

local function number_to_hex(n)
	local digits = "0123456789abcdef"
	n = math.floor(n)
	if n <= 0 then
		return "0"
	end
	local out = ""
	while n > 0 do
		local d = math.floor(n % 16)
		out = digits:sub(d + 1, d + 1) .. out
		n = math.floor(n / 16)
	end
	return out
end

local function hex_to_bands(hex)
	local n = hex_to_number(hex)
	local bands = {}
	for b = 0, 52 do
		local pow = 2 ^ b
		if math.floor(n / pow) % 2 == 1 then
			bands[#bands + 1] = b + 1
		end
	end
	return bands
end

local function bands_to_hex(bands)
	local mask = 0
	for n in bands:gmatch("%d+") do
		local b = tonumber(n)
		if b and b >= 1 and b <= 53 then
			mask = mask + 2 ^ (b - 1)
		end
	end
	return "0x" .. number_to_hex(mask)
end

function action_band_info()
	local out = sys.exec("/usr/bin/modemwatch.sh at " .. shellquote('AT+QCFG="band"') .. " 2>&1")
	local lte_hex
	local _, second = out:match("(0x[0-9a-fA-F]+)%s*,%s*(0x[0-9a-fA-F]+)")
	lte_hex = second or out:match("(0x[0-9a-fA-F]+)")
	local supported = {}
	for _, b in ipairs(BAND_LIST) do
		supported[#supported + 1] = { band = b, txt = BAND_NAMES[b] or "" }
	end
	local enabled = lte_hex and hex_to_bands(lte_hex) or {}
	send_json({
		ok = true,
		modem = "Quectel EC200A",
		supported = supported,
		enabled = enabled,
		raw = out
	})
end

function action_band_set()
	if not check_token() then
		return
	end
	local bands = http.formvalue("bands")
	if not bands or (bands ~= "default" and not bands:match("^[0-9 ]+$")) then
		send_json({ ok = false, error = i18n.translate("invalid band selection") })
		return
	end
	if bands == "default" then
		bands = "1 3 5 7 8 20 28 38 40 41"
	end
	local hex = bands_to_hex(bands)
	local out1 = sys.exec("/usr/bin/modemwatch.sh at " .. shellquote('AT+QCFG="band",0,' .. hex) .. " 2>&1")
	local out2 = sys.exec("/usr/bin/modemwatch.sh at " .. shellquote("AT&W") .. " 2>&1")
	send_json({
		ok = true,
		output = out1 .. out2,
		message = i18n.translate("Band settings sent")
	})
end

function action_scan_start()
	if not check_token() then
		return
	end
	sys.exec("setsid /usr/bin/modemwatch.sh scan >/dev/null 2>&1 &")
	send_json({ ok = true, message = i18n.translate("network scan started") })
end

function action_scan_stop()
	if not check_token() then
		return
	end
	sys.exec("/usr/bin/modemwatch.sh scan_stop >/dev/null 2>&1")
	send_json({ ok = true, message = i18n.translate("network scan stopped") })
end

local function read_kv(path)
	local data = {}
	local f = io.open(path, "r")
	if f then
		for line in f:lines() do
			local k, v = line:match("^([^=]+)=(.*)$")
			if k then
				data[k] = v
			end
		end
		f:close()
	end
	return data
end

local function read_scan_kv()
	return read_kv("/var/run/modemwatch/scan_status")
end

load_mccmnc = function()
	local map = {}
	local f = io.open("/usr/share/modemwatch/mccmnc.dat", "r")
	if f then
		for line in f:lines() do
			local plmn, country, name = line:match("^(%d+);([^;]*);(.*)$")
			if plmn and name then
				country = country:gsub("[\r\n]+$", "")
				name = name:gsub("[\r\n]+$", "")
				if name ~= "" then
					map[plmn] = { country = country, name = name }
				end
			end
		end
		f:close()
	end
	return map
end

lookup_operator_info = function(raw)
	if not raw or raw == "" then
		return raw, "", ""
	end
	local plmn = raw:match("^(%d+)$")
	if not plmn then
		return raw, "", ""
	end
	local entry = load_mccmnc()[plmn]
	if entry then
		return entry.name, entry.country, plmn
	end
	return raw, "", plmn
end

format_operator = function(raw, network)
	local name, country, plmn = lookup_operator_info(raw)
	local net = network or ""
	if plmn == "" then
		local code = net:match("(%d%d%d%d%d%d?)$")
		if code then
			plmn = code
		end
	end
	if plmn ~= "" then
		net = net:gsub("%s+" .. plmn .. "$", "")
		if name == "" or name:match("^%d+$") then
			name = raw or plmn
		end
		return name .. " (" .. plmn .. ")", net, country, plmn
	end
	return name, net, country, plmn
end

local function parse_operators(raw)
	local ops = {}
	local db = load_mccmnc()
	for status, long, short, mccmnc, act in raw:gmatch('%((%d+),"([^"]*)","([^"]*)","(%d+)",(%d+)%)') do
		local tech = "?"
		local a = tonumber(act)
		if a == 7 then
			tech = "LTE"
		elseif a == 2 or a == 4 or a == 5 or a == 6 then
			tech = "3G"
		elseif a == 0 or a == 3 then
			tech = "2G"
		elseif a == 11 then
			tech = "5G"
		end
		local st = "unknown"
		local sn = tonumber(status)
		if sn == 1 then
			st = "available"
		elseif sn == 2 then
			st = "current"
		elseif sn == 3 then
			st = "forbidden"
		end
		local entry = db[mccmnc]
		local name = (long ~= "" and long or short)
		if (name == "" or name:match("^%d+$")) and entry then
			name = entry.name
		end
		ops[#ops + 1] = {
			status = st,
			name = name,
			short = short,
			mccmnc = mccmnc,
			tech = tech,
			act = act,
			country = entry and entry.country or "",
			db_name = entry and entry.name or ""
		}
	end
	return ops
end

function action_scan_status()
	local st = read_scan_kv()
	local raw = ""
	local f = io.open("/var/run/modemwatch/scan_result", "r")
	if f then
		raw = f:read("*a") or ""
		f:close()
	end
	send_json({
		ok = true,
		state = st.state or "idle",
		started = st.started,
		finished = st.finished,
		error = st.error,
		operators = parse_operators(raw),
		raw = raw
	})
end

function action_operator_info()
	local mccmnc = http.formvalue("mccmnc")
	if not mccmnc or not mccmnc:match("^%d+$") then
		send_json({ ok = false, error = i18n.translate("invalid operator") })
		return
	end
	local name, country, plmn = lookup_operator_info(mccmnc)
	send_json({
		ok = true,
		name = name,
		country = country,
		mccmnc = (plmn ~= "" and plmn or mccmnc)
	})
end

function action_mccmnc_status()
	local st = read_kv("/tmp/modemwatch/mccmnc_status")
	local state = st.state or "idle"
	local msg = st.message or ""
	if state == "downloading" then
		msg = i18n.translate("Downloading MCC/MNC list")
	elseif state == "parsing" then
		msg = i18n.translate("Parsing MCC/MNC list")
	elseif state == "done" then
		msg = i18n.translate("MCC/MNC database updated") .. " (" .. tostring(st.count or "0") .. ")"
	elseif state == "error" then
		msg = i18n.translate("Failed to update MCC/MNC database") .. ": " .. msg
	end
	send_json({
		ok = true,
		state = state,
		message = msg,
		count = tonumber(st.count) or 0,
		timestamp = tonumber(st.timestamp) or 0
	})
end

function action_mccmnc_update()
	if not check_token() then
		return
	end
	local st = read_kv("/tmp/modemwatch/mccmnc_status")
	if st.state == "downloading" or st.state == "parsing" then
		send_json({ ok = false, error = i18n.translate("MCC/MNC update already running") })
		return
	end
	sys.exec("setsid lua /usr/lib/modemwatch/mccmnc_update.lua >/dev/null 2>&1 &")
	send_json({ ok = true, message = i18n.translate("MCC/MNC update started") })
end

function action_scan_select()
	if not check_token() then
		return
	end
	local mode = http.formvalue("mode")
	local mccmnc = http.formvalue("mccmnc")
	local cmd
	if mode == "auto" then
		cmd = "AT+COPS=0"
	else
		if not mccmnc or not mccmnc:match("^%d+$") then
			send_json({ ok = false, error = i18n.translate("invalid operator") })
			return
		end
		cmd = 'AT+COPS=1,2,"' .. mccmnc .. '"'
	end
	local out = sys.exec("/usr/bin/modemwatch.sh at " .. shellquote(cmd) .. " 2>&1")
	send_json({ ok = true, output = out, message = i18n.translate("operator selection sent") })
end

function action_check()
	if not check_token() then
		return
	end
	sys.exec("nohup /usr/bin/modemwatch.sh check --fast >/dev/null 2>&1 &")
	send_json({ ok = true, message = i18n.translate("internet check started") })
end

function action_reboot()
	if not check_token() then
		return
	end
	sys.exec("nohup /usr/bin/modemwatch.sh reboot >/dev/null 2>&1 &")
	send_json({ ok = true, message = i18n.translate("modem reboot started") })
end

function action_restart()
	if not check_token() then
		return
	end
	sys.exec("/etc/init.d/modemwatch restart >/dev/null 2>&1")
	send_json({ ok = true, message = i18n.translate("service restarted") })
end

function action_modem_info()
	if not check_token() then
		return
	end
	sys.exec("/usr/bin/modemwatch.sh info --force >/dev/null 2>&1")
	local data = read_status()
	data.ok = true
	data.server_time = os.time()
	if data.modem_info_ok == "1" then
		data.message = i18n.translate("Modem info updated")
	else
		data.message = i18n.translate("Modem did not respond")
	end
	send_json(data)
end

function action_logs()
	local lines = tonumber(http.formvalue("lines")) or 200
	if lines < 10 then lines = 10 end
	if lines > 1000 then lines = 1000 end

	local out = sys.exec("tail -n " .. lines .. " /var/log/modemwatch.log 2>/dev/null")
	if not out or out == "" then
		out = sys.exec("logread -e modemwatch 2>/dev/null | tail -n " .. lines)
	end

	http.prepare_content("text/plain")
	http.write(out or "")
end
