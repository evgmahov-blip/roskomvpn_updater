#!/usr/bin/env python3

import copy
import datetime
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.request

DRY_RUN = "--dry-run" in sys.argv[1:]

API_DOMAIN = os.environ.get("REMNA_API_DOMAIN", "").strip()
SOURCE_UUID = os.environ.get("REMNA_SOURCE_UUID", "").strip()
TARGET_UUID = os.environ.get("REMNA_TARGET_UUID", "").strip()
TOKEN = os.environ.get("REMNA_TOKEN", "").strip()

BASE = pathlib.Path("/opt/remna-xray-auto-updater")
BACKUPS = BASE / "backups"

SOURCES = [
    "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/whitelist",
    "https://raw.githubusercontent.com/hydraponique/roscomvpn-geosite/master/data/category-ru",
]

DENY_EXACT = {
    "ipify.org",
    "checkip.amazonaws.com",
    "ifconfig.me",
    "ipapi.is",
    "iplocate.io",
    "ip.sb",
    "2ip.ru",
    "windsurf.com",
    "yandex",
    "psk",
}

if not API_DOMAIN:
    raise SystemExit("[ОШИБКА] REMNA_API_DOMAIN отсутствует")
if not SOURCE_UUID:
    raise SystemExit("[ОШИБКА] REMNA_SOURCE_UUID отсутствует")
if not TARGET_UUID:
    raise SystemExit("[ОШИБКА] REMNA_TARGET_UUID отсутствует")
if not TOKEN:
    raise SystemExit("[ОШИБКА] REMNA_TOKEN отсутствует")
if SOURCE_UUID == TARGET_UUID:
    raise SystemExit("[ОШИБКА] SOURCE_UUID и TARGET_UUID совпадают. Обновление запрещено")

API_BASE = f"https://{API_DOMAIN}/api"
BASE.mkdir(parents=True, exist_ok=True)
BACKUPS.mkdir(parents=True, exist_ok=True)


def curl_json(method, path, body=None):
    cmd = [
        "curl", "-fsS",
        "--resolve", f"{API_DOMAIN}:443:127.0.0.1",
        "--connect-timeout", "5",
        "--max-time", "30",
        "-X", method,
        "-H", f"Authorization: Bearer {TOKEN}",
        "-H", "Accept: application/json",
    ]

    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "--data-binary", "@-"]

    cmd.append(API_BASE + path)

    p = subprocess.run(
        cmd,
        input=json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    if p.returncode != 0:
        raise RuntimeError(p.stderr.decode("utf-8", errors="replace").strip())

    return json.loads(p.stdout.decode("utf-8"))


def download(url):
    req = urllib.request.Request(url, headers={"User-Agent": "roskomvpn-updater/1.3"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")


def parse_domains(text):
    result = set()

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        if line.startswith("domain:"):
            domain = line[7:].strip()
        elif re.fullmatch(r"[A-Za-z0-9._-]+", line):
            domain = line
        else:
            continue

        domain = domain.lower().rstrip(".")

        if not domain or domain.endswith(".ru"):
            continue
        if domain in DENY_EXACT:
            continue
        if "." not in domain:
            continue

        result.add(domain)

    return result


def extract_manual_domains(rules):
    manual = set()

    for rule in rules:
        if not isinstance(rule, dict):
            continue

        for entry in rule.get("domain", []) or []:
            if not isinstance(entry, str):
                continue

            value = entry.strip().lower()
            if value.startswith("domain:"):
                manual.add(value[7:].rstrip("."))
            elif value.startswith("full:"):
                manual.add(value[5:].rstrip("."))

    return manual


def is_catch_all(rule):
    if not isinstance(rule, dict) or rule.get("type") != "field":
        return False
    network = str(rule.get("network", "")).replace(" ", "").lower()
    return network == "tcp,udp"


if DRY_RUN:
    print("[DRY-RUN] Режим проверки: PATCH и backup выполняться не будут.")

print("[1] Читаю исходный XRAY_JSON шаблон...")
source_response = curl_json("GET", f"/subscription-templates/{SOURCE_UUID}")
source = source_response.get("response", source_response)
cfg = source.get("templateJson")

if not isinstance(cfg, dict):
    raise SystemExit("[ОШИБКА] В исходном шаблоне нет templateJson")

source_rules = cfg.get("routing", {}).get("rules", [])
manual_domains = extract_manual_domains(source_rules)
print(f"[OK] Ручных domain/full записей: {len(manual_domains)}")

print("[2] Скачиваю RoscomVPN списки...")
domains = set()

for url in SOURCES:
    text = download(url)
    current = parse_domains(text)
    domains.update(current)
    print(f"[OK] {url.rsplit('/', 1)[-1]}: {len(current)} после фильтрации")

before_conflict_filter = len(domains)
domains -= manual_domains
conflicts_removed = before_conflict_filter - len(domains)
domains = sorted(domains)

print(f"[OK] Исключено совпадений с ручными domain/full: {conflicts_removed}")
print(f"[OK] Auto-direct доменов: {len(domains)}")

if len(domains) < 50:
    raise SystemExit(f"[ОШИБКА] Подозрительно мало доменов: {len(domains)}. Обновление запрещено")
if len(domains) > 1000:
    raise SystemExit(f"[ОШИБКА] Подозрительно много доменов: {len(domains)}. Обновление запрещено")

new_cfg = copy.deepcopy(cfg)
rules = new_cfg.setdefault("routing", {}).setdefault("rules", [])

auto_rule = {
    "type": "field",
    "domain": [f"domain:{x}" for x in domains],
    "outboundTag": "direct",
}

insert_at = len(rules)
for i, rule in enumerate(rules):
    if is_catch_all(rule):
        insert_at = i
        break

rules.insert(insert_at, auto_rule)

preview = BASE / "generated.json"
preview.write_text(json.dumps(new_cfg, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"[OK] Auto-rule позиция: {insert_at + 1}")
print(f"[OK] Routing rules всего: {len(rules)}")
print(f"[OK] Preview: {preview}")

target_response = curl_json("GET", f"/subscription-templates/{TARGET_UUID}")
target = target_response.get("response", target_response)
old_cfg = target.get("templateJson")

if old_cfg == new_cfg:
    print("[OK] Изменений нет. PATCH не требуется.")
    sys.exit(0)

if DRY_RUN:
    print("[DRY-RUN] Изменения есть, но целевой шаблон НЕ изменен.")
    print(f"[AUTO DOMAINS] {len(domains)}")
    print(f"[MANUAL MATCHES REMOVED] {conflicts_removed}")
    sys.exit(0)

timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
backup = BACKUPS / f"target-{TARGET_UUID}-{timestamp}.json"
backup.write_text(json.dumps(target, ensure_ascii=False, indent=2), encoding="utf-8")
os.chmod(backup, 0o600)
print(f"[OK] Backup TARGET: {backup}")

body = {"uuid": TARGET_UUID, "templateJson": new_cfg}

print("[3] PATCH целевого XRAY_JSON шаблона...")
updated_response = curl_json("PATCH", "/subscription-templates", body)
updated = updated_response.get("response", updated_response)

if updated.get("uuid") != TARGET_UUID:
    raise SystemExit("[ОШИБКА] API вернул неожиданный UUID")

print("[OK] Целевой XRAY_JSON обновлен.")
print(f"[AUTO DOMAINS] {len(domains)}")
print(f"[MANUAL MATCHES REMOVED] {conflicts_removed}")
