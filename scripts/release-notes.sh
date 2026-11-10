#!/bin/sh
set -eu

RELEASE_DIR="${1:-release}"
TAG="${2:-${GITHUB_REF_NAME:-}}"
VERSION="${TAG#v}"
REPO="${GITHUB_REPOSITORY:-freebsdmax/modemwatch}"
VERSIONS="${VERSIONS:-23.05.6 24.10.8 25.12.6}"

if [ -z "$TAG" ]; then
	echo "usage: $0 <release-dir> <tag>" >&2
	exit 2
fi

human_bytes() {
	awk -v b="$1" 'BEGIN {
		if (b >= 1048576) printf "%.1f MB", b / 1048576;
		else if (b >= 1024) printf "%.1f KB", b / 1024;
		else printf "%d B", b;
	}'
}

human_size() {
	human_bytes "$(wc -c < "$1" | tr -d ' ')"
}

pkg_file() {
	pkg="$1"
	ver="$2"
	ext="$3"
	for f in "$RELEASE_DIR/${pkg}_${ver}_"*".${ext}"; do
		if [ -f "$f" ]; then
			basename "$f"
			return 0
		fi
	done
	return 1
}

pkg_desc() {
	case "$1" in
		modemwatch) echo "Сервіс, CLI та watchdog" ;;
		luci-app-modemwatch) echo "Веб-інтерфейс LuCI" ;;
		luci-i18n-modemwatch-uk) echo "Українська локалізація" ;;
		*) echo "$1" ;;
	esac
}

changes=$(awk -v ver="$VERSION" '
	$0 ~ "^## \\[" ver "\\]" { found = 1; next }
	found && /^## \[/ { exit }
	found { print }
' CHANGELOG.md | sed '/./,$!d')

if [ -z "$changes" ]; then
	changes="_Інформацію про зміни цієї версії ще не додано до \`CHANGELOG.md\`._"
fi

prev_tag=$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)
if [ -n "$prev_tag" ]; then
	compare_url="https://github.com/${REPO}/compare/${prev_tag}...${TAG}"
	compare_text="${prev_tag}...${TAG}"
else
	compare_url="https://github.com/${REPO}/releases"
	compare_text="усі релізи"
fi

cat <<EOF
# modemwatch ${VERSION}

Менеджер модема **Quectel EC200A** для OpenWrt: сервіс спостереження,
веб-інтерфейс LuCI, діагностика сигналу, керування діапазонами та
пошук мереж.

## Що нового в ${VERSION}

${changes}

## Можливості

- Періодична перевірка інтернету через ping, DNS і HTTP з автоматичним
  перезавантаженням модема після серії невдач.
- Сторінка **Стан**: оператор із MCC/MNC, мережа, WAN IP, час роботи,
  передані дані за сесію, якість LTE, CSQ, RSSI, RSRP, SINR, RSRQ, Band.
- Сторінка **Сигнал**: головний показник RSRQ, картка CSQ, оператор
  і діапазон із частотою (наприклад, \`B3 (1800 MHz)\`).
- Окрема вкладка **Журнал** з ручним та автоматичним оновленням.
- **Налаштування модема**: читання інформації, вибір діапазонів,
  USB/NAT expert mode.
- **Пошук мереж** з назвами операторів і MCC/MNC та оновленням бази
  операторів.
- CLI: \`status\`, \`check\`, \`reboot\`, \`info\`, \`at\`, \`logs\`.

## Пакети в цьому релізі

EOF

lang_table=$(awk -F'|' '!/^#/ && NF >= 3 { printf "| `%s` | %s |\n", $1, $3 }' scripts/languages.txt)
lang_count=$(awk -F'|' '!/^#/ && NF >= 3 { n++ } END { print n + 0 }' scripts/languages.txt)

for ver in $VERSIONS; do
	case "$ver" in
		25.12.6) ext="apk" ;;
		*) ext="ipk" ;;
	esac

	echo "### OpenWrt ${ver} (\`${ext}\`)"
	echo
	echo "| Компонент | Файл | Розмір |"
	echo "| --- | --- | ---: |"

	for pkg in modemwatch luci-app-modemwatch; do
		if ! file=$(pkg_file "$pkg" "$ver" "$ext"); then
			echo "| $(pkg_desc "$pkg") | _відсутній_ | — |"
			continue
		fi
		echo "| $(pkg_desc "$pkg") | \`${file}\` | $(human_size "$RELEASE_DIR/$file") |"
	done

	if file=$(pkg_file "luci-i18n-modemwatch-uk" "$ver" "$ext"); then
		echo "| Українська локалізація | \`${file}\` | $(human_size "$RELEASE_DIR/$file") |"
	else
		echo "| Українська локалізація | _відсутня_ | — |"
	fi

	tarball="modemwatch-${ver}-all.tar.gz"
	if [ -f "$RELEASE_DIR/$tarball" ]; then
		echo "| Усі пакети одним архівом | \`${tarball}\` | $(human_size "$RELEASE_DIR/$tarball") |"
	fi

	echo
	echo "Окремо в релізі опубліковано лише українську локалізацію."
	if [ "$lang_count" -gt 1 ]; then
		echo "Пакети для решти $((lang_count - 1)) мов входять до \`${tarball}\`."
	fi
	echo
done

cat <<EOF
## Мови перекладу

Пакети перекладу доступні для **${lang_count} мов**. У релізі окремо
опубліковано лише українську локалізацію (\`luci-i18n-modemwatch-uk\`),
а пакети для решти мов входять до загального архіву
\`modemwatch-<версія>-all.tar.gz\`.

<details>
<summary>Повний список мов</summary>

| Код | Мова |
| --- | --- |
${lang_table}

</details>

EOF

cat <<EOF
## Встановлення

Скопіюйте потрібні файли на роутер (наприклад, у \`/tmp\`) і виконайте
команди для своєї версії OpenWrt.

### OpenWrt 23.05 / 24.10 (\`.ipk\`)

\`\`\`sh
opkg update
opkg install modemwatch_24.10.8_*.ipk \\
  luci-app-modemwatch_24.10.8_*.ipk \\
  luci-i18n-modemwatch-uk_24.10.8_*.ipk
\`\`\`

Для 23.05 замініть \`24.10.8\` на \`23.05.6\`. Пакет \`luci-i18n-modemwatch-uk\`
є окремим файлом у релізі. Пакети для інших мов входять до
\`modemwatch-24.10.8-all.tar.gz\`: розпакуйте архів і встановіть потрібний
\`luci-i18n-modemwatch-<lang>_...\`.

### OpenWrt 25.12 (\`.apk\`)

\`\`\`sh
apk update
apk add --allow-untrusted modemwatch_25.12.6_*.apk \\
  luci-app-modemwatch_25.12.6_*.apk \\
  luci-i18n-modemwatch-uk_25.12.6_*.apk
\`\`\`

### Після встановлення

\`\`\`sh
/etc/init.d/modemwatch enable
/etc/init.d/modemwatch start
\`\`\`

Відкрийте LuCI: **Модем → Modemwatch**.

## Залежності

| Пакет | Залежності |
| --- | --- |
| \`modemwatch\` | \`picocom\`, \`sms-tool\`, \`ubus\` |
| \`luci-app-modemwatch\` | \`modemwatch\`, \`luci-compat\`, \`luci-lua-runtime\`, \`luci-lib-jsonc\`, \`luci-lib-nixio\`, \`curl\`, \`ca-bundle\` |
| \`luci-i18n-modemwatch-<lang>\` | \`luci-app-modemwatch\`, \`luci-base\` |

Пакетний менеджер підтягне залежності автоматично. Якщо чогось не
вистачає, він покаже команду для встановлення, наприклад:

\`\`\`sh
opkg update && opkg install picocom sms-tool
# або для 25.12:
apk update && apk add picocom sms-tool
\`\`\`

## Примітки

- Усі пакети архітектурно незалежні (\`all\`) і працюють на будь-якій
  архітектурі OpenWrt.
- За замовчуванням використовується AT-порт \`/dev/ttyUSB2\` і WAN
  \`usb0\`; їх можна змінити в UCI/LuCI.
- Пакети не залежать від \`3ginfo-lite\`, \`modemdata\` або \`modemband\`.
- Якщо на роутері вже працює старий \`/usr/bin/modem_watchdog.sh\`,
  вимкніть його, щоб уникнути подвійних перезавантажень модема.
- Скріншоти та документація: [README.md](https://github.com/${REPO}#readme).

## Скріншоти

- [Стан](https://raw.githubusercontent.com/${REPO}/${TAG}/docs/screenshots/status.png)
- [Сигнал](https://raw.githubusercontent.com/${REPO}/${TAG}/docs/screenshots/signal.png)
- [Журнал](https://raw.githubusercontent.com/${REPO}/${TAG}/docs/screenshots/log.png)
- [Налаштування модема](https://raw.githubusercontent.com/${REPO}/${TAG}/docs/screenshots/modem-settings.png)
- [Пошук мереж](https://raw.githubusercontent.com/${REPO}/${TAG}/docs/screenshots/network-search.png)

## Повний список змін

[${compare_text}](${compare_url})
EOF
