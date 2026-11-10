local m, s, o

local sys = require "luci.sys"
local uci = require "luci.model.uci"

local cursor = uci.cursor()
local current_at = cursor:get("modemwatch", "main", "at_port") or "/dev/ttyUSB2"
local current_wan = cursor:get("modemwatch", "main", "wan_iface") or "wan"

local function at_ports()
	local ports = {}
	local out = sys.exec("ls -1 /dev 2>/dev/null | grep -E '^tty(USB|ACM)[0-9]+$'")
	for name in (out or ""):gmatch("[^\r\n]+") do
		ports[#ports + 1] = "/dev/" .. name
	end
	table.sort(ports)
	return ports
end

local function network_interfaces()
	local ifaces = {}
	cursor:foreach("network", "interface", function(section)
		local name = section[".name"]
		if name and name ~= "loopback" and name ~= "lan" then
			local label = name
			if section.device and section.device ~= "" then
				label = label .. " (" .. section.device .. ")"
			end
			ifaces[#ifaces + 1] = { name = name, label = label }
		end
	end)
	table.sort(ifaces, function(a, b) return a.name < b.name end)
	return ifaces
end

m = Map("modemwatch", translate("Modem LTE 4G"),
	translate("Checks internet connectivity and reboots the Quectel modem when the connection is lost."))

s = m:section(TypedSection, "modemwatch", translate("Settings"))
s.anonymous = true
s.addremove = false

o = s:option(DummyValue, "_service", "")
o.rawhtml = true
o.default = "<h3>" .. translate("Service settings") .. "</h3>"

o = s:option(Flag, "enabled", translate("Enable service"))
o.default = "1"
o.rmempty = false

o = s:option(Value, "check_interval", translate("Check interval (seconds)"))
o.datatype = "uinteger"
o.default = "60"
o.rmempty = false

o = s:option(Value, "failure_threshold", translate("Failures before modem reboot"))
o.datatype = "uinteger"
o.default = "3"
o.rmempty = false

o = s:option(Value, "ping_hosts", translate("Ping hosts"))
o.default = "8.8.8.8 1.1.1.1 9.9.9.9"
o.rmempty = false
o.description = translate("Space-separated list. Internet is considered up if at least one host responds.")

o = s:option(Flag, "dns_check", translate("Also require DNS resolution"))
o.default = "0"

o = s:option(Value, "dns_name", translate("DNS name to resolve"))
o.default = "openwrt.org"
o:depends("dns_check", "1")

o = s:option(Flag, "http_check", translate("Also require an HTTP request"))
o.default = "0"

o = s:option(Value, "http_url", translate("HTTP URL"))
o.default = "http://connectivitycheck.gstatic.com/generate_204"
o:depends("http_check", "1")

o = s:option(ListValue, "wan_iface", translate("WAN interface"))
local wan_found = false
for _, iface in ipairs(network_interfaces()) do
	o:value(iface.name, iface.label)
	if iface.name == current_wan then
		wan_found = true
	end
end
if not wan_found then
	o:value(current_wan, current_wan)
end
o.default = "wan"
o.rmempty = false
o.description = translate("The device name is read from network.<iface>.device.")

o = s:option(DummyValue, "_modem", "")
o.rawhtml = true
o.default = "<h3>" .. translate("Modem settings") .. "</h3>"

o = s:option(ListValue, "at_port", translate("AT serial port"))
local at_found = false
for _, port in ipairs(at_ports()) do
	o:value(port, port)
	if port == current_at then
		at_found = true
	end
end
if not at_found then
	o:value(current_at, current_at)
end
o.default = "/dev/ttyUSB2"
o.rmempty = false
o.description = translate("Detected USB/ACM serial ports. For Quectel EC200A use /dev/ttyUSB2; /dev/ttyUSB0 is the diagnostic port and does not answer AT commands.")

o = s:option(ListValue, "baud", translate("AT port baud rate"))
for _, baud in ipairs({ "9600", "19200", "38400", "57600", "115200", "230400", "460800", "921600" }) do
	o:value(baud, baud)
end
o.default = "115200"
o.rmempty = false

o = s:option(ListValue, "reboot_method", translate("Modem reboot method"))
o:value("cfun", translate("AT+CFUN=1,1 (recommended)"))
o:value("usb", translate("USB re-bind (best effort)"))
o.default = "cfun"
o.rmempty = false

o = s:option(Value, "reboot_wait", translate("Wait after reboot (seconds)"))
o.datatype = "uinteger"
o.default = "45"
o.rmempty = false

o = s:option(Flag, "collect_modem_info", translate("Collect modem information"))
o.default = "1"
o.description = translate("Reads model, firmware, IMEI, signal, operator and temperature via AT commands.")

o = s:option(Value, "info_interval", translate("Modem info interval (seconds)"))
o.datatype = "uinteger"
o.default = "300"
o:depends("collect_modem_info", "1")
o.description = translate("How often to query the modem with AT commands. Keep it longer if other modem tools use the same serial port.")

o = s:option(Value, "signal_interval", translate("Signal refresh interval (seconds)"))
o.datatype = "uinteger"
o.default = "5"
o.rmempty = false
o.description = translate("Pause between signal page updates. The actual update also includes the modem response time.")

o = s:option(DummyValue, "_safety", "")
o.rawhtml = true
o.default = "<h3>" .. translate("Safety") .. "</h3>"

o = s:option(Value, "max_reboots", translate("Maximum reboots per window"))
o.datatype = "uinteger"
o.default = "5"
o.description = translate("Set to 0 for unlimited. The limit prevents reboot loops.")

o = s:option(Value, "reboot_window", translate("Reboot window (seconds)"))
o.datatype = "uinteger"
o.default = "3600"

o = s:option(Value, "cooldown", translate("Cooldown between reboots (seconds)"))
o.datatype = "uinteger"
o.default = "300"

o = s:option(DummyValue, "_logging", "")
o.rawhtml = true
o.default = "<h3>" .. translate("Logging") .. "</h3>"

o = s:option(ListValue, "log_level", translate("Log level"))
o:value("error", translate("Error"))
o:value("warn", translate("Warning"))
o:value("info", translate("Info"))
o:value("debug", translate("Debug"))
o.default = "info"
o.rmempty = false

o = s:option(DummyValue, "_warning", translate("Remote access warning"))
o.default = translate("This service reboots only the modem, not the router. If the modem is the only WAN, internet and remote access will be down during the reboot. Do not change USB mode, APN or band settings remotely without a rollback plan.")

return m
