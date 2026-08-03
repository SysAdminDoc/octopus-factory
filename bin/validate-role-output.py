#!/usr/bin/env python3
"""Validate machine-readable role output against the local role contracts."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONTRACTS = ROOT / "config" / "roles"
ROLE_RE = re.compile(r"^[a-z][a-z0-9_-]*$")


class ContractError(ValueError):
    """A contract or output validation error."""


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContractError(f"could not read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ContractError(f"JSON object required: {path}")
    return value


def load_contracts(directory: Path) -> dict[str, tuple[Path, dict[str, Any]]]:
    if not directory.is_dir():
        raise ContractError(f"contracts directory not found: {directory}")
    contracts: dict[str, tuple[Path, dict[str, Any]]] = {}
    for path in sorted(directory.glob("*.json")):
        value = load_json(path)
        if "role" not in value:
            continue
        role = value.get("role")
        if not isinstance(role, str) or not ROLE_RE.fullmatch(role) or path.stem != role:
            raise ContractError(f"contract filename and role must match: {path.name}")
        if role in contracts:
            raise ContractError(f"duplicate role contract: {role}")
        contracts[role] = (path, value)
    if not contracts:
        raise ContractError(f"no role contracts found in {directory}")
    return contracts


def require_string_list(contract: dict[str, Any], field: str, role: str, errors: list[str]) -> None:
    values = contract.get(field)
    if not isinstance(values, list) or not values or not all(isinstance(item, str) and item for item in values):
        errors.append(f"contract {role}.{field} must be a non-empty string array")
    elif len(values) != len(set(values)):
        errors.append(f"contract {role}.{field} contains duplicates")


def validate_contract(path: Path, contract: dict[str, Any], roles: set[str]) -> list[str]:
    role = contract.get("role", path.stem)
    errors: list[str] = []
    if contract.get("schema_version") != 1:
        errors.append(f"contract {role}.schema_version must be 1")
    if contract.get("role") != path.stem or not isinstance(role, str) or not ROLE_RE.fullmatch(role):
        errors.append(f"contract role must match lowercase filename: {path.name}")
    if not isinstance(contract.get("description"), str) or not contract["description"]:
        errors.append(f"contract {role}.description is required")
    for field in ("allowed_tools", "required_inputs", "required_artifacts", "escalation_triggers", "no_go_zones"):
        require_string_list(contract, field, role, errors)
    output_schema = contract.get("output_schema")
    if not isinstance(output_schema, dict) or not isinstance(output_schema.get("$ref"), str):
        errors.append(f"contract {role}.output_schema must contain a local $ref")
    elif not (path.parent / output_schema["$ref"]).is_file():
        errors.append(f"contract {role}.output_schema ref is missing: {output_schema['$ref']}")
    handoff = contract.get("handoff")
    if not isinstance(handoff, dict):
        errors.append(f"contract {role}.handoff must be an object")
    else:
        next_roles = handoff.get("next_roles")
        if not isinstance(next_roles, list) or not next_roles or not all(isinstance(item, str) for item in next_roles):
            errors.append(f"contract {role}.handoff.next_roles must be a non-empty string array")
        else:
            unknown = sorted(set(next_roles) - roles - {"none"})
            if unknown:
                errors.append(f"contract {role}.handoff.next_roles references unknown roles: {', '.join(unknown)}")
        require_string_list(handoff, "preserve_fields", role + ".handoff", errors)
        if not isinstance(handoff.get("fallback_instruction"), str) or not handoff["fallback_instruction"]:
            errors.append(f"contract {role}.handoff.fallback_instruction is required")
    return errors


def load_yaml(path: Path) -> Any:
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError as exc:
        raise ContractError("YAML output requires PyYAML; use JSON or install PyYAML in the pinned container") from exc
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise ContractError(f"could not read YAML {path}: {exc}") from exc


def load_output(path: Path, output_format: str) -> Any:
    selected = output_format
    if selected == "auto":
        selected = "yaml" if path.suffix.lower() in {".yaml", ".yml"} else "json"
    if selected == "yaml":
        return load_yaml(path)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContractError(f"could not read JSON output {path}: {exc}") from exc


def resolve_schema(schema: dict[str, Any], base: Path) -> dict[str, Any]:
    reference = schema.get("$ref")
    if not reference:
        return schema
    target = (base / reference).resolve()
    if target.parent != base.resolve():
        raise ContractError(f"schema reference escapes the contract directory: {reference}")
    return load_json(target)


def validate_value(value: Any, schema: dict[str, Any], path: str, base: Path, errors: list[str]) -> None:
    schema = resolve_schema(schema, base)
    expected_type = schema.get("type")
    type_ok = {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
    }
    if expected_type in type_ok and not type_ok[expected_type]:
        errors.append(f"{path}: expected {expected_type}")
        return
    if "const" in schema and value != schema["const"]:
        errors.append(f"{path}: must equal {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: must be one of {schema['enum']!r}")
    if isinstance(value, str) and len(value) < schema.get("min_length", 0):
        errors.append(f"{path}: must not be empty")
    if isinstance(value, list) and len(value) < schema.get("min_items", 0):
        errors.append(f"{path}: needs at least {schema['min_items']} item(s)")
    if isinstance(value, dict):
        required = schema.get("required", [])
        for key in required:
            if key not in value:
                errors.append(f"{path}.{key}: required")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            for key in value:
                if key not in properties:
                    errors.append(f"{path}.{key}: unexpected field")
        for key, child_schema in properties.items():
            if key in value:
                validate_value(value[key], child_schema, f"{path}.{key}", base, errors)
    if isinstance(value, list) and isinstance(schema.get("items"), dict):
        for index, item in enumerate(value):
            validate_value(item, schema["items"], f"{path}[{index}]", base, errors)


def validate_output(role: str, output: Any, contract: dict[str, Any], contract_path: Path, contracts: dict[str, tuple[Path, dict[str, Any]]]) -> list[str]:
    errors: list[str] = []
    schema = contract["output_schema"]
    validate_value(output, schema, "$", contract_path.parent, errors)
    if not isinstance(output, dict):
        return errors
    if output.get("role") != role:
        errors.append(f"$.role: expected {role!r}")
    handoff = output.get("handoff")
    allowed_next = contract["handoff"]["next_roles"]
    if isinstance(handoff, dict):
        next_role = handoff.get("next_role")
        if next_role not in allowed_next:
            errors.append(f"$.handoff.next_role: {next_role!r} is not allowed for {role}: {allowed_next!r}")
        task = output.get("task")
        if isinstance(task, dict) and handoff.get("task_id") != task.get("id"):
            errors.append("$.handoff.task_id: must preserve $.task.id")
        if next_role == "none":
            if handoff.get("output_schema_ref") != "none":
                errors.append("$.handoff.output_schema_ref: must be 'none' for terminal handoff")
        elif isinstance(next_role, str) and next_role in contracts:
            expected_ref = f"config/roles/{next_role}.json"
            if handoff.get("output_schema_ref") != expected_ref:
                errors.append(f"$.handoff.output_schema_ref: expected {expected_ref!r}")
    if output.get("status") == "pass":
        if not output.get("artifacts"):
            errors.append("$.artifacts: at least one artifact is required for pass")
        if not output.get("tests"):
            errors.append("$.tests: at least one test/evidence entry is required for pass")
    return errors


def result_payload(status: str, role: str | None, errors: list[str], contract_path: Path | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {"status": status, "role": role, "errors": errors}
    if contract_path:
        result["contract"] = str(contract_path)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate JSON or YAML role output against config/roles/*.json.")
    parser.add_argument("role", nargs="?")
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--contracts-dir", type=Path, default=DEFAULT_CONTRACTS)
    parser.add_argument("--format", choices=("auto", "json", "yaml"), default="auto")
    parser.add_argument("--validate-contracts", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        contracts = load_contracts(args.contracts_dir.resolve())
        contract_errors: list[str] = []
        for path, contract in contracts.values():
            contract_errors.extend(validate_contract(path, contract, set(contracts)))
        if args.validate_contracts:
            payload = result_payload("pass" if not contract_errors else "fail", None, contract_errors)
            if args.json:
                print(json.dumps(payload, indent=2, sort_keys=True))
            else:
                print(f"role contracts: {'valid' if not contract_errors else 'invalid'} ({len(contracts)} roles)")
                for error in contract_errors:
                    print(f"- {error}")
            return 0 if not contract_errors else 1
        if not args.role or not args.output:
            raise ContractError("role and output are required unless --validate-contracts is used")
        if args.role not in contracts:
            raise ContractError(f"unknown role: {args.role}")
        if contract_errors:
            errors = contract_errors
        else:
            contract_path, contract = contracts[args.role]
            output = load_output(args.output.resolve(), args.format)
            errors = validate_output(args.role, output, contract, contract_path, contracts)
        contract_path = contracts[args.role][0]
        payload = result_payload("pass" if not errors else "fail", args.role, errors, contract_path)
        if args.json:
            print(json.dumps(payload, indent=2, sort_keys=True))
        else:
            print(f"role output {args.role}: {'valid' if not errors else 'invalid'}")
            for error in errors:
                print(f"- {error}")
        return 0 if not errors else 1
    except ContractError as exc:
        payload = result_payload("fail", args.role, [str(exc)])
        if args.json:
            print(json.dumps(payload, indent=2, sort_keys=True))
        else:
            print(f"validate-role-output: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
