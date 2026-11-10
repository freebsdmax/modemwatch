#!/usr/bin/lua
-- Update the MCC/MNC database from the Wikipedia-derived list.
-- Source: https://github.com/pbakondy/mcc-mnc-list (MIT)

local jsonc = require "luci.jsonc"
local fs = require "nixio.fs"

local URL = "https://raw.githubusercontent.com/pbakondy/mcc-mnc-list/master/mcc-mnc-list.json"
local TMP = "/tmp/modemwatch/mccmnc.json"
local STATUS = "/tmp/modemwatch/mccmnc_status"
local LOCK = "/tmp/modemwatch/mccmnc.lock"
local OUT = "/usr/share/modemwatch/mccmnc.dat"

local function write_status(state, message, count)
	fs.mkdirr("/tmp/modemwatch")
	local lines = {
		"state=" .. state,
		"message=" .. (message or ""),
		"count=" .. tostring(count or 0),
		"timestamp=" .. tostring(os.time())
	}
	fs.writefile(STATUS, table.concat(lines, "\n") .. "\n")
end

local function is_locked()
	local raw = fs.readfile(LOCK)
	local t = tonumber(raw or "")
	if t and (os.time() - t) < 300 then
		return true
	end
	fs.remove(LOCK)
	return false
end

local function download(url, file)
	fs.mkdirr("/tmp/modemwatch")
	local cmds = {
		"curl -fsSL --connect-timeout 20 --max-time 120 -o " .. file .. " '" .. url .. "'",
		"wget -q -O " .. file .. " '" .. url .. "'",
		"uclient-fetch -q -O " .. file .. " '" .. url .. "'"
	}
	for _, cmd in ipairs(cmds) do
		local rc = os.execute(cmd)
		if rc == 0 and fs.access(file) then
			return true
		end
	end
	return false
end

if is_locked() then
	write_status("error", "Update already running", 0)
	os.exit(1)
end
fs.writefile(LOCK, tostring(os.time()))

write_status("downloading", "Downloading MCC/MNC list", 0)
if not download(URL, TMP) then
	fs.remove(LOCK)
	write_status("error", "Download failed", 0)
	os.exit(1)
end

write_status("parsing", "Parsing MCC/MNC list", 0)
local raw = fs.readfile(TMP)
local ok, data = pcall(jsonc.parse, raw or "")
if not ok or type(data) ~= "table" then
	fs.remove(TMP)
	fs.remove(LOCK)
	write_status("error", "JSON parse failed", 0)
	os.exit(1)
end

local out = {
	"# PLMN;Country;Operator",
	"# Generated from https://github.com/pbakondy/mcc-mnc-list",
	"# Source: https://en.wikipedia.org/wiki/Mobile_country_code"
}
local count = 0
for _, rec in ipairs(data) do
	local mcc = rec.mcc
	local mnc = rec.mnc
	if mcc and mnc then
		local plmn = tostring(mcc) .. tostring(mnc)
		local name = rec.brand
		if not name or name == "" then
			name = rec.operator
		end
		if name and name ~= "" then
			local country = tostring(rec.countryName or "")
			country = country:gsub(";", ","):gsub("[\r\n]+", " ")
			name = tostring(name):gsub(";", ","):gsub("[\r\n]+", " ")
			out[#out + 1] = plmn .. ";" .. country .. ";" .. name
			count = count + 1
		end
	end
end

fs.mkdirr("/usr/share/modemwatch")
local tmpout = OUT .. ".tmp"
fs.writefile(tmpout, table.concat(out, "\n") .. "\n")
os.rename(tmpout, OUT)
fs.remove(TMP)
fs.remove(LOCK)
write_status("done", "MCC/MNC database updated", count)
