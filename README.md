# mdm-doc-validator-abap (ZMDMDOC)

ABAP-клон локального валидатора банковских документов и W-9
([mdm-doc-validator](https://github.com/) — Python-оригинал живёт в `~/Projects/mdm-doc-validator`).
Без веб-панели: классический Z-репорт — пользователь указывает путь к файлу документа,
программа читает его, извлекает реквизиты и выносит вердикт по декларативным правилам.

```
SA38 → ZMDMDOC → путь к файлу → F8
────────────────────────────────────
[BANK DOC VERDICT]
Document   : vendor_bank_letter.pdf
Doc type   : bank_letter
Verdict    : WARNING
Why        : Bank letter appears unsigned/unstamped (no officer block either).
Next step  : usable with caution — note the warnings for the Data Owner
...
IBAN       : IT**…8412 (country IT, len 27)
```

## Что внутри

| Компонент | Назначение |
|---|---|
| `ZMDMDOC` (report) | «CLI»: selection screen, оркестрация пайплайна, вывод, JSON-выгрузка |
| `ZCL_MDMDOC_FILE` | чтение файла (ПК / сервер приложений), SHA-256 run id, unwrap `.zip`/`.eml` |
| `ZCL_MDMDOC_PDF` | извлечение текстового слоя PDF на чистом ABAP (FlateDecode + BT/ET + ToUnicode) |
| `ZCL_MDMDOC_SNIFF` | автоопределение класса документа (bank / w9) и типа (invoice, bank_letter, w8…) |
| `ZCL_MDMDOC_REGEX` | детерминированное извлечение ID: IBAN, SWIFT, routing/ABA, account, EIN/SSN, boxed TIN |
| `ZCL_MDMDOC_LLM` | опциональный Ollama-клиент (`/api/chat`): извлечение полей текст-моделью, vision для сканов |
| `ZCL_MDMDOC_EXTRACT` | merge: regex-кандидаты ПЕРЕКРЫВАЮТ ответ модели (crosscheck), нормализация |
| `ZCL_MDMDOC_RULES` | rule engine: YAML-правила оригинала, скомпилированные в ABAP + JSON-override |
| `ZCL_MDMDOC_VERDICT` | свёртка вердикта: REJECT > NEED_MANUAL_REVIEW > WARNING > ACCEPT |
| `ZCL_MDMDOC_MASK` | маскирование PII (TIN — всегда), leak gate на выходной JSON |
| `ZCL_MDMDOC_REPORT` | текстовый отчёт + JSON `mdmdoc.v1`-совместимого формата |
| `ZCL_MDMDOC_RULES_DATA` | **генерируется** из `rules/*.yaml` — не редактировать руками |

## Требования

- SAP NetWeaver / S/4HANA, **ABAP ≥ 7.50** (classic regex, без PCRE — работает и на ECC EhP8).
- [abapGit](https://abapgit.org) для импорта.
- `/UI2/CL_JSON` (компонент SAP_UI — стандарт с 7.40 SP08). Без него не работают: LLM-вызовы,
  JSON-выгрузка, override правил; ядро (regex + правила + вердикт) работает и без него.
- Опционально: [Ollama](https://ollama.com) для LLM-извлечения полей и чтения сканов.

## Установка

1. abapGit → New Online (или ZIP-импорт этого репозитория) → пакет `ZMDMDOC` → Pull.
2. Активировать все объекты.
3. Прогнать юнит-тесты пакета: `Ctrl+Shift+F10` в ADT (все `HARMLESS/SHORT`, без сети).
4. Запуск: SA38 → `ZMDMDOC`.

### Опционально: локальный Ollama (LLM-извлечение + сканы)

```bash
brew install ollama          # или curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen3:4b         # текстовая модель (извлечение полей)
ollama pull qwen2.5vl:7b     # vision (транскрипция картинок-сканов)
```

**Важно:** URL из параметра «Ollama URL» должен быть доступен **с сервера приложений SAP,
а не с вашего ПК с SAPGUI**. `http://localhost:11434` работает только когда Ollama крутится
на самом сервере приложений (например, локальный ABAP Developer Trial в Docker на той же машине).
Для Ollama на другом хосте: `OLLAMA_HOST=0.0.0.0 ollama serve` и URL `http://<хост>:11434`.
HTTPS-эндпоинты требуют CA-сертификат в STRUST (SSL client PSE); обычный HTTP не требует ничего
(исходящий вызов, SM59/SICF не нужны).

## Использование

Selection screen:

- **Input**: путь к файлу; радио «ПК» (`gui_upload`) / «сервер приложений» (`OPEN DATASET`).
- **Classification**: авто / принудительно bank / принудительно w9; язык вывода EN/RU.
- **LLM (опционально)**: флажок + URL/модели/таймаут. Выключено → детерминированный режим
  (regex-извлечение, нарративные поля пустые, NOTE `LLM-002`).
- **Output**: JSON-файл (mdmdoc.v1-совместимый), путь к JSON-файлу правил (override),
  строгий режим для фоновых джобов.

Поддерживаемые входы: `.pdf` (текстовый слой), картинки `.png/.jpg/...` (только с LLM-vision),
`.zip` / `.eml` (берётся лучший вложенный документ). Редактируемые форматы
(`.docx/.xlsx/.txt/...`) отклоняются вердиктом по правилу BNK-003 — как в оригинале.

### Аналог exit-кодов Python-оригинала

| Python `mdmdoc` | ZMDMDOC |
|---|---|
| 0 ACCEPT | MESSAGE тип S |
| 1 REJECT | MESSAGE S `DISPLAY LIKE 'E'`; в фоне со «строгим» флажком — настоящий тип E (джоб → Canceled) |
| 2 REVIEW/WARNING | MESSAGE S `DISPLAY LIKE 'W'` |
| 3 LLM недоступен | finding `LLM-001` (NEED_MANUAL_REVIEW) |
| 4 нечитаемый документ | finding `EXT-001`/`EXT-002` (NEED_MANUAL_REVIEW) |

Для вызова из другого кода: `SUBMIT zmdmdoc ... AND RETURN`, затем
`IMPORT verdict json FROM MEMORY ID 'ZMDMDOC_RESULT'`.

## Правила

Источник истины — `rules/banking.yaml` и `rules/w9.yaml` (копии правил Python-оригинала).
Изменение правил:

```bash
# правите YAML, затем:
python3 tools/gen_rules_abap.py     # перегенерирует src/zcl_mdmdoc_rules_data.clas.abap + rules/rules.json
# → abapGit Pull в систему
```

Быстрая правка без транспорта: отредактируйте `rules/rules.json` и укажите путь к нему
в параметре «rules override» — правила загрузятся в рантайме через `/UI2/CL_JSON`
(битый JSON → предупреждение + откат на вшитые правила).

## Маскирование (by design, не настраивается)

- TIN (SSN/EIN) **никогда** не выводится полностью — ни в списке, ни в JSON, ни в заметках.
- IBAN/account/routing маскируются (`DE**…4931`, `…6971`); leak gate сканирует финальный JSON
  перед записью и отменяет выгрузку при утечке.

## Ограничения

- **Сканированные PDF без текстового слоя** не читаются (в ABAP нет растеризатора страниц) —
  finding `EXT-001`. Обход: конвертировать страницу в PNG и включить LLM-vision, либо OCR снаружи.
- Картинки-сканы читаются **только** при включённом LLM (vision-модель).
- PDF с CID-шрифтами без ToUnicode-карты: текст этих шрифтов пропускается (warning).
- Запароленные PDF → `EXT-003`.
- `.msg` (Outlook) не поддерживается — пересохраните как `.eml` или извлеките вложение (`EXT-005`).
- Порядок текста ≈ порядок объектов в файле PDF (достаточно для keyword-scoring и label-window
  regex; не для чтения человеком).
- Первое, что стоит проверить на целевой системе: `CL_ABAP_GZIP=>DECOMPRESS_BINARY` с
  zlib-потоками (RFC 1950) — от этого зависит чтение сжатых PDF (три fallback-стратегии внутри
  `ZCL_MDMDOC_PDF`); затем `/UI2/CL_JSON`; затем поведение `CL_ABAP_ZIP` при несовпадении CRC.
  Всё остальное — стандарт с 7.40.

## Сверка с Change Request (MDG)

Дополнительно есть сверка документа с данными **MDG Change Request**: при проверке заявки
(BAdI `USMD_RULE_SERVICE` → `ZCL_MDG_BP_FIELD_DERR_VAL`) система читает вложение CR, извлекает
реквизиты, читает поля самой заявки (`io_model->read_entity_data_all`) и выдаёт **warning** при
расхождениях (IBAN/SWIFT/account/имя/страна…). Логика сравнения (`ZCL_MDMDOC_COMPARE`,
правила `SAP-000..008`) — источник-независима и покрыта юнит-тестами; MDG-специфика изолирована
в `ZCL_MDMDOC_MDG_READER` + BAdI-классе (помечены verify-on-system, вне abaplint).
Внедрение — **глава 10 в [docs/INTEGRATION.md](docs/INTEGRATION.md)**.

**Адаптивность и пред-запусковые тесты.** Маппинг полей MDG не захардкожен: `ZMDMDOC_MDG_DISCOVER`
читает реальную модель и предлагает соответствие `SAP_KEY→сущность.поле` (таблица `ZMDMDOC_MAP`,
иначе дефолты). `ZMDMDOC_DOCTOR` — набор маленьких проверок «загрузится / прочитает данные»
(ядро — тестируемый `ZCL_MDMDOC_SELFTEST`) перед включением BAdI. Разделы 11–12 в INTEGRATION.md.

## Что НЕ переносилось из оригинала

Веб-панель/REST API, teach loop (review → labels → few-shot → LoRA → adoption gate),
eval-фреймворк, web enrichment. Это осознанный скоуп: ABAP-клон = валидационный пайплайн.

## Разработка

```bash
npx --yes @abaplint/cli      # синтаксическая проверка (конфиг abaplint.json, target v750)
python3 tools/gen_rules_abap.py   # регенерация правил (детерминированная)
```

Контракт публичных API классов: `docs/CONTRACT.md`.
