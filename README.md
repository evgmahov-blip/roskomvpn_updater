# roskomvpn_updater

Безопасный updater для Remnawave XRAY_JSON шаблонов.

Что делает:

- берет существующий XRAY_JSON шаблон Remnawave как базовый;
- скачивает `whitelist` и `category-ru` из `hydraponique/roscomvpn-geosite`;
- преобразует записи в обычные `domain:...`, без зависимости от кастомного `geosite.dat`;
- исключает `.ru`, проверочные IP-сервисы и заданный denylist;
- не переопределяет существующие ручные `domain:` / `full:` правила;
- вставляет auto-direct правило после ручных правил;
- делает backup целевого тестового шаблона перед PATCH;
- обновляет только UUID, заданный как `REMNA_TARGET_UUID`;
- отказывается применять подозрительно маленький или большой список.

## Установка

```bash
sudo bash install.sh
```

Установщик спросит:

- домен панели Remnawave;
- UUID исходного XRAY_JSON шаблона;
- UUID целевого тестового XRAY_JSON шаблона;
- API token;
- время ежедневного запуска.

Токен сохраняется только локально в `/etc/remna-xray-auto-updater.env` с правами `600`.

## Ручной запуск

```bash
sudo systemctl start remna-xray-auto-updater.service
sudo journalctl -u remna-xray-auto-updater.service -n 100 --no-pager
```

## Таймер

```bash
systemctl list-timers remna-xray-auto-updater.timer --no-pager
```

## Важное

Сначала используйте отдельный тестовый XRAY_JSON шаблон. Не указывайте рабочий шаблон как `REMNA_TARGET_UUID`, пока не проверите запуск ядра и маршрутизацию на клиенте.

Исходники списков:

- `https://github.com/hydraponique/roscomvpn-geosite`
- `https://github.com/hydraponique/roscomvpn-routing`
