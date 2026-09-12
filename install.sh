#!/usr/bin/env bash
set -u

printf '%s\n' '#################### НАЧАЛО ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'

finish() {
    printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'
}

fail() {
    echo "[ОШИБКА] $1"
    finish
    exit 1
}

if [ "$(id -u)" -ne 0 ]; then
    fail 'Запусти установщик от root.'
fi

for cmd in curl python3 awk systemctl flock; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Не найдена команда: $cmd"
done

base='/opt/remna-xray-auto-updater'
env_file='/etc/remna-xray-auto-updater.env'
service_file='/etc/systemd/system/remna-xray-auto-updater.service'
timer_file='/etc/systemd/system/remna-xray-auto-updater.timer'
repo_raw='https://raw.githubusercontent.com/evgmahov-blip/roskomvpn_updater/main'

read -r -p 'Домен Remnawave [remna.example.com]: ' api_domain
api_domain="${api_domain:-remna.example.com}"
api_domain="${api_domain#https://}"
api_domain="${api_domain#http://}"
api_domain="${api_domain%%/*}"

printf 'Remnawave API token: '
IFS= read -r -s token
printf '\n'
[ -n "$token" ] || fail 'API token пустой.'

api_base="https://${api_domain}/api"
templates_json="$(mktemp)"
templates_tsv="$(mktemp)"
trap 'rm -f "$templates_json" "$templates_tsv"' EXIT

echo '[1] Получаю список XRAY_JSON шаблонов из Remnawave...'

http_code="$(
    curl -sS \
      --resolve "${api_domain}:443:127.0.0.1" \
      --connect-timeout 5 \
      --max-time 30 \
      -H "Authorization: Bearer $token" \
      -H 'Accept: application/json' \
      -o "$templates_json" \
      -w '%{http_code}' \
      "${api_base}/subscription-templates"
)" || fail 'Не удалось обратиться к API Remnawave.'

[ "$http_code" = '200' ] || {
    echo "[ОШИБКА] Remnawave API вернул HTTP $http_code"
    cat "$templates_json" 2>/dev/null || true
    finish
    exit 1
}

if ! python3 - "$templates_json" > "$templates_tsv" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

x = data.get("response", data) if isinstance(data, dict) else data
items = None

if isinstance(x, list):
    items = x
elif isinstance(x, dict):
    for key in ("subscriptionTemplates", "templates", "items", "data"):
        if isinstance(x.get(key), list):
            items = x[key]
            break

if items is None:
    raise SystemExit(2)

rows = []
for item in items:
    if not isinstance(item, dict):
        continue
    template_type = str(item.get("templateType") or item.get("type") or "").upper()
    if template_type != "XRAY_JSON":
        continue
    name = str(item.get("name") or "").replace("\t", " ").replace("\n", " ").strip()
    uuid = str(item.get("uuid") or "").strip()
    if name and uuid:
        rows.append((name, uuid))

rows.sort(key=lambda row: row[0].casefold())
for i, (name, uuid) in enumerate(rows, 1):
    print(f"{i}\t{name}\t{uuid}")
PY
then
    fail 'Не удалось разобрать список шаблонов Remnawave.'
fi

count="$(wc -l < "$templates_tsv" | tr -d ' ')"
[ "$count" -ge 2 ] || fail 'Нужно минимум два XRAY_JSON шаблона: исходный и целевой.'

echo
echo 'Доступные XRAY_JSON шаблоны:'
awk -F '\t' '{printf "  %s) %s\n", $1, $2}' "$templates_tsv"
echo

select_template() {
    prompt="$1"
    while true; do
        read -r -p "$prompt" choice
        case "$choice" in
            ''|*[!0-9]*)
                echo '[ОШИБКА] Введи номер из списка.' >&2
                continue
                ;;
        esac
        row="$(awk -F '\t' -v n="$choice" '$1 == n {print; exit}' "$templates_tsv")"
        if [ -z "$row" ]; then
            echo '[ОШИБКА] Такого номера нет.' >&2
            continue
        fi
        printf '%s\n' "$row"
        return 0
    done
}

source_row="$(select_template 'Выбери ИСХОДНЫЙ шаблон по номеру: ')"
source_name="$(printf '%s\n' "$source_row" | awk -F '\t' '{print $2}')"
source_uuid="$(printf '%s\n' "$source_row" | awk -F '\t' '{print $3}')"

echo "[OK] Исходный шаблон: $source_name"

target_row="$(select_template 'Выбери ЦЕЛЕВОЙ шаблон по номеру: ')"
target_name="$(printf '%s\n' "$target_row" | awk -F '\t' '{print $2}')"
target_uuid="$(printf '%s\n' "$target_row" | awk -F '\t' '{print $3}')"

echo "[OK] Целевой шаблон: $target_name"

if [ "$source_uuid" = "$target_uuid" ]; then
    fail 'Исходный и целевой шаблон совпадают. Выбери разные шаблоны.'
fi

read -r -p 'Время ежедневного запуска [04:20]: ' run_time
read -r -p 'Timezone systemd [Europe/Moscow]: ' timezone
run_time="${run_time:-04:20}"
timezone="${timezone:-Europe/Moscow}"

case "$run_time" in
    [0-2][0-9]:[0-5][0-9]) ;;
    *) fail 'Время должно быть в формате HH:MM.' ;;
esac

hour="${run_time%%:*}"
if [ "$hour" -gt 23 ]; then
    fail 'Час должен быть от 00 до 23.'
fi

mkdir -p "$base/backups"
chmod 700 "$base"
chmod 700 "$base/backups"

echo '[2] Загружаю update.py...'
if ! curl -fsS --connect-timeout 10 --max-time 30 "$repo_raw/update.py" -o "$base/update.py"; then
    unset token
    fail 'Не удалось скачать update.py.'
fi
chmod 700 "$base/update.py"

if ! python3 -m py_compile "$base/update.py"; then
    unset token
    fail 'Проверка синтаксиса update.py не пройдена.'
fi

echo '[OK] update.py загружен и проверен.'

echo '[3] Создаю защищенный env-файл...'
umask 077
cat > "$env_file" <<EOF
REMNA_API_DOMAIN=$api_domain
REMNA_SOURCE_UUID=$source_uuid
REMNA_TARGET_UUID=$target_uuid
REMNA_TOKEN=$token
EOF
chmod 600 "$env_file"
unset token

echo '[4] Создаю systemd service...'
cat > "$service_file" <<'EOF'
[Unit]
Description=Remnawave XRAY JSON RoskomVPN auto updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/remna-xray-auto-updater.env
ExecStart=/usr/bin/flock -n /run/remna-xray-auto-updater.lock /opt/remna-xray-auto-updater/update.py
User=root
Group=root
NoNewPrivileges=true
PrivateTmp=true
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectKernelLogs=true
StandardOutput=journal
StandardError=journal
EOF
chmod 644 "$service_file"

echo '[5] Создаю systemd timer...'
cat > "$timer_file" <<EOF
[Unit]
Description=Daily Remnawave XRAY JSON RoskomVPN auto update

[Timer]
OnCalendar=*-*-* ${run_time}:00 ${timezone}
Persistent=true
Unit=remna-xray-auto-updater.service

[Install]
WantedBy=timers.target
EOF
chmod 644 "$timer_file"

systemctl daemon-reload

echo '[6] Выполняю контрольный запуск...'
if ! systemctl start remna-xray-auto-updater.service; then
    echo '[ОШИБКА] Контрольный запуск завершился ошибкой. Timer не включен.'
    journalctl -u remna-xray-auto-updater.service -n 50 --no-pager || true
    finish
    exit 1
fi

result="$(systemctl show remna-xray-auto-updater.service -p Result --value)"
if [ "$result" != 'success' ]; then
    echo "[ОШИБКА] Service Result=$result. Timer не включен."
    journalctl -u remna-xray-auto-updater.service -n 50 --no-pager || true
    finish
    exit 1
fi

systemctl enable --now remna-xray-auto-updater.timer

echo '[OK] Установка завершена.'
echo "[SOURCE] $source_name"
echo "[TARGET] $target_name"
systemctl list-timers remna-xray-auto-updater.timer --no-pager || true
journalctl -u remna-xray-auto-updater.service -n 30 --no-pager || true

finish
