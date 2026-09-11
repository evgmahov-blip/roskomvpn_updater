#!/usr/bin/env bash
set -u

printf '%s\n' '#################### НАЧАЛО ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'

if [ "$(id -u)" -ne 0 ]; then
    echo '[ОШИБКА] Запусти установщик от root.'
    printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'
    exit 1
fi

base='/opt/remna-xray-auto-updater'
env_file='/etc/remna-xray-auto-updater.env'
service_file='/etc/systemd/system/remna-xray-auto-updater.service'
timer_file='/etc/systemd/system/remna-xray-auto-updater.timer'
repo_raw='https://raw.githubusercontent.com/evgmahov-blip/roskomvpn_updater/main'

read -r -p 'Домен Remnawave [remna.example.com]: ' api_domain
read -r -p 'UUID исходного XRAY_JSON шаблона: ' source_uuid
read -r -p 'UUID целевого XRAY_JSON шаблона: ' target_uuid
read -r -p 'Время ежедневного запуска [04:20]: ' run_time
read -r -p 'Timezone systemd [Europe/Moscow]: ' timezone

api_domain="${api_domain:-remna.example.com}"
run_time="${run_time:-04:20}"
timezone="${timezone:-Europe/Moscow}"

if [ -z "$source_uuid" ] || [ -z "$target_uuid" ]; then
    echo '[ОШИБКА] UUID не могут быть пустыми.'
    printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'
    exit 1
fi

if [ "$source_uuid" = "$target_uuid" ]; then
    echo '[ОШИБКА] Исходный и целевой UUID совпадают. Установка остановлена.'
    printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'
    exit 1
fi

printf 'Remnawave API token: '
IFS= read -r -s token
printf '\n'

if [ -z "$token" ]; then
    echo '[ОШИБКА] API token пустой.'
    printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'
    exit 1
fi

mkdir -p "$base/backups"
chmod 700 "$base"
chmod 700 "$base/backups"

echo '[1] Загружаю update.py...'
if ! curl -fsS --connect-timeout 10 --max-time 30 "$repo_raw/update.py" -o "$base/update.py"; then
    echo '[ОШИБКА] Не удалось скачать update.py.'
    unset token
    printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'
    exit 1
fi
chmod 700 "$base/update.py"

if ! python3 -m py_compile "$base/update.py"; then
    echo '[ОШИБКА] Проверка синтаксиса update.py не пройдена.'
    unset token
    printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'
    exit 1
fi

echo '[OK] update.py загружен и проверен.'

echo '[2] Создаю защищенный env-файл...'
umask 077
cat > "$env_file" <<EOF
REMNA_API_DOMAIN=$api_domain
REMNA_SOURCE_UUID=$source_uuid
REMNA_TARGET_UUID=$target_uuid
REMNA_TOKEN=$token
EOF
chmod 600 "$env_file"
unset token

echo '[3] Создаю systemd service...'
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

echo '[4] Создаю systemd timer...'
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

echo '[5] Выполняю контрольный запуск...'
if ! systemctl start remna-xray-auto-updater.service; then
    echo '[ОШИБКА] Контрольный запуск завершился ошибкой. Timer не включен.'
    journalctl -u remna-xray-auto-updater.service -n 50 --no-pager || true
    printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'
    exit 1
fi

result="$(systemctl show remna-xray-auto-updater.service -p Result --value)"
if [ "$result" != 'success' ]; then
    echo "[ОШИБКА] Service Result=$result. Timer не включен."
    journalctl -u remna-xray-auto-updater.service -n 50 --no-pager || true
    printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'
    exit 1
fi

systemctl enable --now remna-xray-auto-updater.timer

echo '[OK] Установка завершена.'
systemctl list-timers remna-xray-auto-updater.timer --no-pager || true
journalctl -u remna-xray-auto-updater.service -n 30 --no-pager || true

printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER INSTALL ####################'
