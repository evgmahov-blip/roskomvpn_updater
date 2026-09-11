#!/usr/bin/env bash
set -u

printf '%s\n' '#################### НАЧАЛО ВЫВОДА: ROSKOMVPN UPDATER UNINSTALL ####################'

if [ "$(id -u)" -ne 0 ]; then
    echo '[ОШИБКА] Запусти uninstall.sh от root.'
    printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER UNINSTALL ####################'
    exit 1
fi

base='/opt/remna-xray-auto-updater'
env_file='/etc/remna-xray-auto-updater.env'
service_file='/etc/systemd/system/remna-xray-auto-updater.service'
timer_file='/etc/systemd/system/remna-xray-auto-updater.timer'

echo '[1] Останавливаю и отключаю timer...'
systemctl disable --now remna-xray-auto-updater.timer >/dev/null 2>&1 || true

echo '[2] Удаляю systemd units...'
rm -f "$service_file" "$timer_file"
systemctl daemon-reload
systemctl reset-failed remna-xray-auto-updater.service >/dev/null 2>&1 || true

echo '[3] Удаляю локальный API env...'
rm -f "$env_file"

echo '[4] Удаляю updater и generated preview...'
rm -f "$base/update.py" "$base/generated.json"
rm -rf "$base/__pycache__"

if [ -d "$base/backups" ]; then
    echo "[OK] Backups сохранены: $base/backups"
else
    rmdir "$base" >/dev/null 2>&1 || true
fi

echo '[OK] Updater удален. Шаблоны Remnawave не изменялись.'
printf '%s\n' '#################### КОНЕЦ ВЫВОДА: ROSKOMVPN UPDATER UNINSTALL ####################'
