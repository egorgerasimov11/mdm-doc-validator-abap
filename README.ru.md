# mdm-doc-validator-abap (ZMDMDOC)

> English version: [README.md](README.md)

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

Ядро валидатора (работает на любой системе ≥ 7.50):

| Компонент | Назначение |
|---|---|
| `ZMDMDOC` (report) | «CLI»: selection screen, оркестрация пайплайна, вывод, JSON-выгрузка |
| `ZMDMDOC_RULES` (report) | просмотр/экспорт активного набора правил прямо в SAP |
| `ZCL_MDMDOC_FILE` | чтение файла (ПК / сервер приложений), SHA-256 run id, unwrap `.zip`/`.eml` |
| `ZCL_MDMDOC_PDF` | извлечение текстового слоя PDF на чистом ABAP (FlateDecode + BT/ET + ToUnicode) |
| `ZCL_MDMDOC_SNIFF` | автоопределение класса документа (bank / w9) и типа (invoice, bank_letter, w8…) |
| `ZCL_MDMDOC_REGEX` | детерминированное извлечение ID: IBAN, SWIFT, routing/ABA, account, EIN/SSN, boxed TIN |
| `ZCL_MDMDOC_LLM` | опциональный Ollama-клиент (`/api/chat`): извлечение полей текст-моделью, vision для сканов |
| `ZCL_MDMDOC_EXTRACT` | merge: regex-кандидаты сверяются с ответом модели (crosscheck) + guards, нормализация |
| `ZCL_MDMDOC_NORM` | нормализаторы: ISO2-страны, mod-97, даты, классификации, имена |
| `ZCL_MDMDOC_RULES` | rule engine: YAML-правила оригинала, скомпилированные в ABAP + JSON-override |
| `ZCL_MDMDOC_VERDICT` | свёртка вердикта: REJECT > NEED_MANUAL_REVIEW > WARNING > ACCEPT |
| `ZCL_MDMDOC_MASK` | маскирование PII (TIN — всегда), leak gate на выходной JSON |
| `ZCL_MDMDOC_REPORT` | текстовый отчёт + JSON `mdmdoc.v1`-совместимого формата |
| `ZCL_MDMDOC_COMPARE` | посимвольная сверка документ ↔ данные SAP/CR (правила SAP-000..009) |
| `ZCL_MDMDOC_SAP_MANUAL` | ручной/test-double SAP-reader (`ZIF_MDMDOC_SAP_READER`): поля из таблицы или плоского JSON — компаратор работает без живого MDG |
| `ZCL_MDMDOC_RULES_DATA` | **генерируется** из `rules/*.yaml` — не редактировать руками |
| `ZCL_MDMDOC_GOLDEN_DATA` | **генерируется**: golden-корпус паритета Python↔ABAP (тест-данные) |

MDG-сценарий (только для систем с MDG; на прочих эти объекты не активируются — см. «Установка»):

| Компонент | Назначение |
|---|---|
| `ZCL_MDG_BP_FIELD_DERR_VAL` | реализация BAdI `USMD_RULE_SERVICE` — проверка вложений Change Request |
| `ZCL_MDMDOC_MDG_READER` + `ZIF_MDMDOC_SAP_READER` | чтение полей CR и GOS-вложений (verify-on-system) |
| `ZCL_MDMDOC_MDG_MAP` | маппинг SAP_KEY → сущность/поле модели (дефолты + таблица `ZMDMDOC_MAP`) |
| `ZCL_MDMDOC_ONBOARD` / `ZCL_MDMDOC_SELFTEST` | пред-запусковые GO/NO-GO проверки |
| `ZMDMDOC_SETUP` / `ZMDMDOC_DOCTOR` / `ZMDMDOC_MDG_DISCOVER` (reports) | onboarding, самопроверка, discovery модели MDG |

Итого в пакете `ZMDMDOC`: **5 программ, 2 интерфейса, 20 классов** (13 ядро + 2
генерируемых + 5 MDG-сценарий) + message class `ZMDMDOC`.

## Требования

- SAP NetWeaver / S/4HANA, **ABAP ≥ 7.50** (classic regex, без PCRE — работает и на ECC EhP8).
- [abapGit](https://abapgit.org) для импорта.
- `/UI2/CL_JSON` (компонент SAP_UI — стандарт с 7.40 SP08). Без него не работают: LLM-вызовы,
  JSON-выгрузка, override правил; ядро (regex + правила + вердикт) работает и без него.
- Опционально: [Ollama](https://ollama.com) для LLM-извлечения полей и чтения сканов.

## Установка

1. abapGit → New Online (или ZIP-импорт этого репозитория) → пакет `ZMDMDOC` → Pull.
2. Активировать объекты. **На системе без MDG** 7 объектов MDG-сценария (см. таблицу выше)
   ссылаются на USMD-типы и **не активируются** — оставьте их неактивными или удалите;
   ядро валидатора полностью работает без них. На системе с MDG активируется всё.
3. Прогнать юнит-тесты пакета: `Ctrl+Shift+F10` в ADT — ожидается **209 зелёных**
   (все `HARMLESS/SHORT`, без сети/файлов; число растёт с обновлениями — пересчитайте у себя).
4. Запуск: SA38 → `ZMDMDOC`. Первый прогон — см. `samples/README.md` (демо-документ).

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

**W-8 формы:** W-8BEN/-E распознаётся (doc_type `w8`) и по правилу `W9-030` всегда уходит в
`NEED_MANUAL_REVIEW` — W-8 compliance-политика сознательно не автоматизирована в v1.

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

**Governance-профиль (tier).** Каждое правило несёт метку `tier: corp|experimental|learned`.
`python3 tools/gen_rules_abap.py --tier-min corp` генерирует строгий corp-профиль
(без experimental `BNK-002` и `BNK-030`). **Дефолтная генерация шипит полный набор,
включая оба experimental-правила** — осознанное решение оператора (BNK-030 —
безопасный NMR-страховочный для нераспознанных документов). Правила без tier
проходят фильтр всегда.

Быстрая правка без транспорта: отредактируйте `rules/rules.json` и укажите путь к нему
в параметре «rules override» — правила загрузятся в рантайме через `/UI2/CL_JSON`
(битый JSON → предупреждение + откат на вшитые правила).

**Правила как заменяемые «скиллы».** Каждый тип документа — отдельный набор:
`rules/banking.rules.json` и `rules/w9.rules.json`. Override **частичный** — файл только с
`rules_w9` заменяет лишь W-9, банковский модуль не трогается (и наоборот). Смотреть/экспортировать
правила прямо в SAP — отчёт `ZMDMDOC_RULES`. Полная инструкция — [docs/RULES.md](docs/RULES.md).

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
правила `SAP-000..009`) — источник-независима и покрыта юнит-тестами; MDG-специфика изолирована
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

Контракт публичных API классов: `docs/CONTRACT.md`. Передача проекта: `HANDOFF.md`.
