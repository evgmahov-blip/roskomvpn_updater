# roskomvpn_updater

Простой автообновлятор маршрутизации для Remnawave XRAY_JSON.

Он берет списки RoskomVPN, добавляет нужные домены в `direct` и не ломает уже существующие ручные правила: ручные правила всегда остаются выше автоматического списка.

## Что умеет

- обновляет списки `whitelist` и `category-ru`;
- использует обычные `domain:...`, без отдельного `geosite.dat`;
- не трогает `.ru`, если они уже обрабатываются текущими правилами;
- исключает IP-check сервисы и denylist;
- сохраняет backup перед изменением шаблона;
- сам получает список XRAY_JSON шаблонов из Remnawave;
- исходный и целевой шаблон выбираются по имени из пронумерованного списка — UUID вручную вводить не нужно;
- есть `--dry-run` для проверки без PATCH;
- есть systemd timer для автоматического обновления;
- есть безопасный `uninstall.sh`.

Рекомендуемое имя целевого шаблона: `RU_adguard_auto`.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/evgmahov-blip/roskomvpn_updater/main/install.sh -o install.sh
sudo bash install.sh
```

Установщик спросит домен Remnawave и API token, после чего сам покажет все доступные XRAY_JSON шаблоны. Нужно выбрать номер исходного и номер целевого шаблона. UUID установщик определит сам. Затем он спросит время запуска и timezone.

Пример выбора:

```text
Доступные XRAY_JSON шаблоны:
  1) Default
  2) RU_adguard
  3) RU_adguard_auto
  4) Balancer

Выбери ИСХОДНЫЙ шаблон по номеру: 2
[OK] Исходный шаблон: RU_adguard
Выбери ЦЕЛЕВОЙ шаблон по номеру: 3
[OK] Целевой шаблон: RU_adguard_auto
```

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
