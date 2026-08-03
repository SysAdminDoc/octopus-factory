#!/usr/bin/env python3
"""Validate and operate the durable factory phase graph.

The graph is deliberately data-driven.  This helper owns only graph validation
and a small atomic state journal; phase implementations remain in the existing
bash-first runtime and must reserve an operation with ``mark ... running``
before performing an external side effect.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GRAPH = ROOT / "config" / "workflows" / "factory.graph.json"
DEFAULT_STATE = Path.cwd() / ".factory" / "workflow-state.json"
GRAPH_SCHEMA_VERSION = 1
STATE_SCHEMA_VERSION = 1
STATUSES = {"pending", "running", "succeeded", "failed", "blocked", "interrupted", "skipped"}
OPERATION_ID_RE = re.compile(r"^[A-Za-z0-9_.:/-]+$")


class GraphError(ValueError):
    """A user-correctable graph or state contract error."""


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except FileNotFoundError as exc:
        raise GraphError(f"file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise GraphError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise GraphError(f"top-level JSON value must be an object: {path}")
    return value


def graph_nodes(graph: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw_nodes = graph.get("nodes")
    if not isinstance(raw_nodes, list) or not raw_nodes:
        raise GraphError("graph.nodes must be a non-empty array")

    nodes: dict[str, dict[str, Any]] = {}
    for index, raw_node in enumerate(raw_nodes):
        if not isinstance(raw_node, dict):
            raise GraphError(f"graph.nodes[{index}] must be an object")
        node_id = raw_node.get("id")
        if not isinstance(node_id, str) or not re.fullmatch(r"[a-z][a-z0-9_-]*", node_id):
            raise GraphError(f"graph.nodes[{index}].id must be a lowercase identifier")
        if node_id in nodes:
            raise GraphError(f"duplicate graph node id: {node_id}")
        nodes[node_id] = raw_node
    return nodes


def validate_graph(graph: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if graph.get("schema_version") != GRAPH_SCHEMA_VERSION:
        raise GraphError(f"schema_version must be {GRAPH_SCHEMA_VERSION}")
    if not isinstance(graph.get("graph_id"), str) or not graph["graph_id"]:
        raise GraphError("graph_id must be a non-empty string")
    entrypoints = graph.get("entrypoints")
    terminal_ids = graph.get("terminal_nodes")
    if not isinstance(entrypoints, list) or not entrypoints:
        raise GraphError("entrypoints must be a non-empty array")
    if not isinstance(terminal_ids, list) or not terminal_ids:
        raise GraphError("terminal_nodes must be a non-empty array")

    nodes = graph_nodes(graph)
    for label, values in (("entrypoints", entrypoints), ("terminal_nodes", terminal_ids)):
        for node_id in values:
            if node_id not in nodes:
                raise GraphError(f"{label} references unknown node: {node_id}")

    interrupt_ids: set[str] = set()
    for node_id, node in nodes.items():
        for field in ("description", "idempotency_key", "rollback_handler"):
            if field not in node:
                raise GraphError(f"node {node_id} is missing {field}")
        if not isinstance(node["description"], str) or not node["description"]:
            raise GraphError(f"node {node_id}.description must be non-empty")
        if not isinstance(node["idempotency_key"], str) or "{run_id}" not in node["idempotency_key"] or "{node_id}" not in node["idempotency_key"]:
            raise GraphError(f"node {node_id}.idempotency_key must include {{run_id}} and {{node_id}}")
        if node["rollback_handler"] is not None and not isinstance(node["rollback_handler"], str):
            raise GraphError(f"node {node_id}.rollback_handler must be a string or null")

        prerequisites = node.get("prerequisites")
        if not isinstance(prerequisites, list):
            raise GraphError(f"node {node_id}.prerequisites must be an array")
        for prerequisite in prerequisites:
            if prerequisite not in nodes:
                raise GraphError(f"node {node_id} has unknown prerequisite: {prerequisite}")

        retry = node.get("retry_policy")
        if not isinstance(retry, dict) or not isinstance(retry.get("max_attempts"), int) or retry["max_attempts"] < 1:
            raise GraphError(f"node {node_id}.retry_policy.max_attempts must be a positive integer")
        if not isinstance(retry.get("backoff_seconds"), int) or retry["backoff_seconds"] < 0:
            raise GraphError(f"node {node_id}.retry_policy.backoff_seconds must be a non-negative integer")
        exhausted = retry.get("on_exhausted")
        if exhausted not in nodes:
            raise GraphError(f"node {node_id}.retry_policy.on_exhausted references unknown node: {exhausted}")

        required_artifacts = node.get("required_artifacts")
        if not isinstance(required_artifacts, list) or not all(isinstance(item, str) and item for item in required_artifacts):
            raise GraphError(f"node {node_id}.required_artifacts must contain non-empty strings")

        side_effects = node.get("side_effects")
        if not isinstance(side_effects, list):
            raise GraphError(f"node {node_id}.side_effects must be an array")
        effect_ids: set[str] = set()
        for effect in side_effects:
            if not isinstance(effect, dict):
                raise GraphError(f"node {node_id}.side_effects entries must be objects")
            effect_id = effect.get("id")
            if not isinstance(effect_id, str) or not re.fullmatch(r"[a-z][a-z0-9_-]*", effect_id) or effect_id in effect_ids:
                raise GraphError(f"node {node_id} has an invalid or duplicate side-effect id")
            effect_ids.add(effect_id)
            if not isinstance(effect.get("description"), str) or not effect["description"]:
                raise GraphError(f"side effect {node_id}/{effect_id} needs a description")
            effect_key = effect.get("idempotency_key")
            if not isinstance(effect_key, str) or "{run_id}" not in effect_key or "{node_id}" not in effect_key:
                raise GraphError(f"side effect {node_id}/{effect_id} needs a run/node idempotency key")
            if not isinstance(effect.get("rollback_handler"), str) or not effect["rollback_handler"]:
                raise GraphError(f"side effect {node_id}/{effect_id} needs a rollback_handler")

        transitions = node.get("transitions")
        if not isinstance(transitions, dict):
            raise GraphError(f"node {node_id}.transitions must be an object")
        if node.get("terminal") is True:
            if transitions:
                raise GraphError(f"terminal node {node_id} cannot have transitions")
        else:
            for event in ("success", "failure"):
                target = transitions.get(event)
                if target not in nodes:
                    raise GraphError(f"node {node_id}.{event} transition references unknown node: {target}")

        interrupts = node.get("interrupts")
        if not isinstance(interrupts, list):
            raise GraphError(f"node {node_id}.interrupts must be an array")
        for interrupt in interrupts:
            if not isinstance(interrupt, dict):
                raise GraphError(f"node {node_id}.interrupts entries must be objects")
            interrupt_id = interrupt.get("id")
            if not isinstance(interrupt_id, str) or not re.fullmatch(r"[a-z][a-z0-9_-]*", interrupt_id) or interrupt_id in interrupt_ids:
                raise GraphError(f"node {node_id} has an invalid or duplicate interrupt id")
            interrupt_ids.add(interrupt_id)
            if not isinstance(interrupt.get("description"), str) or not interrupt["description"]:
                raise GraphError(f"interrupt {node_id}/{interrupt_id} needs a description")
            if interrupt.get("approval_required") is not True:
                raise GraphError(f"interrupt {node_id}/{interrupt_id} must require approval explicitly")
            if interrupt.get("resume_event") != "approved":
                raise GraphError(f"interrupt {node_id}/{interrupt_id} must resume on approved")

    for node_id in terminal_ids:
        if nodes[node_id].get("terminal") is not True:
            raise GraphError(f"terminal_nodes entry {node_id} must have terminal=true")

    # Check that every node can be reached from an entrypoint and that the
    # transition graph has no accidental cycle. Retry is state-local, not an
    # edge in the durable phase graph.
    adjacency = {
        node_id: [target for target in node.get("transitions", {}).values() if isinstance(target, str)]
        for node_id, node in nodes.items()
    }
    reachable: set[str] = set()
    stack = list(entrypoints)
    while stack:
        node_id = stack.pop()
        if node_id in reachable:
            continue
        reachable.add(node_id)
        stack.extend(adjacency[node_id])
    unreachable = sorted(set(nodes) - reachable)
    if unreachable:
        raise GraphError(f"unreachable graph nodes: {', '.join(unreachable)}")

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(node_id: str) -> None:
        if node_id in visiting:
            raise GraphError(f"cycle detected at graph node: {node_id}")
        if node_id in visited:
            return
        visiting.add(node_id)
        for target in adjacency[node_id]:
            visit(target)
        visiting.remove(node_id)
        visited.add(node_id)

    for node_id in nodes:
        visit(node_id)
    return nodes


def load_graph(path: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    graph = load_json(path)
    return graph, validate_graph(graph)


def write_json_atomic(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def initial_state(graph: dict[str, Any]) -> dict[str, Any]:
    run_id = os.environ.get("OCTOPUS_RUN_ID") or datetime.now(timezone.utc).strftime("graph-%Y%m%dT%H%M%SZ")
    entrypoint = graph["entrypoints"][0]
    return {
        "schema_version": STATE_SCHEMA_VERSION,
        "graph_id": graph["graph_id"],
        "run_id": run_id,
        "current_node": entrypoint,
        "nodes": {},
        "operations": {},
        "approvals": [],
        "interrupts": [],
        "history": [],
        "updated_at": utc_now(),
    }


def load_state(path: Path, graph: dict[str, Any], nodes: dict[str, dict[str, Any]]) -> dict[str, Any]:
    if not path.exists():
        state = initial_state(graph)
        write_json_atomic(path, state)
        return state
    state = load_json(path)
    if state.get("schema_version") != STATE_SCHEMA_VERSION:
        raise GraphError(f"state schema_version must be {STATE_SCHEMA_VERSION}: {path}")
    if state.get("graph_id") != graph["graph_id"]:
        raise GraphError(f"state graph_id does not match graph: {state.get('graph_id')}")
    if state.get("current_node") not in nodes:
        raise GraphError(f"state current_node is not in graph: {state.get('current_node')}")
    for field in ("nodes", "operations", "approvals", "interrupts", "history"):
        if field not in state or not isinstance(state[field], (dict if field in {"nodes", "operations"} else list)):
            raise GraphError(f"state field {field} has the wrong type")
    return state


def operation_id(value: str | None, state: dict[str, Any], node_id: str, attempt: int, side_effect: str | None) -> str:
    candidate = value or (f"{state['run_id']}:{node_id}:{side_effect}" if side_effect else f"{state['run_id']}:{node_id}:{attempt}")
    if not OPERATION_ID_RE.fullmatch(candidate):
        raise GraphError("operation id may contain only letters, numbers, '.', ':', '/', '_' or '-'")
    return candidate


def emit(value: dict[str, Any], as_json: bool, lines: list[str]) -> None:
    if as_json:
        print(json.dumps(value, indent=2, sort_keys=True))
    else:
        for line in lines:
            print(line)


def cmd_validate(args: argparse.Namespace) -> int:
    graph, nodes = load_graph(args.graph)
    emit(
        {"status": "valid", "graph_id": graph["graph_id"], "schema_version": graph["schema_version"], "nodes": len(nodes)},
        args.json,
        [f"factory graph valid: {graph['graph_id']} schema v{graph['schema_version']} ({len(nodes)} nodes)"],
    )
    return 0


def next_result(state: dict[str, Any], node: dict[str, Any], node_id: str, requested_event: str | None) -> tuple[dict[str, Any], int]:
    node_state = state["nodes"].get(node_id, {})
    status = node_state.get("status", "pending")
    attempts = int(node_state.get("attempts", 0))
    event = requested_event
    reason = ""

    if event is None:
        if status in {"pending", "running", "interrupted"}:
            result = {"from": node_id, "status": status, "event": None, "next": node_id, "reason": "current node is not complete"}
            return result, 0
        if status in {"succeeded", "skipped"}:
            event = "success"
        elif status == "failed":
            if attempts < node["retry_policy"]["max_attempts"]:
                event = "retry"
            else:
                event = "failure"
        elif status == "blocked":
            result = {"from": node_id, "status": status, "event": None, "next": node_id, "reason": "workflow is blocked"}
            return result, 0

    if event == "retry":
        if attempts >= node["retry_policy"]["max_attempts"]:
            event = "failure"
        else:
            result = {"from": node_id, "status": status, "event": "retry", "next": node_id, "reason": "retry budget remains"}
            return result, 0

    target = node.get("transitions", {}).get(event)
    if target is None:
        raise GraphError(f"node {node_id} has no transition for event {event}")
    result = {"from": node_id, "status": status, "event": event, "next": target, "reason": reason}
    return result, 0


def cmd_next(args: argparse.Namespace) -> int:
    graph, nodes = load_graph(args.graph)
    state = load_state(args.state, graph, nodes)
    node_id = args.from_node or state["current_node"]
    if node_id not in nodes:
        raise GraphError(f"unknown current node: {node_id}")
    result, code = next_result(state, nodes[node_id], node_id, args.event)
    emit(
        result,
        args.json,
        [
            f"current: {result['from']} ({result['status']})",
            f"event: {result['event'] or 'pending'}",
            f"next: {result['next']}",
            *([f"reason: {result['reason']}"] if result.get("reason") else []),
        ],
    )
    return code


def record_approval(state: dict[str, Any], node_id: str, interrupt_id: str) -> None:
    if any(item.get("node_id") == node_id and item.get("interrupt_id") == interrupt_id for item in state["approvals"]):
        return
    state["approvals"].append(
        {"node_id": node_id, "interrupt_id": interrupt_id, "actor": os.environ.get("OCTOPUS_ACTOR", "operator"), "approved_at": utc_now()}
    )


def required_interrupts(state: dict[str, Any], node: dict[str, Any]) -> list[str]:
    approved = {item.get("interrupt_id") for item in state["approvals"]}
    return [interrupt["id"] for interrupt in node["interrupts"] if interrupt["approval_required"] and interrupt["id"] not in approved]


def cmd_mark(args: argparse.Namespace) -> int:
    graph, nodes = load_graph(args.graph)
    if args.node not in nodes:
        raise GraphError(f"unknown graph node: {args.node}")
    state = load_state(args.state, graph, nodes)
    node = nodes[args.node]
    entry = state["nodes"].setdefault(args.node, {"status": "pending", "attempts": 0, "artifacts": []})
    previous_status = entry.get("status", "pending")
    status = args.status

    for interrupt_id in args.approve:
        if not any(item["id"] == interrupt_id for item in node["interrupts"]):
            raise GraphError(f"unknown approval interrupt for {args.node}: {interrupt_id}")
        record_approval(state, args.node, interrupt_id)

    if status == "running":
        missing = required_interrupts(state, node)
        if missing:
            state["interrupts"] = state.get("interrupts", [])
            for interrupt_id in missing:
                if not any(item.get("node_id") == args.node and item.get("interrupt_id") == interrupt_id for item in state["interrupts"]):
                    state["interrupts"].append({"node_id": args.node, "interrupt_id": interrupt_id, "status": "pending", "requested_at": utc_now()})
            state["updated_at"] = utc_now()
            write_json_atomic(args.state, state)
            result = {"status": "approval_required", "node": args.node, "interrupts": missing}
            emit(result, args.json, [f"approval required before {args.node}: {', '.join(missing)}"])
            return 3

    current_attempt = int(entry.get("attempts", 0))
    attempt = current_attempt + 1 if status == "running" and previous_status != "running" else max(current_attempt, 1)
    side_effect_ids = {effect["id"] for effect in node["side_effects"]}
    if args.side_effect and args.side_effect not in side_effect_ids:
        raise GraphError(f"unknown side effect for {args.node}: {args.side_effect}")
    op_id = operation_id(args.operation_id or (entry.get("operation_id") if not args.side_effect else None), state, args.node, attempt, args.side_effect)
    existing_operation = state["operations"].get(op_id)
    if existing_operation and existing_operation.get("node_id") != args.node:
        raise GraphError(f"operation id already belongs to node {existing_operation.get('node_id')}: {op_id}")
    if existing_operation and existing_operation.get("side_effect") != args.side_effect:
        raise GraphError(f"operation id already belongs to a different side effect: {op_id}")
    if existing_operation and existing_operation.get("status") == status:
        result = {"status": "idempotent", "node": args.node, "operation_id": op_id, "state": previous_status}
        emit(result, args.json, [f"idempotent: {args.node} already {status} ({op_id})"])
        return 0
    if existing_operation and existing_operation.get("status") in {"succeeded", "failed", "blocked", "skipped"} and status != existing_operation["status"]:
        raise GraphError(f"operation {op_id} is already {existing_operation['status']}; use a new operation id for a new attempt")

    if status == "running":
        entry["attempts"] = attempt
    entry.update({"status": status, "operation_id": op_id, "updated_at": utc_now()})
    if args.artifact:
        entry["artifacts"] = sorted(set(entry.get("artifacts", [])) | set(args.artifact))
    if args.note:
        entry["note"] = args.note
    state["operations"][op_id] = {
        "node_id": args.node,
        "side_effect": args.side_effect,
        "status": status,
        "attempt": entry.get("attempts", attempt),
        "reserved_at": state["operations"].get(op_id, {}).get("reserved_at", utc_now()),
        "updated_at": utc_now(),
    }
    state["current_node"] = args.node
    state["history"].append({"node_id": args.node, "status": status, "operation_id": op_id, "at": utc_now()})
    state["updated_at"] = utc_now()
    write_json_atomic(args.state, state)
    result = {"status": status, "node": args.node, "operation_id": op_id, "attempt": entry.get("attempts", attempt), "state_file": str(args.state)}
    emit(result, args.json, [f"marked {args.node} {status} ({op_id})", f"state: {args.state}"])
    return 0


def cmd_explain(args: argparse.Namespace) -> int:
    graph, nodes = load_graph(args.graph)
    if args.node not in nodes:
        raise GraphError(f"unknown graph node: {args.node}")
    node = nodes[args.node]
    if args.json:
        print(json.dumps(node, indent=2, sort_keys=True))
        return 0
    print(f"{node['id']}: {node['description']}")
    print(f"prerequisites: {', '.join(node['prerequisites']) or 'none'}")
    print(f"retry: up to {node['retry_policy']['max_attempts']} attempt(s), {node['retry_policy']['backoff_seconds']}s backoff")
    print(f"idempotency key: {node['idempotency_key']}")
    print(f"side effects: {len(node['side_effects'])}")
    for effect in node["side_effects"]:
        print(f"  - {effect['id']}: {effect['description']} [{effect['idempotency_key']}] rollback={effect['rollback_handler']}")
    if node["interrupts"]:
        print("approval interrupts:")
        for interrupt in node["interrupts"]:
            print(f"  - {interrupt['id']}: {interrupt['description']}")
    print(f"required artifacts: {', '.join(node['required_artifacts']) or 'none'}")
    if node.get("terminal"):
        print("terminal: yes")
    else:
        print(f"on success: {node['transitions']['success']}; on failure: {node['transitions']['failure']}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate and operate the octopus-factory phase graph.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate", help="validate the graph contract")
    validate.add_argument("graph", nargs="?", type=Path, default=DEFAULT_GRAPH)
    validate.add_argument("--json", action="store_true")
    validate.set_defaults(handler=cmd_validate)

    next_parser = subparsers.add_parser("next", help="show the next node for a state journal")
    next_parser.add_argument("state", nargs="?", type=Path, default=DEFAULT_STATE)
    next_parser.add_argument("--graph", type=Path, default=DEFAULT_GRAPH)
    next_parser.add_argument("--from", dest="from_node")
    next_parser.add_argument("--event", choices=("success", "failure", "retry"))
    next_parser.add_argument("--json", action="store_true")
    next_parser.set_defaults(handler=cmd_next)

    mark = subparsers.add_parser("mark", help="reserve or complete a node operation")
    mark.add_argument("state", type=Path)
    mark.add_argument("node")
    mark.add_argument("status", choices=sorted(STATUSES))
    mark.add_argument("--graph", type=Path, default=DEFAULT_GRAPH)
    mark.add_argument("--operation-id")
    mark.add_argument("--side-effect")
    mark.add_argument("--artifact", action="append", default=[])
    mark.add_argument("--note")
    mark.add_argument("--approve", action="append", default=[])
    mark.add_argument("--json", action="store_true")
    mark.set_defaults(handler=cmd_mark)

    explain = subparsers.add_parser("explain", help="show a node contract")
    explain.add_argument("node")
    explain.add_argument("--graph", type=Path, default=DEFAULT_GRAPH)
    explain.add_argument("--json", action="store_true")
    explain.set_defaults(handler=cmd_explain)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except GraphError as exc:
        print(f"factory-graph: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"factory-graph: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
