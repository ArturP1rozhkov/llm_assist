# llm_assist

Итоговая работа курса: **LLM-ассистент для анализа и обработки пользовательских запросов**.

Пользовательские запросы (неструктурированный текст) проходят через GigaChat API
(вместо недоступного в РФ Groq) и превращаются в строгий JSON по заранее
описанной схеме: пайплайн на батче записей, фильтрация и аналитика результата,
сравнение нескольких моделей по скорости и качеству.

## Структура репозитория

```
llm_assist/
├── final_project.ipynb       # сдаваемый ноутбук (разделы 0–7), в корне рядом с .env
├── scripts/
│   ├── fetch_certs.sh        # сертификаты НУЦ Минцифры + сборка CA-бандла
│   └── test_connection.py    # smoke-тест: ключ, сертификат, токен, список моделей
├── certs/                    # скачивается скриптом, в git не попадает
├── .env                      # секреты, в git не попадает
├── .env.example              # шаблон переменных окружения
├── requirements.txt          # зависимости (пины по факту установки)
└── .gitignore
```

Почему так: ноутбук — единственный сдаваемый артефакт и он должен запускаться
целиком, поэтому тексты обращений и весь код живут в нём. Скрипты — вспомогательные:
подготовка окружения (сертификаты, ключ).

## Быстрый старт

```bash
cd /srv/repos/llm_assist

# 1. окружение
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 2. сертификаты НУЦ Минцифры (API GigaChat подписан ими, в системе их нет)
bash scripts/fetch_certs.sh

# 3. ключ
cp .env.example .env      # и вписать GIGACHAT_CREDENTIALS

# 4. проверка связки ключ + сертификат + сеть
python scripts/test_connection.py
```

## Запуск ноутбука

В VS Code: открыть папку репозитория, открыть `final_project.ipynb`, справа сверху
**Select Kernel** → `Python (llm_assist)` (ядро зарегистрировано из `.venv`).
Дальше ячейки запускаются по одной (Shift+Enter) — удобно для пошагового разбора.

Полный прогон «Restart & Run All» из консоли:

```bash
source .venv/bin/activate
jupyter nbconvert --to notebook --execute --inplace \
  --ExecutePreprocessor.timeout=300 --ExecutePreprocessor.kernel_name=llm_assist \
  final_project.ipynb
```

Прогон тратит квоту: 1 запрос в разделе 2.2, 1 в 2.3, 1 в разделе 3, 7 в пайплайне
и 9 в сравнении моделей — всего 19 обращений к API.
