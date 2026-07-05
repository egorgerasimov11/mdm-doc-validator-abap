# Интеграция ZMDMDOC в SAP — пошаговая инструкция и зависимости

Документ описывает, как установить ABAP-клон валидатора (`ZMDMDOC`) в систему SAP,
какие стандартные компоненты для этого нужны, как настроить опциональный вызов Ollama,
и как встроить программу в фоновые задания / вызывать её из другого кода.

Целевая среда: **on-premise SAP, ABAP ≥ 7.50** (ECC EhP8, S/4HANA любой версии, ABAP Platform).
Не для BTP ABAP Environment (Steampunk) — там нет прямого доступа к файловой системе SAPGUI.

---

## 0. TL;DR — что нужно

| Нужно | Обязательно? | Зачем |
|---|---|---|
| ABAP ≥ 7.50 | да | classic regex, синтаксис отчёта |
| [abapGit](https://abapgit.org) | да | импорт исходников |
| Ключ разработчика / транспорт | да (кроме `$TMP`) | создание Z-объектов |
| Компонент **SAP_UI** (`/UI2/CL_JSON`) | почти всегда | LLM-вызовы, JSON-выгрузка, override правил |
| Роль с S_GUI, S_DATASET, S_ICF | да | загрузка файлов + исходящий HTTP |
| [Ollama](https://ollama.com) + модели | нет (опция) | извлечение полей LLM, чтение сканов |
| Разрешение исходящего HTTP на app-сервере | только для Ollama | вызов `/api/chat` |

Ядро (чтение PDF + regex-извлечение + правила + вердикт) работает **без** SAP_UI, без Ollama
и без исходящего HTTP. Всё перечисленное с пометкой «опция» нужно только для LLM-режима.

---

## 1. Стандартные ABAP-зависимости (проверить наличие ДО импорта)

Все — стандартные классы SAP; в 7.50+ они есть практически всегда. Проверьте в SE24 / SE80,
если система урезанная:

| Класс / объект | Используется в | Комментарий |
|---|---|---|
| `/UI2/CL_JSON` | `ZCL_MDMDOC_LLM`, `ZCL_MDMDOC_RULES`, `ZCL_MDMDOC_REPORT` | компонент **SAP_UI** (стандарт с NW 7.40 SP08). Без него отключаются LLM, JSON-выгрузка, JSON-override правил — ядро работает |
| `CL_ABAP_GZIP` | `ZCL_MDMDOC_PDF` | инфляция FlateDecode-потоков PDF. **Проверить первым** (см. §7) |
| `CL_ABAP_ZIP` | `ZCL_MDMDOC_FILE`, `ZCL_MDMDOC_PDF` | распаковка `.zip`-контейнеров, fallback-инфляция |
| `CL_ABAP_MESSAGE_DIGEST` | `ZCL_MDMDOC_FILE` | SHA-256 → run id документа |
| `CL_HTTP_CLIENT` (`CREATE_BY_URL`) | `ZCL_MDMDOC_LLM` | вызовы Ollama `/api/tags`, `/api/chat` |
| `CL_HTTP_UTILITY` | `ZCL_MDMDOC_LLM`, `ZCL_MDMDOC_FILE` | base64 encode/decode (vision-картинки, вложения `.eml`) |
| `CL_GUI_FRONTEND_SERVICES` | `ZMDMDOC`, `ZCL_MDMDOC_FILE` | выбор/загрузка файла с ПК, выгрузка JSON |
| `CL_ABAP_CONV_IN_CE` / `CL_ABAP_CODEPAGE` | `ZCL_MDMDOC_FILE`, `ZCL_MDMDOC_PDF` | xstring ↔ string (UTF-8 / Latin-1) |
| `CL_ABAP_REGEX` / `FIND REGEX` | `ZCL_MDMDOC_REGEX`, `ZCL_MDMDOC_RULES` | classic regex (**не PCRE** — совместимость с 7.50) |

Внешних Z-зависимостей нет: пакет самодостаточен. Единственная внутренняя зависимость —
интерфейс `ZIF_MDMDOC_TYPES` (входит в пакет) и сгенерированный класс `ZCL_MDMDOC_RULES_DATA`.

> **Проверка одной командой** (SE38 → создать временный отчёт или использовать консоль):
> убедитесь, что классы `/UI2/CL_JSON`, `CL_ABAP_GZIP`, `CL_ABAP_ZIP` открываются в SE24.
> Если `/UI2/CL_JSON` отсутствует — доустановите компонент SAP_UI или используйте систему
> в детерминированном режиме (без LLM/JSON).

---

## 2. Импорт через abapGit

### 2.1. Предварительно
1. Установите abapGit (отчёт `ZABAPGIT_STANDALONE` или полная версия) — https://abapgit.org.
2. Для онлайн-режима: настройте SSL для github.com в **STRUST** (SSL client SSL Client (Standard))
   и включите сервис в **SICF** при необходимости. Для offline-режима SSL не нужен.
3. Создайте пакет назначения:
   - SE80 → правый клик → Create → Package → **`ZMDMDOC`** (или ваш Z-неймспейс);
   - Software Component `HOME` / `LOCAL`, назначьте транспортный слой при переносе между системами;
   - для локальных тестов допустим `$TMP` (без транспорта).

### 2.2. Онлайн-импорт (если есть доступ к репозиторию по HTTPS)
1. abapGit → **New Online** → URL репозитория → Package `ZMDMDOC` → Branch `main`.
2. **Pull** → abapGit создаст все объекты пакета.
3. Активируйте всё: SE80 → пакет `ZMDMDOC` → Activate all (или Ctrl+F3 по объектам).

### 2.3. Offline-импорт (ZIP)
1. Заархивируйте содержимое репозитория (папка `src/` обязательна; `.abapgit.xml` в корне).
   Проще: `git archive` или скачать ZIP с git-хостинга.
2. abapGit → **New Offline** → Package `ZMDMDOC` → **Import ZIP** → выберите архив.
3. **Pull** → активируйте все объекты.

### 2.4. Что появится в системе
- 1 программа: `ZMDMDOC` (executable report).
- 1 интерфейс: `ZIF_MDMDOC_TYPES`.
- 12 классов: `ZCL_MDMDOC_FILE / _PDF / _SNIFF / _REGEX / _LLM / _EXTRACT / _RULES /
  _RULES_DATA / _VERDICT / _MASK / _NORM / _REPORT`.
- Класс сообщений (если добавлен) `ZMDMDOC` для текстов вердикта.

### 2.5. Проверка после импорта
1. SE80 → пакет → выделить все классы → **Run → Unit Tests** (Ctrl+Shift+F10).
   Все тесты `HARMLESS/SHORT`, без сети и файлов — должны пройти зелёными.
2. SA38 → `ZMDMDOC` → должен открыться selection screen без синтаксических ошибок.

---

## 3. Авторизации (роль для пользователя-оператора)

Минимальный набор объектов авторизации (PFCG-роль):

| Объект | Значения | Зачем |
|---|---|---|
| `S_TCODE` | `SA38` (или своя Z-транзакция, см. §4) | запуск отчёта |
| `S_GUI` | ACTVT `61` (Upload/Download) | чтение файла с ПК, выгрузка JSON |
| `S_DATASET` | PROGRAM `ZMDMDOC*`, ACTVT `33`(read)/`34`(write), фильтр по путям | режим «сервер приложений» (`OPEN DATASET`) |
| `S_ICF` | ICF_FIELD `SERVICE`, значение — по вашей политике исходящего HTTP | вызовы Ollama (только LLM-режим) |
| `S_DEVELOP` | только на dev-системе | активация/юнит-тесты |

Если LLM не используется — `S_ICF` не нужен. Если файлы только с ПК — `S_DATASET` можно
не выдавать (радио «сервер приложений» тогда просто не сработает — это ожидаемо).

---

## 4. (Опционально) Своя транзакция вместо SA38

Чтобы операторы не имели широкого `SA38`:
1. SE93 → создать транзакцию **`ZMDMDOC`** → тип «Program and selection screen (report transaction)»
   → Program `ZMDMDOC`.
2. Выдать в роли `S_TCODE` = `ZMDMDOC` вместо `SA38`.

---

## 5. (Опционально) Настройка исходящего HTTP к Ollama

Нужно **только** если включаете LLM-режим (извлечение полей моделью и чтение сканов).

### 5.1. Где должен работать Ollama
`CL_HTTP_CLIENT=>CREATE_BY_URL` открывает соединение **с сервера приложений SAP**, а не с ПК
оператора. Поэтому URL должен быть доступен именно серверу приложений:
- Ollama на том же хосте, что и app-сервер (напр. локальный ABAP Developer Trial в Docker):
  `http://localhost:11434`.
- Ollama на другом хосте в сети: запустить как `OLLAMA_HOST=0.0.0.0 ollama serve`,
  URL `http://<хост-или-IP>:11434`.

### 5.2. Модели
```bash
ollama pull qwen3:4b        # текстовая модель — извлечение полей из текста документа
ollama pull qwen2.5vl:7b    # vision — транскрипция картинок-сканов (.png/.jpg)
```

### 5.3. HTTP vs HTTPS
- **Обычный HTTP** (`http://…:11434`): дополнительная настройка не нужна — это исходящий вызов,
  **SM59-назначение и SICF-сервис не требуются**. Достаточно сетевой доступности и `S_ICF`.
- **HTTPS**: сертификат CA эндпоинта нужно добавить в **STRUST** → «SSL client SSL Client (Standard)»
  (или в тот PSE, что использует ваш профиль), иначе рукопожатие TLS упадёт.

### 5.4. Прокси
Если исходящий трафик идёт через корпоративный прокси — задайте его в вызове
`CREATE_BY_URL( proxy_host = … proxy_service = … )`. В текущей версии параметры прокси пустые
(прямое соединение). Если нужен прокси — это единственная точка правки в `ZCL_MDMDOC_LLM`
(метод создания клиента); вынесено намеренно узко.

### 5.5. Проверка доступности
На selection screen включите флажок LLM и укажите URL. Программа сначала делает `GET /api/tags`
(таймаут 5 с). Если Ollama недоступен — вы получите finding `LLM-001` и программа продолжит
в детерминированном режиме (regex-only). То есть неверная настройка HTTP **не ломает** работу,
а деградирует до режима без модели.

---

## 6. Встраивание в процессы

### 6.1. Фоновое задание (SM36/SM37)
1. Создайте вариант отчёта `ZMDMDOC` (файл — с **сервера приложений**, т.к. в фоне нет ПК-сессии;
   радио «сервер приложений» + путь на прикладном сервере).
2. Для фона включите флажок «строгий режим»: при вердикте REJECT программа выдаёт `MESSAGE TYPE 'E'`
   → задание переходит в статус **Canceled** (машиночитаемый аналог «exit code 1» Python-версии).
   При ACCEPT/WARNING задание завершается успешно.
3. Статус задания в SM37 и есть «код возврата» для планировщика.

Соответствие exit-кодов Python-оригинала статусам SAP:

| Python `mdmdoc` | ZMDMDOC (фон, строгий режим) |
|---|---|
| 0 ACCEPT | задание Finished, MESSAGE S |
| 1 REJECT | задание **Canceled** (MESSAGE E) |
| 2 REVIEW/WARNING | задание Finished, MESSAGE «W» |
| 3 LLM недоступен | finding `LLM-001`, задание Finished |
| 4 нечитаемый документ | finding `EXT-001`/`EXT-002`, задание Finished |

### 6.2. Вызов из другого ABAP-кода
```abap
SUBMIT zmdmdoc
  WITH p_file  = '/interface/in/vendor_bank_letter.pdf'
  WITH rb_srv  = abap_true       " файл с сервера приложений
  WITH rb_auto = abap_true       " автоопределение класса документа
  WITH cb_llm  = abap_false      " детерминированный режим
  AND RETURN.

DATA lv_verdict TYPE string.
DATA lv_json    TYPE string.
IMPORT verdict = lv_verdict
       json    = lv_json
  FROM MEMORY ID 'ZMDMDOC_RESULT'.
" lv_verdict ∈ { ACCEPT | REJECT | WARNING | NEED_MANUAL_REVIEW }
" lv_json    = отчёт в формате mdmdoc.v1 (при cb_json = abap_true)
```

### 6.3. Вызов классов напрямую (без экрана)
Логика пайплайна вынесена в классы, отчёт лишь тонкая обёртка. Для полностью программного
использования (например, из воркфлоу или RFC-обёртки) вызывайте классы напрямую в порядке:
`ZCL_MDMDOC_FILE=>read` → `unwrap` → `ZCL_MDMDOC_PDF=>extract_text`
→ `ZCL_MDMDOC_SNIFF=>sniff_doc_class` → `ZCL_MDMDOC_REGEX=>extract_candidates`
→ (опц.) `ZCL_MDMDOC_LLM->extract_fields` → `ZCL_MDMDOC_EXTRACT=>build`
→ `NEW ZCL_MDMDOC_RULES( )->run` → `ZCL_MDMDOC_VERDICT=>decide`
→ `ZCL_MDMDOC_REPORT=>build_list / build_json`.
Точные сигнатуры — в [docs/CONTRACT.md](CONTRACT.md).

### 6.4. RFC-обёртка для внешних систем (при необходимости)
Если документ приходит из внешней системы (например, из middleware вместе с байтами файла),
оберните вызов классов в RFC-enabled функциональный модуль: на вход `XSTRING` содержимого файла
+ имя файла, на выход — вердикт и JSON. Это ~30 строк поверх существующих классов; в поставку
не входит намеренно (у каждого ландшафта свой контракт интеграции), но архитектура к этому готова:
`ZCL_MDMDOC_FILE` уже умеет принимать `xstring` напрямую в структуре `ty_doc`.

---

## 7. Порядок проверки на целевой системе (риски)

Проверяйте в этом порядке — от самого рискованного к стандартному:

1. **`CL_ABAP_GZIP=>DECOMPRESS_BINARY` со zlib-потоками (RFC 1950).**
   PDF использует FlateDecode = zlib, а не gzip. `ZCL_MDMDOC_PDF` пробует три стратегии инфляции
   (прямая → срез zlib-заголовка + синтетический gzip-конверт → синтетический ZIP через
   `CL_ABAP_ZIP`). Если на вашем ядре все три не срабатывают — читаются только PDF с несжатыми
   потоками; обход в README (пере-экспорт PDF через «печать в PDF»). Проверьте на реальном
   сжатом PDF в dev.
2. **`/UI2/CL_JSON`** присутствует (компонент SAP_UI). Нет → LLM/JSON/override отключены,
   ядро работает.
3. **`CL_ABAP_ZIP`** — поведение при несовпадении CRC (для `.zip`-контейнеров и 3-й стратегии PDF).
4. Остальное (`CL_ABAP_MESSAGE_DIGEST`, `CL_HTTP_CLIENT`, `CL_HTTP_UTILITY`,
   `CL_GUI_FRONTEND_SERVICES`) — стандарт с 7.40, риск низкий.

---

## 8. Обновление правил после установки

Правила зашиты в сгенерированный класс `ZCL_MDMDOC_RULES_DATA` (источник — `rules/*.yaml`).

- **Постоянное изменение** (с транспортом): правите `rules/banking.yaml` / `rules/w9.yaml`,
  запускаете `python3 tools/gen_rules_abap.py`, делаете abapGit Pull, активируете, переносите.
- **Быстрая правка без транспорта**: отредактируйте `rules/rules.json`, положите его на ПК или
  сервер приложений и укажите путь в параметре «rules override» на selection screen — правила
  загрузятся в рантайме через `/UI2/CL_JSON`. Битый JSON → предупреждение + откат на вшитые правила.

---

## 9. Чек-лист внедрения

- [ ] ABAP ≥ 7.50, abapGit установлен.
- [ ] Пакет `ZMDMDOC` создан, транспортный слой назначен (или `$TMP` для теста).
- [ ] `/UI2/CL_JSON`, `CL_ABAP_GZIP`, `CL_ABAP_ZIP` открываются в SE24.
- [ ] Импорт через abapGit → активация всех объектов без ошибок.
- [ ] Юнит-тесты пакета зелёные (Ctrl+Shift+F10).
- [ ] `ZMDMDOC` запускается из SA38, экран открывается.
- [ ] Роль оператора: `S_TCODE`, `S_GUI`, при серверных файлах `S_DATASET`, при LLM `S_ICF`.
- [ ] (LLM) Ollama доступен **с сервера приложений**, модели `qwen3:4b` + `qwen2.5vl:7b` скачаны.
- [ ] (LLM+HTTPS) сертификат CA в STRUST.
- [ ] Smoke-тест: прогнать реальный `bank_letter.pdf` → получить вердикт; при включённом LLM —
      прогнать скан `.png` → проверить транскрипцию.
- [ ] (Фон) вариант с серверным путём + строгий режим → проверить статус в SM37.

---

## 10. Встраивание в SAP MDG (сверка Change Request через BAdI)

Отдельный сценарий: не отдельный репорт, а **автоматическая проверка внутри MDG**. Пользователь
создаёт клиента/вендора в Fiori как Change Request, прикладывает документ (bank letter / W-9) во
вложение заявки. При проверке заявки система читает вложение, извлекает реквизиты, читает данные
самого CR (имя, адрес, банк, налог) и **выдаёт warning** в логе сообщений заявки при расхождениях.

### 10.1. Как это устроено

Триггер — **BAdI `USMD_RULE_SERVICE`** (enhancement spot той же MDG-инфраструктуры валидаций),
реализация в классе **`ZCL_MDG_BP_FIELD_DERR_VAL`** (`IF_EX_USMD_RULE_SERVICE`), фильтр по модели
данных `BP`. Поток (метод `CHECK_ENTITY`, срабатывает один раз — guard на якорную сущность
`BP_BANKDT`):

1. `ZCL_MDMDOC_MDG_READER( io_model, i_crequest )`.
2. `read_cr_attachments` → байты вложения(й) CR (через GOS на объекте заявки).
3. `read_cr_fields` → данные CR через `io_model->read_entity_data_all` по сущностям
   (имя/адрес/банк/налог), маппинг в SAP_KEYS.
4. Для PDF-вложения: `ZCL_MDMDOC_PDF=>extract_text` → sniff → `ZCL_MDMDOC_REGEX` →
   `ZCL_MDMDOC_EXTRACT` (**LLM выключен** — BAdI синхронный, без внешнего HTTP; только быстрый
   детерминированный путь).
5. `ZCL_MDMDOC_COMPARE=>compare( doc, cr )` → findings `SAP-000..008`.
6. Findings → сообщения заявки: `WARNING` (`W`); REJECT-findings можно поднимать как `E`
   (блокирует submit). `SAP-000` (всё совпало) не выводится.

Логика сравнения полностью переиспользует ядро; MDG-специфика сосредоточена в двух классах
(`ZCL_MDMDOC_MDG_READER`, `ZCL_MDG_BP_FIELD_DERR_VAL`).

### 10.2. Предпосылки

- SAP MDG активен, модель данных **`BP`** (MDG-BP / MDG-Customer / MDG-Supplier).
- Базовые классы ZMDMDOC установлены и активированы (главы 1–2).
- Класс сообщений **`ZMDMDOC`** (SE91), сообщение `001` с текстом `&1&2&3&4` (текст finding'а
  переносится в MSGV1..MSGV4).

### 10.3. Что подтвердить на dev-системе (VERIFY ON SYSTEM)

Два MDG-класса намеренно **исключены из офлайн-проверки abaplint** (используют типы фреймворка MDG,
которых нет вне системы) и помечены в коде. Перед активацией сверьте на своей системе:

1. **Сигнатуру `IF_EX_USMD_RULE_SERVICE~CHECK_ENTITY`** — точные имена/типы параметров
   (`io_model` / `i_crequest` / `i_fieldname` / `ct_message`) и способ возврата сообщений. Метод
   реализации наследует сигнатуру от интерфейса — при расхождении имён поправьте обращения.
2. **Тип `io_model`** (`if_usmd_model_ext` vs иной) и точный вызов `read_entity_data_all` /
   `create_data_reference` (имена структур-констант).
3. **Технические имена сущностей и полей** модели `BP` (таблица маппинга ниже) — из
   MDGIMG → «Обработка модели данных» / tx `USMD_ENTITY`. У разных клиентов имена различаются.
4. **API вложений CR** — объектный тип заявки для GOS (`USMD_CREQ` в шаблоне) и класс
   `CL_GOS_API` (или альтернативу на вашем релизе). Метод написан как шаблон с graceful-fallback:
   если API недоступен — вернёт ошибку, а не дамп.

### 10.4. Маппинг MDG-BP → SAP_KEYS (подтвердить)

| SAP_KEY | Сущность (`read_entity_data_all`) | Поле |
|---|---|---|
| account_holder / account_name | BP_CENTRL (или BP_HEADER) | NAME_ORG1(+2) / NAME_FIRST+LAST |
| street / city | ADDRESS | STREET / CITY1 |
| bank_country | BP_BANKDT | BANKS |
| bank_key | BP_BANKDT | BANKL |
| bank_account | BP_BANKDT | BANKN |
| control_key | BP_BANKDT | BKONT |
| iban | BP_IBAN (или BP_BANKDT) | IBAN |
| bank_name / swift_bic | из BANKS+BANKL → BNKA (active) | BANKA / SWIFT |
| tin (US) | BP_TAXNUM | TAXTYPE (US1/US2) + TAXNUM |

### 10.5. Установка BAdI-реализации

1. Активировать базовый пакет ZMDMDOC (главы 1–2), включая `ZCL_MDMDOC_COMPARE`,
   `ZCL_MDMDOC_MDG_READER`, `ZCL_MDG_BP_FIELD_DERR_VAL`.
2. SE91 → класс сообщений `ZMDMDOC`, сообщение `001` = `&1&2&3&4`.
3. SE18/SE19 (или MDGIMG → BAdI валидаций/деривации) → enhancement spot `USMD_RULE_SERVICE` →
   создать реализацию → класс `ZCL_MDG_BP_FIELD_DERR_VAL`, **фильтр `USMD_MODEL = 'BP'`**,
   активировать.
4. (При необходимости) сверить/поправить имена сущностей-констант в `ZCL_MDMDOC_MDG_READER`
   (`c_ent_*`) и якорную сущность `c_anchor_entity` в `ZCL_MDG_BP_FIELD_DERR_VAL` под вашу модель.

### 10.6. Авторизации и производительность

- Работает в контексте сессии MDG-заявки — **дополнительный RFC/HTTP не нужен** (в MDG-пути LLM
  отключён; сеть не задействуется). Чтение вложений/сущностей идёт под правами пользователя заявки.
- Парсинг PDF + regex — миллисекунды. Запуск ограничен якорной сущностью и только PDF-вложениями,
  чтобы не замедлять каждый check.

### 10.7. Где виден результат

Warning'и появляются в **логе сообщений Change Request** (Fiori «Мои заявки» / UI заявки).
`W` не блокирует submit; `E` (если включите для жёстких расхождений) — блокирует.

### 10.8. Тест на системе

1. Создать CR для BP с банковскими данными; во вложение положить bank letter, где **IBAN
   отличается** от введённого в заявке.
2. Нажать Check/Submit → в логе сообщений появляется warning `[SAP-001] IBAN mismatch …`
   (значения маскированы, напр. `DE**…4931 vs DE**…4999`).
3. Совпадающий документ → warning'ов нет (внутренний `SAP-000` не выводится).

### 10.9. Чек-лист MDG-внедрения

- [ ] Базовый пакет ZMDMDOC активен (вкл. COMPARE + оба MDG-класса).
- [ ] Класс сообщений `ZMDMDOC` / `001` создан.
- [ ] Сигнатура `IF_EX_USMD_RULE_SERVICE~CHECK_ENTITY` и `read_entity_data_all` сверены,
      обращения в коде поправлены при необходимости.
- [ ] Имена сущностей/полей модели `BP` сверены (`c_ent_*`, маппер), якорная сущность выбрана.
- [ ] API вложений CR (GOS/объектный тип) подтверждён и подставлен.
- [ ] BAdI-реализация создана (spot `USMD_RULE_SERVICE`), фильтр `USMD_MODEL = 'BP'`, активна.
- [ ] End-to-end тест: CR + вложение с неверным IBAN → warning `SAP-001` в логе заявки.

