#!/bin/sh
# modemwatch - Quectel modem watchdog for OpenWrt
# Copyright (C) 2026
# SPDX-License-Identifier: MIT

CONFIG="modemwatch"
STATE_DIR="/var/run/modemwatch"
STATUS_FILE="$STATE_DIR/status"
PID_FILE="$STATE_DIR/pid"
LOCK_DIR="$STATE_DIR/lock"
REBOOT_FILE="$STATE_DIR/reboots"
LOG_FILE="/var/log/modemwatch.log"
LOG_TAG="modemwatch"

# Defaults (overridden by UCI)
enabled=1
at_port="/dev/ttyUSB2"
baud="115200"
check_interval="60"
failure_threshold="3"
ping_hosts="8.8.8.8 1.1.1.1 9.9.9.9"
dns_check="0"
dns_name="openwrt.org"
http_check="0"
http_url="http://connectivitycheck.gstatic.com/generate_204"
reboot_method="cfun"
reboot_wait="45"
max_reboots="5"
reboot_window="3600"
cooldown="300"
collect_modem_info="1"
info_interval="300"
log_level="info"
wan_iface="wan"
wan_device=""

# Runtime state
state="starting"
last_check="0"
last_success="0"
last_failure="0"
failures="0"
reboots="0"
last_reboot="0"
last_info="0"
wan_up=""
wan_ip=""
ping_ok=""
dns_ok=""
http_ok=""
latency_ms=""
modem_model=""
modem_fw=""
modem_imei=""
signal_csq=""
signal_rssi=""
signal_rsrp=""
signal_sinr=""
signal_rsrq=""
signal_band=""
operator=""
network=""
modem_temp=""
modem_info_ok="0"
service_start="0"

[ -f /lib/functions.sh ] && . /lib/functions.sh

now() {
	date +%s
}

log() {
	level="$1"
	shift
	case "$log_level" in
		error) [ "$level" = "error" ] || return 0 ;;
		warn)  [ "$level" = "error" ] || [ "$level" = "warn" ] || return 0 ;;
		info)  [ "$level" = "debug" ] && return 0 ;;
		debug) ;;
		*) ;;
	esac
	msg="$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
	logger -t "$LOG_TAG" "$*" 2>/dev/null
	echo "$msg" >> "$LOG_FILE" 2>/dev/null
	size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
	if [ "$size" -gt 262144 ] 2>/dev/null; then
		mv "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
	fi
}

load_config() {
	config_load "$CONFIG" 2>/dev/null || true

	config_get_bool enabled main enabled 1
	config_get at_port main at_port "$at_port"
	config_get baud main baud "$baud"
	config_get check_interval main check_interval "$check_interval"
	config_get failure_threshold main failure_threshold "$failure_threshold"
	config_get ping_hosts main ping_hosts "$ping_hosts"
	config_get_bool dns_check main dns_check 0
	config_get dns_name main dns_name "$dns_name"
	config_get_bool http_check main http_check 0
	config_get http_url main http_url "$http_url"
	config_get reboot_method main reboot_method "$reboot_method"
	config_get reboot_wait main reboot_wait "$reboot_wait"
	config_get max_reboots main max_reboots "$max_reboots"
	config_get reboot_window main reboot_window "$reboot_window"
	config_get cooldown main cooldown "$cooldown"
	config_get_bool collect_modem_info main collect_modem_info 1
	config_get info_interval main info_interval "$info_interval"
	config_get log_level main log_level "$log_level"
	config_get wan_iface main wan_iface "$wan_iface"

	wan_device=$(uci -q get "network.${wan_iface}.device" 2>/dev/null)
	[ -n "$wan_device" ] || wan_device="$wan_iface"

	sanitize_config
}

sanitize_config() {
	case "$check_interval" in ''|*[!0-9]*) check_interval="60" ;; esac
	[ "$check_interval" -ge 10 ] 2>/dev/null || check_interval="10"

	case "$failure_threshold" in ''|*[!0-9]*) failure_threshold="3" ;; esac
	[ "$failure_threshold" -ge 1 ] 2>/dev/null || failure_threshold="1"

	case "$reboot_wait" in ''|*[!0-9]*) reboot_wait="45" ;; esac
	case "$max_reboots" in ''|*[!0-9]*) max_reboots="5" ;; esac
	case "$reboot_window" in ''|*[!0-9]*) reboot_window="3600" ;; esac
	[ "$reboot_window" -ge 60 ] 2>/dev/null || reboot_window="60"

	case "$cooldown" in ''|*[!0-9]*) cooldown="300" ;; esac
	case "$info_interval" in ''|*[!0-9]*) info_interval="300" ;; esac
	[ "$info_interval" -ge 60 ] 2>/dev/null || info_interval="60"
	case "$baud" in ''|*[!0-9]*) baud="115200" ;; esac

	[ -n "$at_port" ] || at_port="/dev/ttyUSB2"
	[ -n "$ping_hosts" ] || ping_hosts="8.8.8.8 1.1.1.1 9.9.9.9"
	[ -n "$wan_iface" ] || wan_iface="wan"
	[ -n "$wan_device" ] || wan_device="$wan_iface"

	case "$log_level" in
		error|warn|info|debug) ;;
		*) log_level="info" ;;
	esac
}

acquire_lock() {
	if command -v flock >/dev/null 2>&1; then
		exec 9>"$STATE_DIR/lockfile"
		if flock -n 9; then
			return 0
		fi
		exec 9>&-
		return 1
	fi

	tries=0
	while ! mkdir "$LOCK_DIR" 2>/dev/null; do
		tries=$((tries + 1))
		if [ "$tries" -ge 5 ]; then
			if [ -f "$LOCK_DIR/timestamp" ]; then
				ts=$(cat "$LOCK_DIR/timestamp" 2>/dev/null || echo 0)
				if [ $(( $(now) - ts )) -gt 300 ] 2>/dev/null; then
					rm -rf "$LOCK_DIR"
					continue
				fi
			fi
			return 1
		fi
		sleep 1
	done
	echo "$(now)" > "$LOCK_DIR/timestamp"
	echo "$$" > "$LOCK_DIR/pid"
	return 0
}

release_lock() {
	if command -v flock >/dev/null 2>&1; then
		exec 9>&-
	else
		rm -rf "$LOCK_DIR"
	fi
}

acquire_lock_wait() {
	tries=0
	while ! acquire_lock; do
		tries=$((tries + 1))
		if [ "$tries" -ge 60 ]; then
			return 1
		fi
		sleep 1
	done
	return 0
}

at_send() {
	cmd="$1"
	if [ ! -c "$at_port" ]; then
		log error "AT port $at_port not found"
		return 1
	fi
	if command -v sms_tool >/dev/null 2>&1; then
		sms_tool -d "$at_port" at "$cmd" >/dev/null 2>&1
	elif command -v picocom >/dev/null 2>&1; then
		printf '%s\r' "$cmd" | picocom -b "$baud" -q --noreset --exit-after 1500 "$at_port" >/dev/null 2>&1
	else
		printf '%s\r' "$cmd" > "$at_port" 2>/dev/null
	fi
}

at_cmd() {
	cmd="$1"
	[ -c "$at_port" ] || { echo "ERROR: AT port not found"; return 1; }

	if command -v sms_tool >/dev/null 2>&1; then
		sms_tool -d "$at_port" at "$cmd" 2>/dev/null
		return 0
	fi

	tmp="$STATE_DIR/atcmd.$$"
	if command -v picocom >/dev/null 2>&1; then
		{
			sleep 1
			printf '%s\r' "$cmd"
			sleep 3
		} | picocom -b "$baud" -q --noreset --exit-after 5000 "$at_port" > "$tmp" 2>/dev/null
	else
		( cat "$at_port" > "$tmp" 2>/dev/null ) &
		catpid=$!
		sleep 1
		printf '%s\r' "$cmd" > "$at_port" 2>/dev/null
		sleep 3
		kill "$catpid" 2>/dev/null
		wait "$catpid" 2>/dev/null
	fi

	tr -d '\r' < "$tmp" > "$tmp.clean" 2>/dev/null
	mv "$tmp.clean" "$tmp" 2>/dev/null
	awk -v cmd="$cmd" '$0 == cmd { next } /^$/ { next } { print }' "$tmp"
	rm -f "$tmp"
}

at_cmd_long() {
	cmd="$1"
	wait_sec="${2:-60}"
	[ -c "$at_port" ] || { echo "ERROR: AT port not found"; return 1; }

	tmp="$STATE_DIR/atlong.$$"
	if command -v picocom >/dev/null 2>&1; then
		{
			sleep 1
			printf '%s\r' "$cmd"
			sleep "$wait_sec"
		} | picocom -b "$baud" -q --noreset --exit-after $((wait_sec * 1000 + 2000)) "$at_port" > "$tmp" 2>/dev/null
	else
		( cat "$at_port" > "$tmp" 2>/dev/null ) &
		catpid=$!
		sleep 1
		printf '%s\r' "$cmd" > "$at_port" 2>/dev/null
		sleep "$wait_sec"
		kill "$catpid" 2>/dev/null
		wait "$catpid" 2>/dev/null
	fi

	tr -d '\r' < "$tmp" > "$tmp.clean" 2>/dev/null
	mv "$tmp.clean" "$tmp" 2>/dev/null
	awk -v cmd="$cmd" '$0 == cmd { next } /^$/ { next } { print }' "$tmp"
	rm -f "$tmp"
}

query_modem_info() {
	[ "$collect_modem_info" = "1" ] || return 0
	[ -c "$at_port" ] || return 0

	modem_model=""
	modem_fw=""
	modem_imei=""
	signal_csq=""
	signal_rssi=""
	signal_rsrp=""
	signal_sinr=""
	signal_rsrq=""
	signal_band=""
	operator=""
	network=""
	modem_temp=""
	modem_info_ok="0"

	tmp="$STATE_DIR/at.$$"
	if command -v sms_tool >/dev/null 2>&1; then
		: > "$tmp"
		for c in 'ATI' 'AT+CGSN' 'AT+CSQ' 'AT+QCSQ' 'AT+COPS?' 'AT+QNWINFO' 'AT+QENG="servingcell"' 'AT+QTEMP'; do
			sms_tool -d "$at_port" at "$c" >> "$tmp" 2>/dev/null
		done
	elif command -v picocom >/dev/null 2>&1; then
		{
			sleep 1
			printf 'ATI\r'; sleep 1
			printf 'AT+CGSN\r'; sleep 1
			printf 'AT+CSQ\r'; sleep 1
			printf 'AT+QCSQ\r'; sleep 1
			printf 'AT+COPS?\r'; sleep 1
			printf 'AT+QNWINFO\r'; sleep 1
			printf 'AT+QENG="servingcell"\r'; sleep 1
			printf 'AT+QTEMP\r'; sleep 2
		} | picocom -b "$baud" -q --noreset --exit-after 11000 "$at_port" > "$tmp" 2>/dev/null
	else
		( cat "$at_port" > "$tmp" 2>/dev/null ) &
		catpid=$!
		sleep 1
		printf 'ATI\r' > "$at_port" 2>/dev/null; sleep 1
		printf 'AT+CGSN\r' > "$at_port" 2>/dev/null; sleep 1
		printf 'AT+CSQ\r' > "$at_port" 2>/dev/null; sleep 1
		printf 'AT+QCSQ\r' > "$at_port" 2>/dev/null; sleep 1
		printf 'AT+COPS?\r' > "$at_port" 2>/dev/null; sleep 1
		printf 'AT+QNWINFO\r' > "$at_port" 2>/dev/null; sleep 1
		printf 'AT+QENG="servingcell"\r' > "$at_port" 2>/dev/null; sleep 1
		printf 'AT+QTEMP\r' > "$at_port" 2>/dev/null; sleep 2
		kill "$catpid" 2>/dev/null
		wait "$catpid" 2>/dev/null
	fi

	[ -s "$tmp" ] || { rm -f "$tmp"; modem_info_ok="0"; return 0; }

	# Normalize CR/LF for parsing
	tr -d '\r' < "$tmp" > "$tmp.clean" 2>/dev/null
	mv "$tmp.clean" "$tmp" 2>/dev/null

	modem_model=$(awk 'prev == "Quectel" { print; exit } { prev = $0 }' "$tmp" 2>/dev/null)
	modem_fw=$(sed -n 's/^Revision: //p' "$tmp" 2>/dev/null | head -n 1)
	modem_imei=$(grep -Eo '[0-9]{15}' "$tmp" 2>/dev/null | head -n 1)
	signal_csq=$(awk -F, '/^\+CSQ:/ { gsub(/[^0-9]/, "", $1); print $1; exit }' "$tmp" 2>/dev/null)

	qeng=$(grep '^+QENG:' "$tmp" 2>/dev/null | head -n 1)
	if [ -n "$qeng" ]; then
		signal_rsrp=$(echo "$qeng" | awk -F, '{ gsub(/[^0-9-]/, "", $14); print $14 }')
		signal_rsrq=$(echo "$qeng" | awk -F, '{ gsub(/[^0-9-]/, "", $15); print $15 }')
		signal_rssi=$(echo "$qeng" | awk -F, '{ gsub(/[^0-9-]/, "", $16); print $16 }')
		signal_sinr=$(echo "$qeng" | awk -F, '{ gsub(/[^0-9-]/, "", $17); print $17 }')
		signal_band=$(echo "$qeng" | awk -F, '{ gsub(/[^0-9]/, "", $10); print $10 }')
	fi

	if [ -z "$signal_rsrp" ] || [ -z "$signal_sinr" ] || [ -z "$signal_rsrq" ]; then
		qcsq=$(grep '^+QCSQ:' "$tmp" 2>/dev/null | head -n 1)
		if [ -n "$qcsq" ]; then
			[ -z "$signal_rsrp" ] && signal_rsrp=$(echo "$qcsq" | awk -F, '{ gsub(/[^0-9-]/, "", $3); print $3 }')
			[ -z "$signal_sinr" ] && signal_sinr=$(echo "$qcsq" | awk -F, '{ gsub(/[^0-9-]/, "", $4); print $4 }')
			[ -z "$signal_rsrq" ] && signal_rsrq=$(echo "$qcsq" | awk -F, '{ gsub(/[^0-9-]/, "", $5); print $5 }')
		fi
	fi

	if [ -n "$signal_sinr" ] && [ "$signal_sinr" -gt 50 ] 2>/dev/null; then
		signal_sinr=$(awk -v v="$signal_sinr" 'BEGIN { printf "%.1f", v / 10 }')
	fi

	if [ -z "$signal_rssi" ] && [ -n "$signal_csq" ]; then
		signal_rssi=$(awk -v c="$signal_csq" 'BEGIN { printf "%d", -113 + 2 * c }')
	fi

	operator=$(awk -F'"' '/^\+COPS:/ { print $2; exit }' "$tmp" 2>/dev/null)
	network=$(awk -F'"' '/^\+QNWINFO:/ { print $2 " " $4; exit }' "$tmp" 2>/dev/null)
	modem_temp=$(awk -F, '/^\+QTEMP:/ { gsub(/[^0-9-]/, "", $1); print $1; exit }' "$tmp" 2>/dev/null)

	if [ -n "$modem_model" ] || [ -n "$modem_imei" ]; then
		modem_info_ok="1"
	else
		modem_info_ok="0"
	fi

	rm -f "$tmp"
}

query_signal() {
	[ -c "$at_port" ] || { echo "error=AT port not found"; return 1; }

	tmp="$STATE_DIR/signal.$$"
	if command -v sms_tool >/dev/null 2>&1; then
		: > "$tmp"
		for c in 'AT+CSQ' 'AT+QCSQ' 'AT+QENG="servingcell"'; do
			sms_tool -d "$at_port" at "$c" >> "$tmp" 2>/dev/null
		done
	elif command -v picocom >/dev/null 2>&1; then
		{
			sleep 1
			printf 'AT+CSQ\r'; sleep 1
			printf 'AT+QCSQ\r'; sleep 1
			printf 'AT+QENG="servingcell"\r'; sleep 2
		} | picocom -b "$baud" -q --noreset --exit-after 6000 "$at_port" > "$tmp" 2>/dev/null
	else
		( cat "$at_port" > "$tmp" 2>/dev/null ) &
		catpid=$!
		sleep 1
		printf 'AT+CSQ\r' > "$at_port" 2>/dev/null; sleep 1
		printf 'AT+QCSQ\r' > "$at_port" 2>/dev/null; sleep 1
		printf 'AT+QENG="servingcell"\r' > "$at_port" 2>/dev/null; sleep 2
		kill "$catpid" 2>/dev/null
		wait "$catpid" 2>/dev/null
	fi

	[ -s "$tmp" ] || { rm -f "$tmp"; echo "error=no response"; return 1; }
	tr -d '\r' < "$tmp" > "$tmp.clean" 2>/dev/null
	mv "$tmp.clean" "$tmp" 2>/dev/null

	csq=$(awk -F, '/^\+CSQ:/ { gsub(/[^0-9]/, "", $1); print $1; exit }' "$tmp" 2>/dev/null)
	[ "$csq" = "99" ] && csq=""

	qeng=$(grep '^+QENG:' "$tmp" 2>/dev/null | head -n 1)
	rsrp=""
	rsrq=""
	rssi=""
	sinr=""
	band=""
	network=""
	if [ -n "$qeng" ]; then
		rsrp=$(echo "$qeng" | awk -F, '{ gsub(/[^0-9-]/, "", $14); print $14 }')
		rsrq=$(echo "$qeng" | awk -F, '{ gsub(/[^0-9-]/, "", $15); print $15 }')
		rssi=$(echo "$qeng" | awk -F, '{ gsub(/[^0-9-]/, "", $16); print $16 }')
		sinr=$(echo "$qeng" | awk -F, '{ gsub(/[^0-9-]/, "", $17); print $17 }')
		band=$(echo "$qeng" | awk -F, '{ gsub(/[^0-9]/, "", $10); print $10 }')
		network=$(echo "$qeng" | awk -F, '{ gsub(/"/, "", $3); gsub(/"/, "", $4); print $3 " " $4 }')
	fi

	if [ -z "$rsrp" ] || [ -z "$sinr" ] || [ -z "$rsrq" ]; then
		qcsq=$(grep '^+QCSQ:' "$tmp" 2>/dev/null | head -n 1)
		if [ -n "$qcsq" ]; then
			[ -z "$rsrp" ] && rsrp=$(echo "$qcsq" | awk -F, '{ gsub(/[^0-9-]/, "", $3); print $3 }')
			[ -z "$sinr" ] && sinr=$(echo "$qcsq" | awk -F, '{ gsub(/[^0-9-]/, "", $4); print $4 }')
			[ -z "$rsrq" ] && rsrq=$(echo "$qcsq" | awk -F, '{ gsub(/[^0-9-]/, "", $5); print $5 }')
		fi
	fi

	if [ -n "$sinr" ] && [ "$sinr" -gt 50 ] 2>/dev/null; then
		sinr=$(awk -v v="$sinr" 'BEGIN { printf "%.1f", v / 10 }')
	fi

	if [ -z "$rssi" ] && [ -n "$csq" ]; then
		rssi=$(awk -v c="$csq" 'BEGIN { printf "%d", -113 + 2 * c }')
	fi

	echo "csq=$csq"
	echo "rssi=$rssi"
	echo "rsrp=$rsrp"
	echo "sinr=$sinr"
	echo "rsrq=$rsrq"
	echo "band=$band"
	echo "network=$network"
	echo "timestamp=$(now)"
	rm -f "$tmp"
}

get_wan_status() {
	wan_ip=$(ip -4 addr show "$wan_device" 2>/dev/null | awk '/inet / { print $2; exit }')
	wan_up="0"
	if command -v ubus >/dev/null 2>&1; then
		if ubus call "network.interface.${wan_iface}" status 2>/dev/null | grep -q '"up": true'; then
			wan_up="1"
		fi
	fi
	[ -n "$wan_ip" ] && wan_up="1"
}

check_ping() {
	ping_ok="0"
	latency_ms=""
	for host in $ping_hosts; do
		out=$(ping -c 1 -W 3 "$host" 2>/dev/null)
		if [ $? -eq 0 ]; then
			ping_ok="1"
			latency_ms=$(echo "$out" | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -n 1)
			return 0
		fi
	done
	return 1
}

check_dns() {
	[ "$dns_check" = "1" ] || { dns_ok="1"; return 0; }
	if command -v nslookup >/dev/null 2>&1; then
		nslookup "$dns_name" >/dev/null 2>&1
	else
		ping -c 1 -W 3 "$dns_name" >/dev/null 2>&1
	fi
	if [ $? -eq 0 ]; then
		dns_ok="1"
		return 0
	fi
	dns_ok="0"
	return 1
}

check_http() {
	[ "$http_check" = "1" ] || { http_ok="1"; return 0; }
	if command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -q -O /dev/null -T 5 "$http_url" >/dev/null 2>&1
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O /dev/null -T 5 "$http_url" >/dev/null 2>&1
	else
		http_ok="1"
		return 0
	fi
	if [ $? -eq 0 ]; then
		http_ok="1"
		return 0
	fi
	http_ok="0"
	return 1
}

check_internet() {
	ping_ok="0"
	dns_ok="0"
	http_ok="0"
	latency_ms=""
	get_wan_status
	check_ping || return 1
	check_dns || return 1
	check_http || return 1
	return 0
}

write_status() {
	[ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR"
	tmp="$STATUS_FILE.tmp"
	service_uptime="0"
	[ "$service_start" -gt 0 ] 2>/dev/null && service_uptime=$(( $(now) - service_start ))
	{
		echo "version=1.0.0"
		echo "state=$state"
		echo "enabled=$enabled"
		echo "service_running=1"
		echo "service_start=$service_start"
		echo "service_uptime=$service_uptime"
		echo "last_check=$last_check"
		echo "last_success=$last_success"
		echo "last_failure=$last_failure"
		echo "failures=$failures"
		echo "failure_threshold=$failure_threshold"
		echo "reboots=$reboots"
		echo "last_reboot=$last_reboot"
		echo "last_info=$last_info"
		echo "info_interval=$info_interval"
		echo "check_interval=$check_interval"
		echo "reboot_method=$reboot_method"
		echo "reboot_wait=$reboot_wait"
		echo "wan_iface=$wan_iface"
		echo "wan_device=$wan_device"
		echo "wan_up=$wan_up"
		echo "wan_ip=$wan_ip"
		echo "ping_ok=$ping_ok"
		echo "dns_ok=$dns_ok"
		echo "http_ok=$http_ok"
		echo "latency_ms=$latency_ms"
		echo "modem_model=$modem_model"
		echo "modem_fw=$modem_fw"
		echo "modem_imei=$modem_imei"
		echo "signal_csq=$signal_csq"
		echo "signal_rssi=$signal_rssi"
		echo "signal_rsrp=$signal_rsrp"
		echo "signal_sinr=$signal_sinr"
		echo "signal_rsrq=$signal_rsrq"
		echo "signal_band=$signal_band"
		echo "operator=$operator"
		echo "network=$network"
		echo "modem_temp=$modem_temp"
		echo "modem_info_ok=$modem_info_ok"
		echo "pid=$$"
	} > "$tmp"
	mv "$tmp" "$STATUS_FILE"
}

load_status() {
	[ -f "$STATUS_FILE" ] || return 1
	while IFS='=' read -r key value; do
		case "$key" in
			state) state="$value" ;;
			last_check) last_check="$value" ;;
			last_success) last_success="$value" ;;
			last_failure) last_failure="$value" ;;
			failures) failures="$value" ;;
			reboots) reboots="$value" ;;
			last_reboot) last_reboot="$value" ;;
			last_info) last_info="$value" ;;
			service_start) service_start="$value" ;;
			wan_up) wan_up="$value" ;;
			wan_ip) wan_ip="$value" ;;
			ping_ok) ping_ok="$value" ;;
			dns_ok) dns_ok="$value" ;;
			http_ok) http_ok="$value" ;;
			latency_ms) latency_ms="$value" ;;
			modem_model) modem_model="$value" ;;
			modem_fw) modem_fw="$value" ;;
			modem_imei) modem_imei="$value" ;;
			signal_csq) signal_csq="$value" ;;
			signal_rssi) signal_rssi="$value" ;;
			signal_rsrp) signal_rsrp="$value" ;;
			signal_sinr) signal_sinr="$value" ;;
			signal_rsrq) signal_rsrq="$value" ;;
			signal_band) signal_band="$value" ;;
			operator) operator="$value" ;;
			network) network="$value" ;;
			modem_temp) modem_temp="$value" ;;
			modem_info_ok) modem_info_ok="$value" ;;
		esac
	done < "$STATUS_FILE"
	return 0
}

reset_reboot_window() {
	now_ts=$(now)
	cutoff=$((now_ts - reboot_window))
	if [ -f "$REBOOT_FILE" ]; then
		awk -v c="$cutoff" '$1 >= c' "$REBOOT_FILE" > "$REBOOT_FILE.tmp" 2>/dev/null
		[ -f "$REBOOT_FILE.tmp" ] && mv "$REBOOT_FILE.tmp" "$REBOOT_FILE"
	fi
}

count_recent_reboots() {
	[ -f "$REBOOT_FILE" ] || { echo 0; return; }
	wc -l < "$REBOOT_FILE" 2>/dev/null || echo 0
}

reset_usb_modem() {
	dev=$(basename "$(readlink -f /sys/class/net/usb0/device 2>/dev/null)" 2>/dev/null)
	[ -n "$dev" ] || { log error "cannot find USB device for usb0"; return 1; }
	for drv in rndis_host cdc_ether; do
		if [ -e "/sys/bus/usb/drivers/$drv/$dev" ]; then
			echo "$dev" > "/sys/bus/usb/drivers/$drv/unbind" 2>/dev/null
			sleep 2
			echo "$dev" > "/sys/bus/usb/drivers/$drv/bind" 2>/dev/null
			return $?
		fi
	done
	log error "no known USB driver bound to $dev"
	return 1
}

reboot_modem() {
	case "$reboot_method" in
		cfun|usb) ;;
		*) log error "invalid reboot_method=$reboot_method"; return 1 ;;
	esac

	log warn "rebooting modem (method=$reboot_method)"
	state="rebooting"
	last_reboot=$(now)
	reboots=$((reboots + 1))
	echo "$last_reboot" >> "$REBOOT_FILE"

	case "$reboot_method" in
		cfun)
			at_send "AT+CFUN=1,1" || log error "failed to send AT+CFUN=1,1"
			;;
		usb)
			reset_usb_modem || log error "USB reset failed"
			;;
	esac

	failures="0"
	write_status
	log info "waiting up to ${reboot_wait}s for modem to come back"
	elapsed=0
	while [ "$elapsed" -lt "$reboot_wait" ]; do
		sleep 5
		elapsed=$((elapsed + 5))
		if check_internet; then
			state="online"
			last_success=$(now)
			failures="0"
			log info "internet restored after ${elapsed}s"
			write_status
			return 0
		fi
	done
	state="offline"
	log warn "still offline after ${reboot_wait}s"
	write_status
}

maybe_reboot() {
	now_ts=$(now)

	# Respect reboots performed by a manual action or another process.
	if [ -f "$REBOOT_FILE" ]; then
		file_last=$(tail -n 1 "$REBOOT_FILE" 2>/dev/null)
		case "$file_last" in
			''|*[!0-9]*) ;;
			*) [ "$file_last" -gt "$last_reboot" ] 2>/dev/null && last_reboot="$file_last" ;;
		esac
	fi

	if [ "$last_reboot" -gt 0 ] 2>/dev/null && [ $((now_ts - last_reboot)) -lt "$cooldown" ] 2>/dev/null; then
		log warn "reboot suppressed: cooldown $((cooldown - (now_ts - last_reboot)))s left"
		return 1
	fi

	if [ "$max_reboots" -gt 0 ] 2>/dev/null; then
		reset_reboot_window
		recent=$(count_recent_reboots)
		if [ "$recent" -ge "$max_reboots" ] 2>/dev/null; then
			log warn "reboot suppressed: $recent reboots in last ${reboot_window}s (max $max_reboots)"
			return 1
		fi
	fi

	reboot_modem
}

wait_before_reboot() {
	timeout="${offline_timeout:-60}"
	case "$timeout" in
		''|*[!0-9]*) timeout=60 ;;
	esac
	if [ "$timeout" -le 0 ] 2>/dev/null; then
		maybe_reboot
		return
	fi

	log warn "internet is down; waiting ${timeout}s before reboot"
	elapsed=0
	while [ "$elapsed" -lt "$timeout" ]; do
		sleep 5
		elapsed=$((elapsed + 5))
		if check_internet; then
			state="online"
			last_success=$(now)
			failures="0"
			log info "internet restored after ${elapsed}s; reboot cancelled"
			write_status
			return 0
		fi
	done

	log warn "still offline after ${timeout}s; rebooting modem"
	maybe_reboot
}

run_cycle() {
	load_config

	if [ "$enabled" != "1" ]; then
		state="disabled"
		write_status
		return 0
	fi

	if ! acquire_lock; then
		log debug "check skipped: lock busy"
		return 0
	fi

	last_check=$(now)
	state="checking"
	write_status

	if check_internet; then
		failures="0"
		last_success="$last_check"
		state="online"
		log info "internet OK (latency ${latency_ms:-?} ms, WAN ${wan_device} ${wan_ip:-no-ip})"
	else
		failures=$((failures + 1))
		last_failure="$last_check"
		state="offline"
		log warn "internet FAILED ($failures/$failure_threshold) ping=$ping_ok dns=$dns_ok http=$http_ok wan_up=$wan_up ip=${wan_ip:-none}"
		if [ "$failures" -ge "$failure_threshold" ] 2>/dev/null; then
			wait_before_reboot
		fi
	fi

	if [ "$collect_modem_info" = "1" ]; then
		now_ts=$(now)
		if [ "$last_info" -eq 0 ] 2>/dev/null || [ $((now_ts - last_info)) -ge "$info_interval" ] 2>/dev/null; then
			query_modem_info
			last_info="$now_ts"
		fi
	fi

	write_status
	release_lock
}

do_check() {
	fast="$1"
	load_config
	mkdir -p "$STATE_DIR"
	load_status || true

	if ! acquire_lock; then
		echo "busy=1"
		return 1
	fi

	last_check=$(now)
	state="checking"
	write_status

	if check_internet; then
		failures="0"
		last_success="$last_check"
		state="online"
		log info "manual check: internet OK (latency ${latency_ms:-?} ms)"
	else
		failures=$((failures + 1))
		last_failure="$last_check"
		state="offline"
		log warn "manual check: internet FAILED ping=$ping_ok dns=$dns_ok http=$http_ok wan_up=$wan_up ip=${wan_ip:-none}"
	fi

	if [ "$fast" != "--fast" ]; then
		query_modem_info
		last_info=$(now)
	fi
	write_status
	release_lock
	cat "$STATUS_FILE"
}

do_reboot() {
	load_config
	mkdir -p "$STATE_DIR"
	load_status || true

	if ! acquire_lock_wait; then
		echo "busy=1"
		return 1
	fi

	reboot_modem
	query_modem_info
	last_info=$(now)
	write_status
	release_lock
	cat "$STATUS_FILE"
}

do_info() {
	force="$1"
	load_config
	mkdir -p "$STATE_DIR"

	if [ -f "$STATUS_FILE" ]; then
		load_status
	elif [ -f "$PID_FILE" ]; then
		pid=$(cat "$PID_FILE" 2>/dev/null)
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			state="starting"
		else
			state="stopped"
		fi
	else
		state="stopped"
	fi

	[ "$force" = "--force" ] && collect_modem_info="1"

	if acquire_lock; then
		query_modem_info
		last_info=$(now)
		write_status
		release_lock
	fi
	cat "$STATUS_FILE" 2>/dev/null
}

do_signal() {
	load_config
	mkdir -p "$STATE_DIR"

	if ! acquire_lock; then
		echo "busy=1"
		return 1
	fi

	query_signal
	release_lock
}

do_read() {
	load_config
	mkdir -p "$STATE_DIR"

	if ! acquire_lock; then
		echo "busy=1"
		return 1
	fi

	if ! command -v picocom >/dev/null 2>&1 && ! command -v sms_tool >/dev/null 2>&1; then
		echo "ERROR: picocom or sms_tool not installed"
		release_lock
		return 1
	fi

	tmp="$STATE_DIR/read.$$"
	if command -v sms_tool >/dev/null 2>&1; then
		for c in 'ATI' 'AT+CGMI' 'AT+CGMM' 'AT+CGMR' 'AT+CGSN' 'AT+QCCID' 'AT+CPIN?' 'AT+CSQ' 'AT+QCSQ' 'AT+QENG="servingcell"' 'AT+COPS?' 'AT+QNWINFO' 'AT+CGDCONT?' 'AT+QICSGP=1' 'AT+QCFG="nwscanmode"' 'AT+QCFG="band"' 'AT+QCFG="usbnet"' 'AT+QCFG="nat"' 'AT+QTEMP'; do
			sms_tool -d "$at_port" at "$c" 2>/dev/null
		done
		release_lock
		return 0
	fi
	{
		sleep 1
		for c in 'ATI' 'AT+CGMI' 'AT+CGMM' 'AT+CGMR' 'AT+CGSN' 'AT+QCCID' 'AT+CPIN?' 'AT+CSQ' 'AT+QCSQ' 'AT+QENG="servingcell"' 'AT+COPS?' 'AT+QNWINFO' 'AT+CGDCONT?' 'AT+QICSGP=1' 'AT+QCFG="nwscanmode"' 'AT+QCFG="band"' 'AT+QCFG="usbnet"' 'AT+QCFG="nat"' 'AT+QTEMP'; do
			printf '%s\r' "$c"
			sleep 1
		done
		sleep 1
	} | picocom -b "$baud" -q --noreset --exit-after 25000 "$at_port" > "$tmp" 2>/dev/null

	tr -d '\r' < "$tmp" > "$tmp.clean" 2>/dev/null
	mv "$tmp.clean" "$tmp" 2>/dev/null
	cat "$tmp"
	rm -f "$tmp"
	release_lock
}

do_scan() {
	load_config
	mkdir -p "$STATE_DIR"

	scan_status="$STATE_DIR/scan_status"
	scan_result="$STATE_DIR/scan_result"
	echo "state=scanning" > "$scan_status"
	echo "started=$(now)" >> "$scan_status"

	if ! acquire_lock; then
		echo "state=busy" > "$scan_status"
		return 1
	fi

	if [ ! -c "$at_port" ]; then
		echo "state=error" > "$scan_status"
		echo "error=AT port not found" >> "$scan_status"
		release_lock
		return 1
	fi

	out=$(at_cmd_long "AT+COPS=?" 120)
	printf '%s\n' "$out" > "$scan_result"
	echo "state=done" > "$scan_status"
	echo "finished=$(now)" >> "$scan_status"
	release_lock
}

do_scan_stop() {
	load_config
	mkdir -p "$STATE_DIR"

	for p in $(ps w | awk '/[m]odemwatch.sh scan$/ {print $1}'); do
		kill -TERM -$p 2>/dev/null || kill $p 2>/dev/null
	done

	rm -f "$STATE_DIR/scan_status" "$STATE_DIR/scan_result" "$STATE_DIR"/atlong.*
	echo "state=idle" > "$STATE_DIR/scan_status"
}

do_at() {
	load_config
	mkdir -p "$STATE_DIR"
	if [ -z "$*" ]; then
		echo "usage: $0 at <AT command>"
		return 1
	fi
	if ! acquire_lock; then
		echo "busy=1"
		return 1
	fi
	at_cmd "$*"
	release_lock
}

do_logs() {
	lines="${1:-200}"
	case "$lines" in ''|*[!0-9]*) lines="200" ;; esac
	if [ -f "$LOG_FILE" ]; then
		tail -n "$lines" "$LOG_FILE"
	else
		logread -e "$LOG_TAG" 2>/dev/null | tail -n "$lines"
	fi
}

cleanup() {
	trap - EXIT INT TERM
	log info "stopping"
	state="stopped"
	write_status
	release_lock
	rm -f "$PID_FILE"
	exit 0
}

daemon() {
	load_config
	mkdir -p "$STATE_DIR"

	if [ -f "$PID_FILE" ]; then
		oldpid=$(cat "$PID_FILE" 2>/dev/null)
		if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
			log error "already running (pid $oldpid)"
			exit 1
		fi
	fi

	echo "$$" > "$PID_FILE"
	service_start=$(now)
	state="starting"
	failures="0"
	last_check="0"
	last_success="0"
	last_failure="0"
	last_reboot="0"

	if [ -f "$REBOOT_FILE" ]; then
		reboots=$(wc -l < "$REBOOT_FILE" 2>/dev/null || echo 0)
		last_reboot=$(tail -n 1 "$REBOOT_FILE" 2>/dev/null)
		case "$last_reboot" in ''|*[!0-9]*) last_reboot="0" ;; esac
	else
		reboots="0"
		last_reboot="0"
	fi

	if ps w 2>/dev/null | grep -q '[m]odem_watchdog.sh'; then
		log warn "legacy modem_watchdog.sh is running; disable it to avoid double reboots"
	fi

	log info "starting (interval=${check_interval}s, threshold=${failure_threshold}, at_port=$at_port, wan=$wan_iface/$wan_device)"
	trap cleanup EXIT INT TERM

	run_cycle

	while true; do
		sleep "$check_interval" &
		wait $!
		run_cycle
	done
}

case "$1" in
	daemon) daemon ;;
	check) do_check "$2" ;;
	reboot) do_reboot ;;
	status) cat "$STATUS_FILE" 2>/dev/null || echo "state=stopped" ;;
	info) do_info "$2" ;;
	signal) do_signal ;;
	read) do_read ;;
	scan) do_scan ;;
	scan_stop) do_scan_stop ;;
	at) shift; do_at "$*" ;;
	logs) shift; do_logs "$1" ;;
	*)
		echo "Usage: $0 {daemon|check [--fast]|reboot|status|info [--force]|signal|read|scan|scan_stop|at <command>|logs [lines]}"
		exit 1
		;;
esac
