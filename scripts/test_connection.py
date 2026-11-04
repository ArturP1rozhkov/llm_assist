"""тест окружения: ключ, сертификат, токен, список доступных моделей.

Запуск:
    source .venv/bin/activate
    python scripts/test_connection.py

"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from gigachat import GigaChat

REPO_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(REPO_ROOT / ".env")

credentials = os.getenv("GIGACHAT_CREDENTIALS")
ca_bundle = os.getenv("GIGACHAT_CA_BUNDLE_FILE")

if not credentials:
    sys.exit("GIGACHAT_CREDENTIALS не задан — заполните .env (см. .env.example)")

# Печатаем только префикс: ключ не должен попадать в ноутбук, логи и скриншоты
print(f"Ключ авторизации: {credentials[:8]}… (длина {len(credentials)})")

ca_path = REPO_ROOT / (ca_bundle or "")
print(f"CA-бандл: {ca_path} — {'найден' if ca_path.is_file() else 'НЕ НАЙДЕН'}")
if not ca_path.is_file():
    sys.exit("Сертификаты не скачаны: выполните bash scripts/fetch_certs.sh")

with GigaChat(
    credentials=credentials,
    scope="GIGACHAT_API_PERS",
    ca_bundle_file=str(ca_path),
    timeout=60.0,
) as client:
    token = client.get_token()
    print(f"Токен получен, действует до: {token.expires_at}")

    models = client.get_models()
    print(f"Доступные модели ({len(models.data)}):")
    for m in models.data:
        print(f"  - {m.id_} (owned_by={m.owned_by})")

print("\nОкружение готово: ключ, сертификаты и сеть до GigaChat работают.")
