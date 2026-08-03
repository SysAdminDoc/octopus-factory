#!/usr/bin/env python3
"""Small stdio MCP server exposing the factory's explicitly allowlisted files."""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_POLICY = ROOT / "config" / "mcp-policy.json"
SERVER_VERSION = "1"
JSONRPC_VERSION = "2.0"
READ_ONLY_OPERATION_VALUES = {"read", "read-only-tools"}
REQUIRED_FORBIDDEN_OPERATIONS = {"write", "edit", "delete", "execute", "shell", "git", "network"}


class ServerError(Exception):
    """A startup or policy error that should stop the server."""


class RequestError(Exception):
    """An MCP request error with a JSON-RPC error code."""

    def __init__(self, code: int, message: str, data: Any = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.data = data


@dataclass(frozen=True)
class Resource:
    uri: str
    root_id: str
    path: Path
    name: str
    description: str
    mime_type: str
    size: int


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ServerError(f"could not read policy {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ServerError("MCP policy must be a JSON object")
    return value


def ensure_within(path: Path, parent: Path) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(parent.resolve())
    except ValueError as exc:
        raise ServerError(f"policy path escapes repository: {path}") from exc
    return resolved


def mime_type(path: Path) -> str:
    if path.suffix.lower() == ".md":
        return "text/markdown"
    guessed, _ = mimetypes.guess_type(path.name)
    return guessed or "text/plain"


def resource_uri(root_id: str, relative: Path) -> str:
    return f"octopus-factory://{root_id}/{relative.as_posix()}"


def discover_resources(policy: dict[str, Any]) -> list[Resource]:
    roots = policy.get("allowed_roots")
    if not isinstance(roots, list) or not roots:
        raise ServerError("MCP policy must define allowed_roots")
    max_count = int(policy.get("max_resource_count", 512))
    if max_count < 1:
        raise ServerError("MCP policy max_resource_count must be positive")

    resources: list[Resource] = []
    repo_root = ROOT.resolve()
    for raw_root in roots:
        if not isinstance(raw_root, dict):
            raise ServerError("every MCP allowed root must be an object")
        root_id = raw_root.get("id")
        relative_root = raw_root.get("path")
        extensions = raw_root.get("extensions")
        if not isinstance(root_id, str) or not root_id or not isinstance(relative_root, str):
            raise ServerError("MCP allowed roots require string id and path")
        if Path(relative_root).is_absolute() or ".." in Path(relative_root).parts:
            raise ServerError(f"MCP allowed root is not repository-relative: {relative_root}")
        if not isinstance(extensions, list) or not all(isinstance(item, str) for item in extensions):
            raise ServerError(f"MCP root {root_id} requires extension allowlist")
        max_bytes = int(raw_root.get("max_bytes", 262144))
        if max_bytes < 1:
            raise ServerError(f"MCP root {root_id} max_bytes must be positive")

        configured = ROOT / relative_root
        if not configured.exists():
            raise ServerError(f"MCP allowed root is missing: {relative_root}")
        if configured.is_symlink():
            raise ServerError(f"MCP allowed root may not be a symlink: {relative_root}")
        resolved_root = ensure_within(configured, repo_root)
        if resolved_root.is_file():
            candidates = [resolved_root]
            base = resolved_root.parent
        elif resolved_root.is_dir():
            candidates = sorted(item for item in resolved_root.rglob("*") if item.is_file())
            base = resolved_root
        else:
            raise ServerError(f"MCP allowed root is not a regular file or directory: {relative_root}")

        allowed_extensions = {extension.lower() for extension in extensions}
        for candidate in candidates:
            if candidate.is_symlink():
                continue
            resolved = ensure_within(candidate, repo_root)
            if not resolved.is_file() or resolved.suffix.lower() not in allowed_extensions:
                continue
            size = resolved.stat().st_size
            if size > max_bytes:
                raise ServerError(f"MCP resource exceeds size cap: {resolved}")
            relative = resolved.relative_to(base)
            resources.append(
                Resource(
                    uri=resource_uri(root_id, relative),
                    root_id=root_id,
                    path=resolved,
                    name=relative.as_posix(),
                    description=f"{raw_root.get('description', root_id)}: {relative.as_posix()}",
                    mime_type=mime_type(resolved),
                    size=size,
                )
            )
            if len(resources) > max_count:
                raise ServerError("MCP resource count exceeds policy cap")
    if not resources:
        raise ServerError("MCP policy discovered no resources")
    return sorted(resources, key=lambda item: item.uri)


def safe_json_id(value: Any) -> Any:
    return value if isinstance(value, (str, int, float)) or value is None else None


class MCPServer:
    def __init__(self, policy_path: Path) -> None:
        self.policy = load_json(policy_path)
        if self.policy.get("schema_version") != 1:
            raise ServerError("unsupported MCP policy schema_version")
        if self.policy.get("server") != "octopus-factory-mcp":
            raise ServerError("MCP policy server name mismatch")
        if self.policy.get("read_only") is not True:
            raise ServerError("MCP server refuses a policy that is not read-only")
        versions = self.policy.get("protocol_versions")
        if not isinstance(versions, list) or not versions or not all(isinstance(item, str) for item in versions):
            raise ServerError("MCP policy requires protocol_versions")
        self.protocol_versions = tuple(versions)
        operations = self.policy.get("operations")
        if not isinstance(operations, dict) or any(value not in READ_ONLY_OPERATION_VALUES for value in operations.values()):
            raise ServerError("MCP policy contains a write-capable operation")
        forbidden = self.policy.get("forbidden_operations")
        if not isinstance(forbidden, list) or not REQUIRED_FORBIDDEN_OPERATIONS.issubset(set(forbidden)):
            raise ServerError("MCP policy must forbid write, execute, network, and git operations")
        self.resources = discover_resources(self.policy)
        self.by_uri = {item.uri: item for item in self.resources}
        self.prompts = {
            item.name: item for item in self.resources if item.root_id == "prompts"
        }
        self.initialized = False
        self.protocol_version = self.protocol_versions[0]
        self.stop_requested = False
        self.trajectory_ready = False
        self.trajectory_run_id = os.environ.get(
            "OCTOPUS_RUN_ID", f"mcp-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}-{os.getpid()}"
        )
        if not all(character.isalnum() or character in "._-" for character in self.trajectory_run_id):
            self.trajectory_run_id = f"mcp-{os.getpid()}"

    def resource_summary(self, item: Resource) -> dict[str, Any]:
        return {
            "uri": item.uri,
            "name": item.name,
            "description": item.description,
            "mimeType": item.mime_type,
            "size": item.size,
        }

    def read_resource(self, uri: str) -> tuple[Resource, str]:
        if not isinstance(uri, str) or uri not in self.by_uri:
            raise RequestError(-32602, "resource URI is not allowlisted")
        item = self.by_uri[uri]
        try:
            resolved = ensure_within(item.path, ROOT.resolve())
            if resolved != item.path or not resolved.is_file() or resolved.stat().st_size > item.size:
                raise RequestError(-32602, "resource is no longer within the allowlist")
            content = resolved.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise RequestError(-32603, f"resource could not be read: {exc}") from exc
        return item, content

    def record_call(self, method: str, request_id: Any, allowed: bool, uri: str = "") -> None:
        if os.environ.get("OCTOPUS_TRAJECTORY_DISABLED", "").lower() in {"1", "true", "yes"}:
            return
        bash = shutil.which("bash")
        if not bash:
            raise RequestError(-32603, "trajectory logging requires bash")
        trajectory = ROOT / "bin" / "factory-trajectory.sh"
        if not trajectory.is_file():
            raise RequestError(-32603, "trajectory logger is unavailable")
        env = os.environ.copy()
        env.update(
            {
                "OCTOPUS_TRAJECTORY_REPO": str(ROOT),
                "OCTOPUS_TRAJECTORY_SOURCE": "mcp",
                "OCTOPUS_RUN_ID": self.trajectory_run_id,
            }
        )
        if not self.trajectory_ready:
            initialized = subprocess.run(
                [bash, str(trajectory), "init"],
                cwd=str(ROOT),
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            if initialized.returncode != 0:
                raise RequestError(-32603, "trajectory initialization failed")
            self.trajectory_ready = True
        payload = json.dumps(
            {
                "mcp_method": method,
                "request_id": safe_json_id(request_id),
                "allowed": allowed,
                "read_only": True,
                "resource_uri": uri or None,
            },
            separators=(",", ":"),
        )
        env["OCTOPUS_TRAJECTORY_PAYLOAD"] = payload
        emitted = subprocess.run(
            [bash, str(trajectory), "emit", "tool_command", "--actor", "mcp", "--payload-env", "OCTOPUS_TRAJECTORY_PAYLOAD"],
            cwd=str(ROOT),
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        if emitted.returncode != 0:
            raise RequestError(-32603, "trajectory event could not be recorded")

    def initialize(self, params: dict[str, Any]) -> dict[str, Any]:
        requested = params.get("protocolVersion")
        if not isinstance(requested, str) or not requested:
            raise RequestError(-32602, "initialize requires protocolVersion")
        if requested not in self.protocol_versions:
            raise RequestError(-32602, f"unsupported protocol version: {requested}")
        self.protocol_version = requested
        self.initialized = True
        return {
            "protocolVersion": self.protocol_version,
            "capabilities": {
                "resources": {"listChanged": False},
                "prompts": {"listChanged": False},
                "tools": {"listChanged": False},
            },
            "serverInfo": {"name": "octopus-factory-mcp", "version": SERVER_VERSION},
            "instructions": "Read-only factory resources. No write, execute, network, or git tools are exposed.",
        }

    def tools(self) -> list[dict[str, Any]]:
        read_only_annotations = {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": False,
        }
        return [
            {
                "name": "factory.list_resources",
                "description": "List the factory resources allowed by config/mcp-policy.json.",
                "inputSchema": {"type": "object", "additionalProperties": False},
                "annotations": read_only_annotations,
            },
            {
                "name": "factory.read_resource",
                "description": "Read one allowlisted factory resource by its octopus-factory URI.",
                "inputSchema": {
                    "type": "object",
                    "properties": {"uri": {"type": "string"}},
                    "required": ["uri"],
                    "additionalProperties": False,
                },
                "annotations": read_only_annotations,
            },
        ]

    def dispatch(self, method: str, params: Any, request_id: Any) -> Any:
        if method == "initialize":
            if not isinstance(params, dict):
                raise RequestError(-32602, "initialize params must be an object")
            return self.initialize(params)
        if method == "ping":
            return {}
        if method == "notifications/initialized":
            self.initialized = True
            return None
        if method == "notifications/cancelled":
            return None
        if method == "shutdown":
            if not self.initialized:
                raise RequestError(-32002, "server is not initialized")
            self.stop_requested = True
            return None
        if not self.initialized:
            raise RequestError(-32002, "server is not initialized")
        if method == "resources/list":
            self.record_call(method, request_id, True)
            return {"resources": [self.resource_summary(item) for item in self.resources]}
        if method == "resources/read":
            if not isinstance(params, dict):
                raise RequestError(-32602, "resources/read params must be an object")
            uri = params.get("uri", "")
            try:
                item, content = self.read_resource(uri)
                self.record_call(method, request_id, True, uri)
            except RequestError:
                self.record_call(method, request_id, False, uri if isinstance(uri, str) else "")
                raise
            return {"contents": [{"uri": item.uri, "mimeType": item.mime_type, "text": content}]}
        if method == "prompts/list":
            self.record_call(method, request_id, True)
            return {
                "prompts": [
                    {"name": item.name, "description": item.description}
                    for item in sorted(self.prompts.values(), key=lambda value: value.name)
                ]
            }
        if method == "prompts/get":
            if not isinstance(params, dict) or not isinstance(params.get("name"), str):
                raise RequestError(-32602, "prompts/get requires an allowlisted prompt name")
            name = params["name"]
            item = self.prompts.get(name)
            if item is None:
                self.record_call(method, request_id, False)
                raise RequestError(-32602, "prompt name is not allowlisted")
            _, content = self.read_resource(item.uri)
            self.record_call(method, request_id, True, item.uri)
            return {
                "description": item.description,
                "messages": [{"role": "user", "content": {"type": "text", "text": content}}],
            }
        if method == "tools/list":
            self.record_call(method, request_id, True)
            return {"tools": self.tools()}
        if method == "tools/call":
            if not isinstance(params, dict) or not isinstance(params.get("name"), str):
                self.record_call(method, request_id, False)
                raise RequestError(-32602, "tools/call requires a tool name")
            name = params["name"]
            arguments = params.get("arguments")
            if arguments is None:
                arguments = {}
            if not isinstance(arguments, dict):
                self.record_call(method, request_id, False)
                raise RequestError(-32602, "tool arguments must be an object")
            if name == "factory.list_resources":
                self.record_call(method, request_id, True)
                structured = {"resources": [self.resource_summary(item) for item in self.resources]}
            elif name == "factory.read_resource":
                uri = arguments.get("uri", "")
                try:
                    item, content = self.read_resource(uri)
                    self.record_call(method, request_id, True, uri)
                except RequestError:
                    self.record_call(method, request_id, False, uri if isinstance(uri, str) else "")
                    raise
                structured = {"resource": self.resource_summary(item), "text": content}
            else:
                self.record_call(method, request_id, False)
                raise RequestError(-32602, "tool is not allowlisted and no write-capable tools exist")
            return {
                "content": [{"type": "text", "text": json.dumps(structured, indent=2, sort_keys=True)}],
                "structuredContent": structured,
                "isError": False,
            }
        raise RequestError(-32601, f"method not found: {method}")

    def serve(self) -> int:
        for line in sys.stdin:
            if not line.strip():
                continue
            request_id: Any = None
            notification = False
            try:
                request = json.loads(line)
                if not isinstance(request, dict) or request.get("jsonrpc") != JSONRPC_VERSION or not isinstance(request.get("method"), str):
                    raise RequestError(-32600, "invalid JSON-RPC request")
                notification = "id" not in request
                request_id = safe_json_id(request.get("id"))
                result = self.dispatch(request["method"], request.get("params", {}), request_id)
                if notification:
                    continue
                response = {"jsonrpc": JSONRPC_VERSION, "id": request_id, "result": result}
            except json.JSONDecodeError as exc:
                response = {"jsonrpc": JSONRPC_VERSION, "id": None, "error": {"code": -32700, "message": f"parse error: {exc.msg}"}}
            except RequestError as exc:
                if notification:
                    continue
                error: dict[str, Any] = {"code": exc.code, "message": exc.message}
                if exc.data is not None:
                    error["data"] = exc.data
                response = {"jsonrpc": JSONRPC_VERSION, "id": request_id, "error": error}
            except (TypeError, ValueError) as exc:
                if notification:
                    continue
                response = {"jsonrpc": JSONRPC_VERSION, "id": request_id, "error": {"code": -32602, "message": str(exc)}}
            except Exception as exc:  # pragma: no cover - final protocol safety net
                if notification:
                    continue
                response = {"jsonrpc": JSONRPC_VERSION, "id": request_id, "error": {"code": -32603, "message": f"internal error: {exc}"}}
            print(json.dumps(response, separators=(",", ":")), flush=True)
            if self.stop_requested:
                break
        return 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", default=str(DEFAULT_POLICY), help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        return MCPServer(Path(args.policy).resolve()).serve()
    except ServerError as exc:
        print(f"octopus-factory-mcp: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
