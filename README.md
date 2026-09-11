# roskomvpn_updater

Простой автообновлятор маршрутизации для Remnawave XRAY_JSON.

Он берет списки RoskomVPN, добавляет нужные домены в `direct` и не ломает уже существующие ручные правила: ручные правила всегда остаются выше автоматического списка.

## Что умеет

- обновляет списки `whitelist` и `category-ru`;
- использует обычные `domain:...`, без отдельного `geosite.dat`;
- не трогает `.ru`, если они уже обрабатываются текущими правилами;
- исключает IP-check сервисы и denylist;
- сохраняет backup перед изменением шаблона;
- работает по UUID шаблона, поэтому его можно переименовывать;
- есть `--dry-run` для проверки без PATCH;
- есть systemd timer для автоматического обновления;
- есть безопасный `uninstall.sh`.

Рекомендуемое имя целевого шаблона: `RU_adguard_auto`.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/evgmahov-blip/roskomvpn_updater/main/install.sh -o install.sh
sudo bash install.sh
```

Установщик спросит домен Remnawave, UUID исходного и целевого XRAY_JSON шаблонов, API token, время запуска и timezone.

API token хранится только локально в `/etc/remna-xray-auto-updater.env` с правами `600`.

## Проверка без изменений

```bash
set -a
. /etc/remna-xray-auto-updater.env
set +a
/opt/remna-xray-auto-updater/update.py --dry-run
unset REMNA_TOKEN
```

`--dry-run` скачает списки, соберет итоговый JSON и покажет, есть ли изменения, но не сделает backup и не отправит PATCH в Remnawave.

## Ручной запуск

```bash
sudo systemctl start remna-xray-auto-updater.service
sudo journalctl -u remna-xray-auto-updater.service -n 100 --no-pager
```

## Проверка таймера

```bash
systemctl list-timers remna-xray-auto-updater.timer --no-pager
```

## Удаление

```bash
curl -fsSL https://raw.githubusercontent.com/evgmahov-blip/roskomvpn_updater/main/uninstall.sh -o uninstall.sh
sudo bash uninstall.sh
```

Удаление отключает timer, удаляет updater и локальный API token. Backups оставляет на месте. Шаблоны Remnawave не удаляет и не откатывает.

## Как идет трафик

```text
ручные правила
      ↓
auto-direct RoskomVPN
      ↓
обычный proxy / fallback
```

Источники списков:

- https://github.com/hydraponique/roscomvpn-geosite
- https://github.com/hydraponique/roscomvpn-routing
