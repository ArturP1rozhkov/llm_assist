

## Разбор решения задания

### Прежде всего:
- получил ключи авторизации на ресурсе Giga от Сбера (https://developers.sber.ru/docs/ru/gigachat/tariffs/individual-tariffs#terms-update) вместо недоступного в РФ Groq, с соответствующим изменением сценария выполнения работы;
- скачал и сложил в репозиторий сертификаты НУЦ Минцифры, без которых Python-клиент не устанавливает TLS-соединение с GigaChat (скриптом);
- настроил рабочее окружение и проверил связку «ключ + сертификат + сеть» отдельным скриптом до запуска ноутбука;
- собрал ноутбук из шаблона: разделы 0-7 сохранены, код и тексты обращений живут в самом ноутбуке, вспомогательные скрипты вынесены в `scripts/`.

```bash
cd /srv/repos/llm_assist

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# сертификаты НУЦ Минцифры и сборка одного CA-бандла
bash scripts/fetch_certs.sh

# шаблон переменных окружения
cp .env.example .env
```

вывод `bash scripts/fetch_certs.sh` - сколько сертификатов в бандле и проверка ssl :
![](<Pasted image 20261104220939.png>)

#### Структура репозитория

```text
llm_assist/
├── final_project.ipynb       # сдаваемый ноутбук, разделы 0–7
├── scripts/
│   ├── fetch_certs.sh        # сертификаты НУЦ Минцифры + сборка CA-бандла
│   └── test_connection.py    # смоук-тест: ключ, сертификат, токен, список моделей
├── certs/                    # скачивается скриптом, в git не попадает
├── .env                      # секреты, в git не попадает
├── .env.example              # шаблон переменных окружения
├── requirements.txt          # зависимости с фиксированными версиями
└── .gitignore
```

Ноутбук как единственный сдаваемый артефакт должен запускаться целиком, поэтому весь код и все тексты обращений находятся в нём. Скрипты вспомогательные: подготовка окружения и проверка, что ключ и сертификаты работают, до первого платного запроса.

#### Файл `.env`

```text
# Ключ авторизации GigaChat API: Client ID:Client Secret в Base64
GIGACHAT_CREDENTIALS=

# Путь к CA-бандлу НУЦ Минцифры (root + sub CA одним файлом)
GIGACHAT_CA_BUNDLE_FILE=certs/trusted_bundle.pem
```

Строка авторизации собирается из пары Client ID и Client Secret:

```bash
echo -n "CLIENT_ID:CLIENT_SECRET" | base64
```

> [!warning] Ключ не попадает в репозиторий
> `.env` и `certs/` перечислены в `.gitignore`. В ноутбуке и скриптах печатается только префикс ключа, полное значение не выводится даже на скриншотах.

#### Небольшой тест доступности модели и корректности подключения

Скрипт `scripts/test_connection.py` проверяет всё, что может сломаться до первого запроса: наличие ключа, наличие CA-бандла, получение токена и список моделей, доступных на ключе.

```python
import os
from pathlib import Path

from dotenv import load_dotenv
from gigachat import GigaChat

REPO_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(REPO_ROOT / ".env")

credentials = os.getenv("GIGACHAT_CREDENTIALS")
ca_bundle = os.getenv("GIGACHAT_CA_BUNDLE_FILE")

print(f"Ключ авторизации: {credentials[:8]}… (длина {len(credentials)})")

ca_path = REPO_ROOT / ca_bundle
print(f"CA-бандл: {ca_path} - {'найден' if ca_path.is_file() else 'НЕ НАЙДЕН'}")

with GigaChat(
    credentials=credentials,
    scope="GIGACHAT_API_PERS",
    ca_bundle_file=str(ca_path),
    timeout=60.0,
) as client:
    token = client.get_token()
    print(f"Токен получен, действует до: {token.expires_at}")

    models = client.get_models()
    for m in models.data:
        print(f"  - {m.id_} (owned_by={m.owned_by})")
```

Вывод `python scripts/test_connection.py` - токен и список моделей:
![](<Pasted image 20261104221200.png>)
#### Почему сертификаты пришлось собирать вручную

- Python-клиенты (`httpx`, SDK `gigachat`) не используют системное хранилище сертификатов, поэтому CA-бандл передаётся в конструктор явно через `ca_bundle_file`.
- API GigaChat подписан цепочкой НУЦ Минцифры, которой в системе нет: корневой сертификат и промежуточный sub CA скачиваются с `gu-st.ru`.
- `gu-st.ru` отдаёт файлы с CRLF, на которых спотыкается PEM-загрузчик OpenSSL, поэтому скрипт убирает `\r`.
- SDK принимает **один** файл, а цепочка состоит из двух звеньев - root и sub CA склеиваются в `certs/trusted_bundle.pem`. Перевод строки между сертификатами обязателен, иначе `-----END CERTIFICATE----------BEGIN CERTIFICATE-----` превращается в одну строку и бандл перестаёт парситься.

### Раздел 0. Постановка задачи

В разделе 0 описана прикладная область и контракт ответа: девять полей, у каждого тип и допустимые значения. Перечисления заданы прямо в схеме, поэтому значение вне словаря не проходит валидацию, а фильтры дальше пишутся точным сравнением, без `.lower()` и поиска подстрок.

| Поле | Тип | Допустимые значения | Смысл |
|---|---|---|---|
| `category` | enum | `access`, `billing`, `bug`, `performance`, `security`, `question`, `other` | тип проблемы |
| `priority` | enum | `low`, `medium`, `high`, `critical` | в какую очередь ставить |
| `urgency_score` | integer | 1–10 | срочность внутри очереди |
| `department` | enum | `support`, `billing`, `devops`, `security`, `product` | кому отдать обращение |
| `affected_service` | enum | `api`, `web`, `mobile`, `auth`, `payments`, `email`, `other` | что затронуто |
| `is_incident` | boolean | `true` / `false` | сбой на нашей стороне |
| `requires_human` | boolean | `true` / `false` | можно ли ответить автоматически |
| `sentiment` | enum | `negative`, `neutral`, `positive` | тон автора |
| `summary` | string | свободный текст | одна фраза по сути |

Там, где данных в тексте нет, используется `other`, а не выдуманное значение. Это решение принято осознанно: `other` - значение словаря, которое видно в аналитике, а выдуманное значение ломает и валидацию, и фильтры.

### Раздел 1. Клиент GigaChat

```python
import json
import os
import time
from pathlib import Path

from dotenv import load_dotenv
from gigachat import GigaChat
from gigachat.exceptions import RateLimitError
from gigachat.models import Chat, Messages, MessagesRole

ENV_PATH = Path(".env")
load_dotenv(ENV_PATH)

CREDENTIALS = os.getenv("GIGACHAT_CREDENTIALS")
CA_BUNDLE = os.getenv("GIGACHAT_CA_BUNDLE_FILE", "certs/trusted_bundle.pem")

if not CREDENTIALS:
    raise RuntimeError(f"В {ENV_PATH.resolve()} нет GIGACHAT_CREDENTIALS - заполните .env")
if not Path(CA_BUNDLE).is_file():
    raise RuntimeError(f"Не найден CA-бандл {CA_BUNDLE} - выполните: bash scripts/fetch_certs.sh")

client = GigaChat(
    credentials=CREDENTIALS,
    scope="GIGACHAT_API_PERS",
    ca_bundle_file=CA_BUNDLE,
    timeout=60.0,
)

token = client.get_token()
MODELS_AVAILABLE = [m.id_ for m in client.get_models().data]

DEFAULT_MODEL = next(
    (m for m in ("GigaChat-2", "GigaChat-3-Lightning") if m in MODELS_AVAILABLE),
    MODELS_AVAILABLE[0],
)

print(f"Ключ загружен: {CREDENTIALS[:5]}… (длина {len(CREDENTIALS)})")
print(f"Токен получен, действует до: {token.expires_at}")
print("Модели на ключе:", ", ".join(MODELS_AVAILABLE))
print("Модель по умолчанию:", DEFAULT_MODEL)
```

- Проверки вынесены в начало: если нет ключа или сертификата, ноутбук падает с понятным сообщением, а не с ошибкой TLS на первом запросе.
- Модель по умолчанию выбирается из фактического списка `get_models()`, а не жёстко: имена моделей у Сбера меняются, и захардкоженное имя однажды перестанет существовать.
- `scope="GIGACHAT_API_PERS"` - тариф для физлиц. Для юридических лиц используется другой scope, и это первое, что нужно поменять при переносе.

Вывод раздела 1 - префикс ключа, срок действия токена, список моделей:

![](<Pasted image 20261105224017.png>)
### Раздел 2.1–2.2. Проблема: неструктурированный вывод

Сначала обычный запрос без формального контракта: просим JSON словами.

```python
sample_input = """
С утра не могу войти в личный кабинет: после ввода пароля страница просто
перезагружается. Браузер Chrome, в режиме инкогнито та же картина.
Доступ нужен срочно - завтра сдавать отчёт. Пароль менял вчера, до этого всё работало.
"""

response = client.chat(
    Chat(
        model=DEFAULT_MODEL,
        messages=[
            Messages(
                role=MessagesRole.USER,
                content=f"Разбери обращение клиента и верни результат в JSON:\n{sample_input}",
            )
        ],
    )
)

raw_output = response.choices[0].message.content
print(raw_output)

try:
    data = json.loads(raw_output)
    print("json.loads прошёл, но контракта нет: состав полей ничем не задан.")
    print("Ключи, которые выбрала модель:", list(data))
except Exception as e:
    print(f"Ошибка json.loads: {e}")
```

Фактический вывод модели:

~~~text
--- сырой ответ модели ---
```json
{
  "проблема": "Не могу войти в личный кабинет",
  "описание": "После ввода пароля страница перезагружается.",
  "браузер": "Chrome",
  "режим_использования_браузера": "обычный режим + режим инкогнито",
  "состояние_до_проблемы": "всё работало нормально",
  "действие_предпринятое_клиентом": "менял пароль вчера",
  "необходимость_скорого_решения": true,
  "контекст": "завтра сдавать отчёт"
}
```

Ошибка json.loads: Expecting value: line 1 column 1 (char 0)
~~~

- Модель вернула не данные, а текст: обернула JSON в блок кода с меткой `json`, поэтому `json.loads` падает на первом символе.
- Даже без обрамления состав полей не наш: `проблема`, `описание`, `браузер`, `режим_использования_браузера`, `необходимость_скорого_решения` - модель придумала свои ключи, потому что контракта не было.
- Вывод нестабилен от запуска к запуску: набор ключей и их названия меняются, а значит в коде нельзя написать `ticket["category"]` - такого поля может не быть.

Вывод раздела 2.2 - сырой ответ и ошибка `json.loads`:

![](<Pasted image 20261105224112.png>)
### Раздел 2.3. Решение: JSON-схема и `strict: True`

У GigaChat нет режима `json_object`, который предлагает шаблон под Groq. Вместо флага «верни JSON» передаётся полная JSON-схема: типы полей, перечисления, обязательность и запрет дополнительных свойств. Промпт остаётся, он объясняет смысл полей, но форму ответа диктует схема.

```python
CATEGORIES = ["access", "billing", "bug", "performance", "security", "question", "other"]
PRIORITIES = ["low", "medium", "high", "critical"]
DEPARTMENTS = ["support", "billing", "devops", "security", "product"]
SERVICES = ["api", "web", "mobile", "auth", "payments", "email", "other"]
SENTIMENTS = ["negative", "neutral", "positive"]

TICKET_SCHEMA = {
    "type": "object",
    "properties": {
        "category": {"type": "string", "enum": CATEGORIES},
        "priority": {"type": "string", "enum": PRIORITIES},
        "urgency_score": {"type": "integer", "minimum": 1, "maximum": 10},
        "department": {"type": "string", "enum": DEPARTMENTS},
        "affected_service": {"type": "string", "enum": SERVICES},
        "is_incident": {"type": "boolean"},
        "requires_human": {"type": "boolean"},
        "sentiment": {"type": "string", "enum": SENTIMENTS},
        "summary": {"type": "string"},
    },
    "required": [
        "category", "priority", "urgency_score", "department", "affected_service",
        "is_incident", "requires_human", "sentiment", "summary",
    ],
    "additionalProperties": False,
}

SYSTEM_PROMPT = """
Ты - ассистент первой линии технической поддержки. На вход приходит свободный текст
обращения клиента. Разметь обращение и верни строго JSON по схеме.

category - тип проблемы:
  access - вход, пароли, права доступа;
  billing - деньги, счета, подписки, возвраты;
  bug - ошибка или сбой в работе продукта;
  performance - работает, но медленно;
  security - фишинг, утечки, подозрительная активность;
  question - вопрос «как сделать», инструкция, а не поломка;
  other - ничего из перечисленного.

priority - в какую очередь ставить:
  critical - не работает у многих, потеря денег или данных;
  high - блокирует работу клиента;
  medium - мешает, но есть обход;
  low - косметика или пожелание.

urgency_score - целое от 1 до 10, срочность внутри очереди: 1-3 можно подождать,
  4-6 решить в течение дня, 7-8 нужно сегодня, 9-10 немедленно.

department - кому отдать обращение: support, billing, devops, security, product.
affected_service - что затронуто: api, web, mobile, auth, payments, email, other.

is_incident - true только если это сбой или деградация сервиса на нашей стороне.
  Жалоба на списание и вопрос «как выгрузить отчёт» инцидентом не являются.

requires_human - true, если нужен человек: деньги, доступы, безопасность, инциденты.
sentiment - тон автора: negative, neutral, positive.
summary - одна короткая фраза по сути обращения, без домыслов и советов.

Если данных в тексте нет, выбирай other в соответствующем поле. Не придумывай факты.
"""

response = client.chat(
    Chat(
        model=DEFAULT_MODEL,
        messages=[
            Messages(role=MessagesRole.SYSTEM, content=SYSTEM_PROMPT),
            Messages(role=MessagesRole.USER, content=f"Обращение клиента:\n{sample_input}"),
        ],
        response_format={
            "type": "json_schema",
            "schema": TICKET_SCHEMA,
            "strict": True,
        },
        temperature=0.0,
    )
)

ticket = json.loads(response.choices[0].message.content)
print(json.dumps(ticket, ensure_ascii=False, indent=2))
print(f"полей в ответе: {len(ticket)} из {len(TICKET_SCHEMA['required'])}")
```

- `strict: True` вместе с полным `required` гарантирует, что в ответе будут все девять полей, а полей вне схемы не появится. Модель больше не может придумать `браузер` или `необходимость_скорого_решения`.
- `enum` в схеме - это не подсказка, а ограничение: значение вне словаря не проходит валидацию на стороне API. Именно поэтому в разделе 5 фильтры пишутся точным сравнением.
- `additionalProperties: False` закрывает схему: лишнее поле - ошибка, а не «бонус» от модели.
- `temperature=0.0` снижает разброс, но не гарантирует полный детерминизм - на повторных прогонах значения могут отличаться на один класс.
- Промпт и схема определены один раз, в этой ячейке; дальше `process_item()` переиспользует их, чтобы в ноутбуке не появилось две разные версии контракта.

Вывод раздела 2.3 - валидный JSON по схеме и строка «полей в ответе: 9 из 9»:
![](<Pasted image 20261105224139.png>)

### Раздел 3. Функция обработки одного обращения

```python
def process_item(text: str, model: str | None = None, attempts: int = 3) -> dict | None:
    """
    Обрабатывает один входной текст с помощью LLM.

    Args:
        text: входной текст для обработки
        model: имя модели; None - модель по умолчанию с ключа
        attempts: сколько раз повторить запрос при лимите запросов

    Returns:
        Словарь с извлечёнными данными или None при ошибке
    """
    chat = Chat(
        model=model or DEFAULT_MODEL,
        messages=[
            Messages(role=MessagesRole.SYSTEM, content=SYSTEM_PROMPT),
            Messages(role=MessagesRole.USER, content=f"Обращение клиента:\n{text}"),
        ],
        response_format={"type": "json_schema", "schema": TICKET_SCHEMA, "strict": True},
        temperature=0.0,
    )

    for attempt in range(1, attempts + 1):
        try:
            response = client.chat(chat)
            return json.loads(response.choices[0].message.content)
        except RateLimitError as e:
            # Лимит частоты на тарифе: ждём столько, сколько просит сервер
            wait = getattr(e, "retry_after", None) or 5
            print(f"Лимит запросов. Ждём {wait} сек... (попытка {attempt}/{attempts})")
            time.sleep(wait)
        except Exception as e:
            print(f"Ошибка: {e}")
            return None

    print(f"Не удалось обработать после {attempts} попыток")
    return None
```

- Двухслойная защита от лимитов: SDK сам повторяет часть ошибок, а цикл в функции обрабатывает `RateLimitError`, который всё-таки пробился. Пауза берётся из `retry_after`, а не выдумывается.
- `except Exception` возвращает `None`, а не роняет батч: одно сбойное обращение не должно стоить результатов по остальным семи.
- Функция возвращает только словарь, без `usage` и времени - это осознанно: для пайплайна нужны данные, а метрики собираются отдельно в разделе 6, где вызов идёт напрямую.

![](<Pasted image 20261104221906.png>)

### Раздел 4. Пайплайн по 7 обращениям

```python
input_items = [
    """
    С утра не могу войти в личный кабинет: после ввода пароля страница просто
    перезагружается. Браузер Chrome, в режиме инкогнито та же картина.
    Доступ нужен срочно - завтра сдавать отчёт. Пароль менял вчера, до этого всё работало.
    """,
    """
    После обновления приложения до версии 2.4.1 раздел «Платежи» открывается
    и сразу закрывается. Так у всей команды на iOS 18. До обновления работало нормально.
    """,
    # ... всего семь обращений: разные категории, отделы и степень подробности
]

results = []
failed = []

for number, text in enumerate(input_items, 1):
    print(f"Обрабатываю {number}/{len(input_items)}...")
    parsed = process_item(text)
    if parsed is None:
        failed.append(number)
        continue
    results.append({"id": f"T-{number:02d}", **parsed})
    # пауза между запросами: у бесплатного тарифа ограничена частота
    time.sleep(1.5)

print(f"Размечено: {len(results)} из {len(input_items)}. Сбои: {failed or 'нет'}")
```

Набор из семи обращений подобран так, чтобы проверить разные ветки схемы: вход в личный кабинет (`access`), сбой после обновления (`bug`), возврат денег (`billing`), вопрос по выгрузке отчёта (`question`), инцидент с API (`bug` + `is_incident`), фишинг (`security`), медленный дашборд (`performance`).

- Пауза `time.sleep(1.5)` между запросами - не украшение: на бесплатном тарифе ограничена частота, и семь запросов подряд могут привести к `429`.
- Идентификаторы `T-01…T-07` присваиваются после разметки, поэтому в аналитике можно ссылаться на конкретное обращение, не пересчитывая индексы.
- Список `failed` сохраняет номера сбойных записей: если API откажет, в выводе видно, какие обращения потерялись, а не только «размечено 6 из 7».

Вывод раздела 4.2 - таблица разметки и строка «Размечено: 7 из 7. Сбои: нет»:
![](<Pasted image 20261105224244.png>)

### Раздел 5. Фильтрация и анализ без модели

Три задания используют только размеченные данные: обращений к API здесь нет.

#### Задание 1. Фильтрация по числовому полю

```python
URGENCY_THRESHOLD = 7

urgent = [r for r in results if r.get("urgency_score", 0) >= URGENCY_THRESHOLD]

print(f"Обращений со срочностью >= {URGENCY_THRESHOLD}: {len(urgent)} из {len(results)}")
for r in sorted(urgent, key=lambda x: x["urgency_score"], reverse=True):
    print(f"  {r['id']} | {r['urgency_score']}/10 | {r['priority']:<8} | {r['department']:<8} | {r['summary']}")
```

Порог 7 выбран по смыслу шкалы из промпта: 7–8 - «нужно сегодня», 9–10 - «немедленно». Результат: 5 обращений из 7 - T-05 (10), T-01 (8), T-02 (8), T-03 (8), T-06 (8).
![](<Pasted image 20261104222049.png>)
#### Задание 2. Поиск экстремального значения

```python
most_urgent = max(results, key=lambda r: r["urgency_score"])
least_urgent = min(results, key=lambda r: r["urgency_score"])

print(f"Самое срочное: {most_urgent['id']} - {most_urgent['urgency_score']}/10")
print(f"Самое несрочное: {least_urgent['id']} - {least_urgent['urgency_score']}/10")
```

Результат: максимум - T-05 (инцидент с API, 10/10), минимум - T-04 (вопрос про выгрузку отчёта, 3/10). Это ожидаемая пара: авария сервиса против справочного вопроса.
![](<Pasted image 20261105224415.png>)
#### Задание 3. Агрегация по категориям

```python
from collections import defaultdict

by_category = defaultdict(list)
for r in results:
    by_category[r["category"]].append(r["urgency_score"])

scores = [r["urgency_score"] for r in results]

print(f"Всего обращений: {len(scores)}")
print(f"Средняя срочность: {sum(scores) / len(scores):.2f}")
for category, values in sorted(by_category.items(), key=lambda kv: -len(kv[1])):
    print(f"{category:<14} {len(values):>9} {sum(values) / len(values):>12.2f} {max(values):>9}")
```

Результат: средняя срочность 7.14; `bug` - 2 обращения со средней 9.00 и максимумом 10; `access` - 8.00; `billing` - 8.00; `security` - 8.00; `performance` - 5.00; `question` - 3.00. Агрегация показывает перекос выборки: половина обращений - про сбои и доступы, поэтому средняя срочность высокая.

![](<Pasted image 20261105224519.png>)

### Раздел 6. Сравнение моделей

Сравниваются три модели на трёх обращениях - девять запросов, это укладывается в лимиты бесплатного тарифа. Метрики: время ответа, `usage.total_tokens`, токены в секунду, прошёл ли ответ схему. Качество оценивается не по числу токенов, а построчным сравнением полей.

| Модель                 | Поколение | Класс     | Ожидаемая роль              |
| ---------------------- | --------- | --------- | --------------------------- |
| `GigaChat-3-Lightning` | 3         | Lightning | минимальная задержка ответа |
| `GigaChat-2`           | 2         | базовая   | повседневные задачи         |
| `GigaChat-2-Pro`       | 2         | Pro       | ресурсоёмкие задачи         |

```python
MODELS_TO_COMPARE = ["GigaChat-2", "GigaChat-2-Pro", "GigaChat-3-Lightning"]
COMPARE_TEXTS = {"T-01": input_items[0], "T-03": input_items[2], "T-05": input_items[4]}

comparison_results = []

for model in MODELS_TO_COMPARE:
    for ticket_id, text in COMPARE_TEXTS.items():
        chat = Chat(
            model=model,
            messages=[
                Messages(role=MessagesRole.SYSTEM, content=SYSTEM_PROMPT),
                Messages(role=MessagesRole.USER, content=f"Обращение клиента:\n{text}"),
            ],
            response_format={"type": "json_schema", "schema": TICKET_SCHEMA, "strict": True},
            temperature=0.0,
        )
        started = time.perf_counter()
        try:
            response = client.chat(chat)
            elapsed = time.perf_counter() - started
            usage = response.usage
            parsed = json.loads(response.choices[0].message.content)
        except Exception as e:
            elapsed = time.perf_counter() - started
            comparison_results.append({
                "model": model, "id": ticket_id, "seconds": round(elapsed, 2),
                "total_tokens": 0, "tok_per_sec": 0.0, "ok": False, "parsed": {},
            })
            continue

        comparison_results.append({
            "model": model,
            "id": ticket_id,
            "seconds": round(elapsed, 2),
            "total_tokens": usage.total_tokens,
            "tok_per_sec": round(usage.completion_tokens / max(elapsed, 1e-3), 1),
            "ok": True,
            "parsed": parsed,
        })
        time.sleep(1.5)
```

Результаты прогона:

| Модель | Среднее время | Средние токены | Ток/с | Валидных ответов |
|---|---|---|---|---|
| `GigaChat-3-Lightning` | 0.75 с | 326 | 146 | 3 из 3 |
| `GigaChat-2` | 0.81 с | 175 | 117 | 3 из 3 |
| `GigaChat-2-Pro` | 4.78 с | 310 | 24 | 3 из 3 |

- `strict: True` работает на всех трёх моделях: 9 ответов из 9 прошли схему, все девять полей на месте, лишних полей нет.
- `GigaChat-3-Lightning` быстрее всех (0.75 с, 146 ток/с), но расходится с базовой моделью в пяти полях: на денежном T-03 ставит `support` вместо `billing` и `is_incident: true`, а на T-01, T-03 и T-05 меняет `urgency_score` на ±1 балл.
- `GigaChat-2-Pro` в 5.9 раза медленнее базовой `GigaChat-2` (4.78 с против 0.81 с) и не даёт выигрыша в качестве: все поля совпали, кроме `is_incident` на пограничном T-01. На этой задаче «тяжёлая» модель не нужна.
- Расхождения между моделями содержательные, но немногочисленные: T-01 - `is_incident` true/false/true и `urgency_score` 8/8/9; T-03 - `department` billing/billing/support, `is_incident` false/false/true и `urgency_score` 8/8/9; T-05 - `urgency_score` 10/10/9.
- Про токены. `usage.total_tokens` по девяти запросам различается более чем втрое: от 164 до 564. Средние - 175 (`GigaChat-2`), 310 (`GigaChat-2-Pro`), 326 (`GigaChat-3-Lightning`), но у Pro и Lightning первый запрос к модели (T-01) стоит 561 и 564 токена, а следующие - 175-216; у базовой модели, которая уже работала в разделе 4, тот же T-01 стоит 181. Системный промпт и схема во всех девяти запросах одинаковые, поэтому разница в ~380 токенов это не размер промпта и не длина ответа, а разовый overhead при первом обращении к модели (холодный старт). Отсюда два вывода: `total_tokens` нельзя использовать как меру «разговорчивости» модели, а средние по трём запросам с одним холодным стартом смещены. Для оценки стоимости нужны `prompt_tokens` и `completion_tokens` по отдельности и замер после прогрева модели.

Вывод раздела 6 - таблица по моделям, средние и расхождения в разметке:
![](<Pasted image 20261105224714.png>)

![](<Pasted image 20261105224758.png>)
### Раздел 7. Итоги

В разделе 7 ноутбука зафиксировано, что реализовано, что показал прогон и что можно улучшить. Кратко:

- клиент GigaChat с авторизацией по строке `Client ID:Client Secret` в Base64 и CA-бандлом НУЦ Минцифры; ключ только в `.env`;
- продемонстрирована проблема неструктурированного вывода и решена полной JSON-схемой со `strict: True`;
- функция `process_item()` с повтором на `RateLimitError` и `None` на прочих ошибках;
- пайплайн на 7 обращений: размечены все 7, сбоев нет;
- три задания аналитики без модели: фильтр по `urgency_score >= 7` (5 из 7), экстремумы (T-05 = 10, T-04 = 3), агрегация по категориям (средняя 7.14; `bug` - 2 обращения со средней 9.00);
- сравнение трёх моделей: 9 запросов, все 9 ответов валидны; Lightning 0.75 с и 146 ток/с, базовая 0.81 с и 117 ток/с, Pro 4.78 с и 24 ток/с; качество разметки - в разделе 6.

Что можно улучшить:

- добавить в схему поле `confidence` и отправлять на ручную проверку обращения с низкой уверенностью или с `category: other`;
- закрепить спорные правила прямо в промпте (например: «возврат средств - всегда `billing`») и проверить их на размеченной выборке;
- кэшировать ответы по хэшу текста, чтобы повторные прогоны не тратили квоту;
- вынести промпт и схему в отдельный файл: смена предметной области должна требовать правки одного файла, а не всего ноутбука;

### С какими трудностями столкнулись

- Задание написано под Groq, но в России он недоступен - пришлось перейти на GigaChat и разобраться с его авторизацией, scope и линейкой моделей.
- В GigaChat нет режима `json_object`. Вместо одного флага нужна полная JSON-схема со `strict: True`, а это заметно больше кода в промпте и в разделе 2.
- TLS-соединение не устанавливалось без CA-бандла НУЦ Минцифры; пришлось разбираться с CRLF в файлах `gu-st.ru` и склейкой root + sub CA в один PEM.
- Бесплатный тариф ограничивает частоту запросов: в пайплайне появились паузы, а в функции - повтор на `429` с паузой из `retry_after`.
- `temperature=0` не гарантирует полного детерминизма: при повторных прогонах `urgency_score` для T-01 приходил то 9, то 8, а время ответа у `GigaChat-2-Pro` менялось в разы. Выводы в разделе 7 сформулированы с учётом этого.
- Имена моделей у Сбера меняются, поэтому модель по умолчанию выбирается из `get_models()`, а не задаётся строкой.


