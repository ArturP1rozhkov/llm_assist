#!/usr/bin/env bash
# Скачивает сертификаты НУЦ Минцифры и собирает из них один CA-бандл.
# Зачем: Python-клиенты (httpx/gigachat SDK) не используют системное хранилище
# сертификатов, а API GigaChat подписан цепочкой, которой в системе нет.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p certs

ROOT_URL="https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt"
SUB_URL="https://gu-st.ru/content/lending/russian_trusted_sub_ca_pem.crt"

curl -fsSL -o certs/russian_trusted_root_ca.crt "$ROOT_URL"
curl -fsSL -o certs/russian_trusted_sub_ca.crt  "$SUB_URL"

# gu-st.ru отдаёт файлы с CRLF — OpenSSL-загрузчик на них спотыкается ("PEM lib")
sed -i 's/\r$//' certs/russian_trusted_root_ca.crt certs/russian_trusted_sub_ca.crt

# SDK принимает ОДИН файл, а цепочка состоит из двух звеньев: root + sub CA.
# printf '\n' обязателен: без перевода строки "-----END CERTIFICATE----------BEGIN..."
# склеиваются в одну строку, и бандл перестаёт парситься.
{
  cat certs/russian_trusted_root_ca.crt; printf '\n'
  cat certs/russian_trusted_sub_ca.crt;  printf '\n'
} > certs/trusted_bundle.pem

echo "OK: сертификатов в бандле — $(grep -c 'BEGIN CERTIFICATE' certs/trusted_bundle.pem)"
python3 -c "import ssl; print('ssl: бандл валиден, CA в контексте —', len(ssl.create_default_context(cafile='certs/trusted_bundle.pem').get_ca_certs()))"
