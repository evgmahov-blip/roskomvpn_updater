# roskomvpn_updater

Безопасный updater для Remnawave XRAY_JSON шаблонов.

## Что делает

- берет существующий XRAY_JSON шаблон Remnawave как базовый;
- скачивает `whitelist` и `category-ru` из `hydraponique/roscomvpn-geosite`;
- преобразует записи в обычные `domain:...`, без зависимости от кастомного `geosite.dat`;
- исключает `.ru`, проверочные IP-сервисы и denylist;
- не переопределяет существующие ручные `domain:` / `full:` правила;
- добавляет auto-direct правило после ручных правил;
- сохраняет backup целевого шаблона перед PATCH;
- обновляет только UUID из `REMNA_TARGET_UUID`;
- отказывается применять подозрительно маленький или большой список.

Рекомендуемое имя целевого шаблона: `RU_adguard_auto`.

Имя шаблона не используется updater-ом для записи: привязка идет по UUID, поэтому шаблон можно безопасно переименовывать без изменения конфигурации updater-а.

## Установка

```bash
sudo bash install.sh
```

Установщик спросит:

- домен панели Remnawave;
- UUID исходного XRAY_JSON шаблона;
- UUID целевого XRAY_JSON шаблона;
- API token;
- время ежедневного запуска;
- timezone systemd timer.

API token сохраняется только локально в `/etc/remna-xray-auto-updater.env` с правами `600` и в GitHub не попадает.

## Ручной запуск

```bash
sudo systemctl start remna-xray-auto-updater.service
sudo journalctl -u remna-xray-auto-updater.service -n 100 --no-pager
```

## Проверка таймера

```bash
systemctl list-timers remna-xray-auto-updater.timer --no-pager
```

## Приоритет правил

Updater каждый запуск заново берет исходный шаблон. Ручные правила сохраняются в исходном порядке. Автоматический direct-список добавляется после них, поэтому ручные исключения имеют приоритет.

Схема:

```text
ручные block/direct/proxy правила
        ↓
roscomvpn auto-direct
        ↓
обычный fallback/proxy
```

Перед использованием на рабочем шаблоне рекомендуется сначала проверить отдельный целевой шаблон на одном клиенте: запуск ядра и фактический выбор `direct` / `proxy` в access log.

## Источники списков

- https://github.com/hydraponique/roscomvpn-geosite
- https://github.com/hydraponique/roscomvpn-routing
