# MDG system facts — reconnaissance log

**Purpose.** Everything we have *verified in the customer's SAP system* about the MDG integration,
plus what is still assumed. Read this **before touching** `ZCL_MDMDOC_MDG_CHECK`,
`ZCL_MDMDOC_MDG_READER`, `ZCL_MDMDOC_MDG_MAP`, `ZCL_MDG_BP_FIELD_DERR_VAL` or chapter 10 of
[INTEGRATION.md](INTEGRATION.md). Every design decision in the MDG path traces back to a fact here.

**Rule:** a line moves from *Assumed* to *Verified* only with an on-system source (transaction +
screen). Never "improve" the design against an assumption.

**System observed:** `MDQ` client `100` (quality). Custom namespace convention: `ZCLMDG_*`.
Last updated: 2026-07-05.

---

## A. Verified facts

### A1. BAdI `USMD_RULE_SERVICE`

*Source: SE18 → Enhancement Spot `USMD_RULE_SERVICE` → Attributes / Enh. Spot Element Definitions.*

| Property | Value | Consequence |
|---|---|---|
| Enhancement method | Object Plug-in (BAdI) | |
| Package / origin | `USMD7`, SAP, created 2008-04-25 | standard MDG |
| **Multiple Use** | **NO (unchecked)** | only ONE implementation runs **per filter value combination**. It is *not* a global "one implementation" rule — see A7: 53 implementations coexist, separated by filter. Do not collide with a taken combination. |
| Limited filter use | no | |
| Implemented at SAP only | no | custom implementations allowed |
| **Instance Creation Mode** | **Reusing Instantiation** | the BAdI instance is reused → check methods fire repeatedly → **cache expensive work** (we cache the parsed PDF by SHA) |
| Fallback class | none | |
| Interface | `IF_EX_USMD_RULE_SERVICE` | |
| Filter | exists (node `Filter` in the tree) — **field list not yet captured** | see B1 |

**A sibling BAdI lives in the same enhancement spot:** `USMD_RULE_SERVICE_CROSS…` (name truncated on
screen; almost certainly `USMD_RULE_SERVICE_CROSS_ET`), interface **`IF_EX_USMD_RULE_SERVICE2`**,
description starts with "Valid…". *Technical Details* tab confirms both interfaces are referenced by
the spot. Semantics: cross-entity-type validations — potentially a better home for our cross-entity
comparison. **Its `Multiple Use` flag is not yet checked.**

### A2. Interface `IF_EX_USMD_RULE_SERVICE` — 11 methods

*Source: SE24 → `IF_EX_USMD_RULE_SERVICE` → Methods.* All are instance methods, public.
**All 11 must exist in an implementing class or it will not activate.**

| Method | Description |
|---|---|
| `CHECK_ENTITY` | Check One Single Master Record |
| `CHECK_ENTITY_HIERARCHY` | Check of Hierarchy |
| `CHECK_CREQUEST_START` | Start of Check of a Change Request |
| `CHECK_CREQUEST` | Master Data Check (Call per Entity Type) |
| `CHECK_CREQUEST_HIERARCHY` | Check of Hierarchy in Change Requests (by Entity Type) |
| **`CHECK_CREQUEST_FINAL`** | **Completion of Check of a Change Request** ← our hook |
| `CHECK_EDITION_START` | Start of Check of an Edition |
| `CHECK_EDITION` | Master Data Check (Call per Entity Type) |
| `CHECK_EDITION_HIERARCHY` | Check of Hierarchy of an Edition (by Entity Type) |
| `CHECK_EDITION_FINAL` | Completion of Check of an Edition |
| `DERIVE_ENTITY` | Derivation of Data for a Master Record |

### A3. Signature — `CHECK_CREQUEST_FINAL` (our hook)

*Source: SE24 → Methods → `CHECK_CREQUEST_FINAL` → Parameters.*

| Parameter | Type | Typing | Associated type |
|---|---|---|---|
| `ID_EDITION` | Importing | Type | `USMD_EDITION` |
| `ID_CREQUEST` | Importing | Type | `USMD_CREQUEST` |
| `IO_MODEL` | Importing | Type Ref To | `IF_USMD_MODEL_EXT` |
| `ID_LOG_HANDLE` | Importing | Type | `BALLOGHNDL` |

**No EXPORTING parameters.** → messages must be written to the **application log (BAL)** using
`ID_LOG_HANDLE` (`BAL_LOG_MSG_ADD`), not returned in a table. Fires **once per change request**.

### A4. Signature — `CHECK_ENTITY` (deliberately unused)

*Source: SE24 → Signature of the implemented method in `ZCLMDG_GTS_BP_VALIDATION`.*

| Parameter | Type | Associated type | Note |
|---|---|---|---|
| `IO_MODEL` | Importing | `IF_USMD_MODEL_EXT` | MDM data model |
| `ID_EDITION` | Importing | `USMD_EDITION` | |
| `ID_CREQUEST` | Importing | `USMD_CREQUEST` | **OPTIONAL** |
| `ID_ENTITYTYPE` | Importing | `USMD_ENTITY` | entity type |
| `IF_ONLINE_CHECK` | Importing | `USMD_FLG` DEFAULT `ABAP_TRUE` | `' '` = Validation, `'X'` = Online Check |
| `IT_DATA` | Importing | ANY TABLE | master data rows of that entity |
| `ET_MESSAGE` | Exporting | `USMD_T_MESSAGE` | messages |

Fires **per entity type AND per record** → wrong granularity for a whole-document check.
(Our earlier "anchor entity guard" existed only to work around this. It is gone.)

### A5. How real code reads CR data and context

*Source: `ZCL_MDG_BP_FIELD_DERR_VAL` and `ZCLMDG_GTS_BP_VALIDATION` source in SE24.*

Reading staged (change-request) entity data — **note the parameter names differ from the BAdI
method's**:

```abap
io_model->read_entity_data_all(
  EXPORTING
    i_fieldname    = 'BP_HEADER'      " the entity
    if_active      = ''               " '' = staged CR data, 'X' = active
    i_crequest     = lv_crequest_id
    it_sel         = lt_sel
  IMPORTING
    et_data_entity = lt_data_entity ).
```

Reading the CR context without a parameter (used by the GTS class):

```abap
lr_context = cl_usmd_app_context=>get_context( ).          " if_usmd_app_context
lr_context->get_attributes( IMPORTING ev_process       = lv_process ).       " usmd_process
lr_context->get_attributes( IMPORTING ev_crequest_type = lv_crequest_type ). " usmd_crequest_type
```

Field access on generic entity rows (the pattern our reader uses):

```abap
LOOP AT it_data ASSIGNING <ls_data>.
  ASSIGN COMPONENT 'NAME1' OF STRUCTURE <ls_data> TO FIELD-SYMBOL(<lv_name1>).
ENDLOOP.
```

### A6. Existing implementation observed

`ZCLMDG_GTS_BP_VALIDATION` — "developed to screen BP in GTS and populate results accordingly in MDG".
Status *Implemented / Active*. Two notes for the customer's team:

- **`break skuruganti.`** sits in active code (line ~43 of `CHECK_ENTITY`) — a developer breakpoint
  left behind. Harmless for other users, but it should not be in a transported object.
- The method is effectively **a stub**: it fetches the context, loops `it_data`, assigns `NAME1`, and
  ends. No `ET_MESSAGE` is filled, no `SCREENING_RESULT` written (the intended fields
  `BP_TYPE / SCREENING_RESULT / ERROR_MESSSAGE` [sic] are only comments). GTS screening is unfinished.

### A7. Implementation landscape — **53 implementations**

*Source: SE18 → `USMD_RULE_SERVICE` → Enh. Spot Element Definitions → node `Implementations`.*

Despite `Multiple Use = NO`, **53 implementations coexist**. They are separated by **filter values**,
and the naming makes the filter dimensions obvious: **data model + entity type** (one implementation
per entity).

| Enhancement Implementation | BAdI Implementation | SWC | Meaning |
|---|---|---|---|
| `USMDZ7_RULE_SERVICE` | `USMDZ7_RS_ACCOUNT`, `_CCTR`, `_CELEM`, `_COMPANY`, `_CONSCHAR`, `_CONSGRP`, `_CONSUNIT`, `_FRS`, `_FSI`, `_FSIH`, `_FSIT`, `_IORDER`, `_PCTR`, `_PCTRG`, `_PCTRH`, `_SUBMPACK`, `_TRANSTYPE`, `_BDC`, `_BDCSET`, `_ACCCCDET` | MDG_FND | SAP standard, **one per entity** of the financial model |
| `ZMDG_0G_RULE_SERVICE` | `ZMDG_0G_*_IMPL` | HOME | customer, model `0G` (MDG-F) |
| **`ZMDG_BP`** | **`ZMDG_BP_BP_BKDTL_IMPL`**, **`ZMDG_BP_BP_CENTRL_IMPL`** | HOME | customer, model `BP`, per entity |
| `ZMDG_BP_CUST` | `ZMDG_BP_CUST_BP_SALES_IMPL`, `ZMDG_BP_CUST_CUSGEN_IMPL` | HOME | MDG-C |
| `ZMDG_BP_SUPPL` | `ZMDG_BP_SUPPL_BP_PORG_IMPL`, `ZMDG_BP_SUPPL_BP_VENGEN_IMPL` | HOME | MDG-S |
| **`ZMDG_BP_FIELD_VALIDATIONS`** | **`ZBADI_MDG_BP_DERIVATION_VALI`** | HOME | "Customer & Sup…" — the implementation behind the class Egor first pointed at |
| `ZMDG_BP_GTS_VALIDATION` | `ZMDG_GTS_BP_VALIDATION` | HOME | class `ZCLMDG_GTS_BP_VALIDATION` (A6) |
| `ZMDG_MM_MATERIAL` | `ZMDG_MM_MARCBASIC_IMPL`, `_MARCMRPPP_IMPL`, `_UNITOFMSR_IMPL` | HOME | model `MM` |
| `MDG_BS_BP_DESCRIPTION`, `MDG_BS_BP_TAXJURCODE`, `MDG_BS_SUPPL_ACCGRP_ID`, `MDG_BS_SUPPL_VENDOR_LIKE_UI`, `MDG_SF_RULE_SERVICE`, `USMDA3_IMP_RULE_SERVICE_BADI`, `USMDZ3_IMP_RULE_SERVICE_BADI` | — | MDG_FND / MDG_APPL | SAP standard |

**Derived entity names of model `BP` in this system** (implementations are named after the entity
they filter on):

| Entity | Evidence |
|---|---|
| **`BP_BKDTL`** — bank details | `ZMDG_BP_BP_BKDTL_IMPL` (**not** `BP_BANKDT`, which we had guessed) |
| `BP_CENTRL` — central data | `ZMDG_BP_BP_CENTRL_IMPL` |
| `BP_SALES` | `ZMDG_BP_CUST_BP_SALES_IMPL` |
| `CUSGEN` | `ZMDG_BP_CUST_CUSGEN_IMPL` |
| `BP_PORG` | `ZMDG_BP_SUPPL_BP_PORG_IMPL` |
| `BP_VENGEN` | `ZMDG_BP_SUPPL_BP_VENGEN_IMPL` |

`ZCL_MDMDOC_MDG_MAP` defaults were corrected to `BP_BKDTL` accordingly. `ZMDMDOC_MDG_DISCOVER`
overrides them from the live model anyway.

**Still unresolved — how CR-level methods dispatch.** The filter is per entity, but
`CHECK_CREQUEST_FINAL` is *not* entity-scoped. Which implementation(s) receive it (all matching the
model? one with a blank entity filter?) is unknown until the `Filter` node and the `Filter Values` of
the BP implementations are read. **This determines whether we may register our own implementation or
must call in from an existing one.** See C1.

---

## B. Design consequences (why our code looks the way it does)

1. **`ZCL_MDMDOC_MDG_CHECK` is a plain service class, not a BAdI implementation** — because the BAdI
   is not Multiple Use (A1) and the `BP` slot is taken (A6). Integration is a 2-line call-in placed
   in the *existing* implementation's `CHECK_CREQUEST_FINAL`.
2. **The hook is `CHECK_CREQUEST_FINAL`** (A3), not `CHECK_ENTITY` (A4). One call per CR, with
   `id_crequest` + `io_model` in hand.
3. **Messages go to BAL** via `id_log_handle` (A3) — `BAL_LOG_MSG_ADD`, message class `ZMDMDOC` no.
   `001` (`&1&2&3&4`). Default severity `W`; `E` only when `iv_block = abap_true`.
4. **The parsed attachment is cached by SHA** — Reusing Instantiation (A1) means check methods can
   fire many times per session; PDF parsing must not repeat.
5. **`ZCL_MDG_BP_FIELD_DERR_VAL` is a reference implementation only** — all 11 methods (A2), and its
   header tells you not to activate it when the `BP` slot is occupied.

---

## C. Still to collect — prioritized checklist

### C1. Blocks the integration (do these first)

| # | Where | What to capture | Why it decides the design |
|---|---|---|---|
| 1 | SE18 → `USMD_RULE_SERVICE` → tree node **`Filter`** | the filter **field names** (`USMD_MODEL`? `USMD_ENTITY`? both?) | tells us the dimensions we must not collide on |
| 2 | Same screen → select a BP row → button **`Filter Values`** — do it for `ZMDG_BP_FIELD_VALIDATIONS / ZBADI_MDG_BP_DERIVATION_VALI`, `ZMDG_BP_GTS_VALIDATION / ZMDG_GTS_BP_VALIDATION`, `ZMDG_BP / ZMDG_BP_BP_BKDTL_IMPL` | the concrete filter values of each | **the** decision: is there a free combination for our own implementation, or do we call in? If one of them has model=`BP` + entity=blank, that one owns the CR-level methods → call-in goes there |
| 3 | SE18 → expand **`USMD_RULE_SERVICE_CROSS…`** | full name, **`Multiple Use` flag**, interface | if Multiple Use is ON, we get our own implementation with no call-in into a foreign class — strictly better |
| 4 | SE24 → `IF_EX_USMD_RULE_SERVICE2` → Methods (+ Parameters of the CR-level one) | method list and signatures | to judge (3) |

> A6 shows `ZCLMDG_GTS_BP_VALIDATION` implements `CHECK_ENTITY` and reaches for the CR context via
> `cl_usmd_app_context=>get_context( )` instead of taking it from a parameter — a hint that its
> filter is entity-scoped and that CR-level context is not handed to it. Confirm with (2).

### C2. Our code calls these APIs — verify they exist with these names

Each row is a concrete line in our code that will fail to activate if the API differs.

| Our code | Assumed API | How to verify |
|---|---|---|
| `zcl_mdmdoc_mdg_reader`, `_onboard` | `io_model->create_data_reference( i_fieldname, i_struct, if_table, er_data )` and constant `if_usmd_model=>gc_struct_key_attr` | SE24 → `IF_USMD_MODEL_EXT` → Methods → `CREATE_DATA_REFERENCE` → Parameters; and SE24 → `IF_USMD_MODEL` → Attributes (constant name) |
| `zcl_mdmdoc_onboard` (discovery) | `cl_usmd_model_ext=>get_instance( i_usmd_model = … )` | SE24 → `CL_USMD_MODEL_EXT` → Methods (is `GET_INSTANCE` static? param name?) |
| `zcl_mdmdoc_onboard` (discovery) | `io_model->get_entities( IMPORTING et_entity = … )`, type `usmd_ts_entity` | SE24 → `IF_USMD_MODEL_EXT` → Methods; SE11 → `USMD_TS_ENTITY` |
| `zcl_mdmdoc_mdg_reader` | `lt_sel TYPE usmd_ts_sel` | SE11 → `USMD_TS_SEL` |
| `zcl_mdmdoc_mdg_check` | `usmd_s_message` / `usmd_t_message` field names (`msgid msgno msgty msgv1..4`) | SE11 → `USMD_S_MESSAGE` |
| `zcl_mdmdoc_mdg_check` | `bal_s_msg` field names; FM `BAL_LOG_MSG_ADD` | SE11 → `BAL_S_MSG`; SE37 → `BAL_LOG_MSG_ADD` |
| `zcl_mdmdoc_mdg_reader` (attachments) | `cl_gos_api=>create_instance( is_object )`, `get_atta_list( )`, `read_attachment( )` | SE24 → `CL_GOS_API` — **does it exist on this release?** If not, see C3. |

### C3. CR attachments — the biggest unknown

We must learn **how this system stores a change-request attachment**.

- Attach a file to a test CR, then **SE16N → `SRGBTBREL`** (GOS object relationships) and filter on
  the CR number in `INSTID_A` / `INSTID_B`. Capture `TYPEID_A` / `TYPEID_B` and `RELTYPE`.
  → that gives the real BOR/IBO object type of the CR (our template assumes `USMD_CREQ`).
- If nothing appears there, MDG may store attachments through its own service — then check
  SE24 for `CL_USMD_ATTACHMENT*` / `IF_USMD_CREQUEST*` and MDGIMG → Change Requests → attachments.
- Also confirm the authorization: the BAdI runs in the requester's session; can it read the GOS
  attachment of that CR?

### C4. Data model — entity and field names

Our mapping (`ZCL_MDMDOC_MDG_MAP` defaults: `BP_CENTRL / ADDRESS / BP_BANKDT / BP_IBAN / BP_TAXNUM`)
is a guess.

- Fastest path: install the package and run **`ZMDMDOC_MDG_DISCOVER`** (chapter 12) — it reads the
  live model and proposes the real `SAP_KEY → entity.field` map.
- Manual path: **MDGIMG** → General Settings → Data Modeling → Edit Data Model → model `BP` →
  Entity Types; and tx `USMD_ENTITY`.
- Also confirm the **filter value** for our model: is it literally `BP`? (MDG-S / MDG-C both sit on
  the BP data model.)

### C5. Runtime behaviour to confirm

| Question | How |
|---|---|
| Does an `E` message in `CHECK_CREQUEST_FINAL`'s BAL log **block** CR submit? | test CR; our default is `W` only, so this is not blocking us |
| Is `CHECK_CREQUEST_FINAL` also called for the interactive *Online Check*, or only on submit? | test; relates to `IF_ONLINE_CHECK` semantics on `CHECK_ENTITY` |
| Where does the operator actually see the log? | open a CR in Fiori/GUI after a check |
| Message class `ZMDMDOC` / `001` exists? | SE91 (create if not: `001` = `&1&2&3&4`) |

### C6. Platform baseline

| Question | How | Why |
|---|---|---|
| SAP_BASIS release + SP | System → Status | we target **7.50** (classic regex, no PCRE). If ≥ 7.55 we could simplify regex. |
| Does `CL_ABAP_GZIP=>DECOMPRESS_BINARY` accept **zlib** (RFC 1950) streams? | run `ZMDMDOC_DOCTOR`, or feed a compressed PDF | **our #1 risk** — PDF FlateDecode is zlib, not gzip. Three fallback strategies live in `ZCL_MDMDOC_PDF`. |
| `/UI2/CL_JSON` available? | SE24 | needed for the JSON export / rules override |

---

## D. How to update this file

When you verify something on the system:

1. Move the line from section C into section A, adding the **source** (transaction + screen) and the
   date.
2. If it contradicts a design decision, update section B **and** the affected class header comment
   (`*** VERIFY ON SYSTEM ***` blocks) and chapter 10 of `INTEGRATION.md` in the same commit.
3. If an assumption in C2 turns out wrong, the fix belongs in exactly one place — the MDG-specific
   classes are excluded from abaplint precisely because they cannot be checked offline.
