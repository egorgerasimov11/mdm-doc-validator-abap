#!/usr/bin/env python3
"""Generate ZCL_MDMDOC_RULES_DATA (ABAP) + rules/rules.json from the YAML rule files.

Input : rules/banking.yaml, rules/w9.yaml  (copies of the Python mdm-doc-validator rules)
Output: src/zcl_mdmdoc_rules_data.clas.abap (+ .clas.xml if missing)
        rules/rules.json                    (runtime-override template for p_rules)

Deterministic: same input -> byte-identical output (no timestamps).
Fails loudly on: unknown when-operator, unknown severity/verdict_effect,
regex constructs that classic ABAP (7.50) regex cannot run.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[1]
RULES_DIR = REPO / "rules"
SRC_DIR = REPO / "src"

SEVERITIES = {"CRITICAL", "WARNING", "NOTE"}
EFFECTS = {"REJECT", "NEED_MANUAL_REVIEW", "WARNING", "ACCEPT", None}
WHEN_OPS = {"always", "field_missing", "flag_true", "flag_false",
            "equals", "in", "regex_mismatch", "check"}

# Constructs classic ABAP regex (pre-PCRE, 7.50) cannot express as-is.
FORBIDDEN_REGEX = [
    (r"\(\?i\)", "(?i) inline flag — use IGNORING CASE in ABAP instead"),
    (r"\(\?s\)", "(?s) dotall — restructure the buffer instead"),
    (r"\(\?m\)", "(?m) multiline — use a line table instead"),
    (r"\(\?P<", "(?P<name>) named group"),
    (r"\(\?<", "lookbehind"),
    (r"\(\?=", "lookahead"),
    (r"\(\?!", "negative lookahead"),
    (r"\\b", r"\b word boundary — use \< / \> in ABAP"),
]

CHUNK = 90  # max chars per emitted string-literal chunk


def die(msg: str) -> None:
    print(f"gen_rules_abap: ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def check_regex_portable(rule_id: str, pattern: str) -> None:
    for pat, why in FORBIDDEN_REGEX:
        if re.search(pat, pattern):
            die(f"rule {rule_id}: regex pattern {pattern!r} not portable to ABAP: {why}")


def abap_str(value: str) -> str:
    """Emit a (possibly concatenated) ABAP back-quoted string literal."""
    value = value or ""
    value = value.replace("`", "``")
    if not value:
        return "``"
    chunks = [value[i:i + CHUNK] for i in range(0, len(value), CHUNK)]
    return " &&\n        ".join(f"`{c}`" for c in chunks)


def string_table(values: list[str], indent: str) -> str:
    if not values:
        return "VALUE #( )"
    rows = f"\n{indent}  ".join(f"( {abap_str(v)} )" for v in values)
    return f"VALUE #(\n{indent}  {rows} )"


def flatten_arg(value) -> str:
    if isinstance(value, list):
        return ",".join(str(v) for v in value)
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def parse_when(rule_id: str, when: dict) -> dict:
    """Normalize the YAML `when` into flat ty_rule columns."""
    out = {"when_op": "", "when_field": "", "when_value": "",
           "when_values": [], "check_name": "", "check_args": []}
    if not isinstance(when, dict) or len(when) == 0:
        die(f"rule {rule_id}: empty/invalid when clause")

    if "always" in when:
        out["when_op"] = "always"
    elif "field_missing" in when:
        out["when_op"] = "field_missing"
        out["when_field"] = str(when["field_missing"])
    elif "flag_true" in when:
        out["when_op"] = "flag_true"
        out["when_field"] = str(when["flag_true"])
    elif "flag_false" in when:
        out["when_op"] = "flag_false"
        out["when_field"] = str(when["flag_false"])
    elif "equals" in when:
        out["when_op"] = "equals"
        out["when_field"] = str(when["equals"]["field"])
        out["when_value"] = str(when["equals"]["value"])
    elif "in" in when:
        out["when_op"] = "in"
        out["when_field"] = str(when["in"]["field"])
        out["when_values"] = [str(v) for v in when["in"]["values"]]
    elif "regex_mismatch" in when:
        out["when_op"] = "regex_mismatch"
        out["when_field"] = str(when["regex_mismatch"]["field"])
        pattern = str(when["regex_mismatch"]["pattern"])
        check_regex_portable(rule_id, pattern)
        out["when_value"] = pattern
    elif "check" in when:
        out["when_op"] = "check"
        out["check_name"] = str(when["check"])
        out["when_field"] = str(when.get("field", ""))
        args = when.get("args", {}) or {}
        out["check_args"] = [{"name": str(k), "value": flatten_arg(v)}
                             for k, v in args.items()]
    else:
        die(f"rule {rule_id}: unknown when operator in {when!r}")
    return out


def load_rules(path: Path) -> tuple[list[dict], list[str], dict]:
    doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    rules = []
    for raw in doc.get("rules", []):
        rid = str(raw.get("id", "?"))
        sev = raw.get("severity")
        if sev not in SEVERITIES:
            die(f"rule {rid}: unknown severity {sev!r}")
        effect = raw.get("verdict_effect")
        if effect not in EFFECTS:
            die(f"rule {rid}: unknown verdict_effect {effect!r}")
        rule = {
            "id": rid,
            "name": str(raw.get("name", "")),
            "applies_to": [str(a) for a in (raw.get("applies_to") or [])],
            "severity": sev,
            "verdict_effect": effect or "",
            "message": str(raw.get("message", "")),
            "message_ru": str(raw.get("message_ru", "") or ""),
        }
        rule.update(parse_when(rid, raw.get("when")))
        rules.append(rule)
    doc_types = [str(t) for t in doc.get("doc_types", [])]
    tables = doc.get("tables", {}) or {}
    return rules, doc_types, tables


def emit_rule(rule: dict, target: str) -> str:
    lines = [f"    APPEND VALUE #("]
    lines.append(f"        id = {abap_str(rule['id'])}")
    lines.append(f"        name = {abap_str(rule['name'])}")
    if rule["applies_to"]:
        lines.append(f"        applies_to = {string_table(rule['applies_to'], '        ')}")
    lines.append(f"        when_op = {abap_str(rule['when_op'])}")
    if rule["when_field"]:
        lines.append(f"        when_field = {abap_str(rule['when_field'])}")
    if rule["when_value"]:
        lines.append(f"        when_value = {abap_str(rule['when_value'])}")
    if rule["when_values"]:
        lines.append(f"        when_values = {string_table(rule['when_values'], '        ')}")
    if rule["check_name"]:
        lines.append(f"        check_name = {abap_str(rule['check_name'])}")
    if rule["check_args"]:
        rows = "\n          ".join(
            f"( name = {abap_str(a['name'])} value = {abap_str(a['value'])} )"
            for a in rule["check_args"])
        lines.append(f"        check_args = VALUE #(\n          {rows} )")
    lines.append(f"        severity = {abap_str(rule['severity'])}")
    if rule["verdict_effect"]:
        lines.append(f"        verdict_effect = {abap_str(rule['verdict_effect'])}")
    lines.append(f"        message = {abap_str(rule['message'])}")
    if rule["message_ru"]:
        lines.append(f"        message_ru = {abap_str(rule['message_ru'])}")
    lines.append(f"      ) TO {target}.")
    return "\n".join(lines)


def emit_class(bank: list[dict], w9: list[dict],
               bank_types: list[str], w9_types: list[str],
               iban_len: dict) -> str:
    parts = []
    parts.append("""\
" GENERATED from rules/banking.yaml + rules/w9.yaml by tools/gen_rules_abap.py
" *** DO NOT EDIT BY HAND — edit the YAML and re-run the generator ***
CLASS zcl_mdmdoc_rules_data DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-DATA gt_rules_bank TYPE zif_mdmdoc_types=>tt_rules READ-ONLY.
    CLASS-DATA gt_rules_w9 TYPE zif_mdmdoc_types=>tt_rules READ-ONLY.
    CLASS-DATA gt_iban_len TYPE zif_mdmdoc_types=>tt_iban_len READ-ONLY.
    CLASS-DATA gt_doc_types_bank TYPE string_table READ-ONLY.
    CLASS-DATA gt_doc_types_w9 TYPE string_table READ-ONLY.
    CLASS-METHODS class_constructor.
  PRIVATE SECTION.
    CLASS-METHODS build_bank.
    CLASS-METHODS build_w9.
    CLASS-METHODS build_tables.
ENDCLASS.


CLASS zcl_mdmdoc_rules_data IMPLEMENTATION.

  METHOD class_constructor.
    build_bank( ).
    build_w9( ).
    build_tables( ).
  ENDMETHOD.

  METHOD build_bank.""")
    for rule in bank:
        parts.append(emit_rule(rule, "gt_rules_bank"))
    parts.append("  ENDMETHOD.\n\n  METHOD build_w9.")
    for rule in w9:
        parts.append(emit_rule(rule, "gt_rules_w9"))
    parts.append("  ENDMETHOD.\n\n  METHOD build_tables.")
    bank_types_rows = "\n      ".join(f"( {abap_str(t)} )" for t in bank_types)
    w9_types_rows = "\n      ".join(f"( {abap_str(t)} )" for t in w9_types)
    parts.append(f"    gt_doc_types_bank = VALUE #(\n      {bank_types_rows} ).")
    parts.append(f"    gt_doc_types_w9 = VALUE #(\n      {w9_types_rows} ).")
    parts.append("    gt_iban_len = VALUE #(")
    for country in sorted(iban_len):
        parts.append(f"      ( country = '{country}' len = {int(iban_len[country])} )")
    parts.append("    ).")
    parts.append("  ENDMETHOD.\n\nENDCLASS.")
    return "\n".join(parts) + "\n"


CLAS_XML = """\
<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0" serializer="LCL_OBJECT_CLAS" serializer_version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
   <VSEOCLASS>
    <CLSNAME>ZCL_MDMDOC_RULES_DATA</CLSNAME>
    <LANGU>E</LANGU>
    <DESCRIPT>mdmdoc: GENERATED rule tables (do not edit)</DESCRIPT>
    <STATE>1</STATE>
    <CLSCCINCL>X</CLSCCINCL>
    <FIXPT>X</FIXPT>
    <UNICODE>X</UNICODE>
   </VSEOCLASS>
  </asx:values>
 </asx:abap>
</abapGit>
"""


def main() -> None:
    bank, bank_types, bank_tables = load_rules(RULES_DIR / "banking.yaml")
    w9, w9_types, _ = load_rules(RULES_DIR / "w9.yaml")
    iban_len = bank_tables.get("iban_length", {})
    if not iban_len:
        die("banking.yaml: tables.iban_length missing/empty")
    # YAML 1.1 pitfall: unquoted NO would have parsed as boolean False
    for key in iban_len:
        if not (isinstance(key, str) and re.fullmatch(r"[A-Z]{2}", key)):
            die(f"iban_length: bad country key {key!r} (check YAML quoting, e.g. \"NO\")")

    abap = emit_class(bank, w9, bank_types, w9_types, iban_len)
    (SRC_DIR / "zcl_mdmdoc_rules_data.clas.abap").write_text(abap, encoding="utf-8")
    xml_path = SRC_DIR / "zcl_mdmdoc_rules_data.clas.xml"
    xml_path.write_text(CLAS_XML, encoding="utf-8")

    bank_rules = [dict(r) for r in bank]
    w9_rules = [dict(r) for r in w9]
    iban_rows = [{"country": c, "len": int(iban_len[c])} for c in sorted(iban_len)]

    def dump(path, obj):
        path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # combined override (both classes) — the default rules.json
    dump(RULES_DIR / "rules.json", {
        "schema": "zmdmdoc.rules.v1",
        "rules_bank": bank_rules,
        "rules_w9": w9_rules,
        "iban_length": iban_rows,
    })
    # per-class "skill" packs — swap one without touching the other (partial override)
    dump(RULES_DIR / "banking.rules.json", {
        "schema": "zmdmdoc.rules.v1",
        "rules_bank": bank_rules,
        "iban_length": iban_rows,
    })
    dump(RULES_DIR / "w9.rules.json", {
        "schema": "zmdmdoc.rules.v1",
        "rules_w9": w9_rules,
    })

    print(f"OK: {len(bank)} bank rules, {len(w9)} w9 rules, {len(iban_len)} iban lengths "
          f"-> zcl_mdmdoc_rules_data.clas.abap + rules/{{rules,banking.rules,w9.rules}}.json")


if __name__ == "__main__":
    main()
