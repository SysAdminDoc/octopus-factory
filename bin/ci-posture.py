#!/usr/bin/env python3
"""Inspect GitHub Actions workflow security posture without third-party YAML."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")
USES_RE = re.compile(r"^\s*-?\s*uses:\s*([^\s#]+)")
NETWORK_RE = re.compile(
    r"\b(?:curl|wget|Invoke-WebRequest|Start-BitsTransfer|nc|ncat|socat)\b|"
    r"\b(?:npm|pnpm|yarn|pip|uv)\s+(?:install|add)\b",
    re.IGNORECASE,
)


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def check(check_id: str, status: str, detail: str, **extra: Any) -> dict[str, Any]:
    item: dict[str, Any] = {"id": check_id, "status": status, "detail": detail}
    item.update(extra)
    return item


def workflow_files(repo: Path) -> list[Path]:
    directory = repo / ".github" / "workflows"
    if not directory.is_dir():
        return []
    return sorted(
        path
        for path in directory.iterdir()
        if path.is_file() and path.suffix.lower() in {".yml", ".yaml"}
    )


def scan_workflow(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    checks: list[dict[str, Any]] = []

    top_permissions = re.search(r"(?m)^permissions:\s*(.*?)\s*$", text)
    if not top_permissions:
        checks.append(check("permissions", "fail", "workflow has no top-level permissions block"))
    elif "write-all" in top_permissions.group(1).lower():
        checks.append(check("permissions", "fail", "workflow requests write-all permissions"))
    else:
        checks.append(check("permissions", "pass", "workflow declares explicit top-level permissions"))

    actions: list[dict[str, str]] = []
    for line_number, line in enumerate(lines, start=1):
        match = USES_RE.match(line)
        if not match:
            continue
        reference = match.group(1)
        if reference.startswith("./") or reference.startswith("docker://"):
            actions.append({"reference": reference, "status": "skip", "line": str(line_number)})
            continue
        _, _, revision = reference.rpartition("@")
        action_status = "pass" if SHA_RE.fullmatch(revision) else "fail"
        actions.append({"reference": reference, "status": action_status, "line": str(line_number)})
        if action_status == "fail":
            checks.append(
                check(
                    "pinned-action",
                    "fail",
                    f"action is not pinned to a full commit SHA: {reference}",
                    line=line_number,
                )
            )
    if not actions:
        checks.append(check("actions", "warn", "workflow has no reusable actions to inspect"))

    harden = "step-security/harden-runner@" in text and bool(
        re.search(r"egress-policy:\s*(?:audit|block)\b", text)
    )
    checks.append(
        check(
            "harden-runner",
            "pass" if harden else "warn",
            "Harden-Runner audit/block policy is declared"
            if harden
            else "workflow has no Harden-Runner audit/block step",
        )
    )

    scorecard = "ossf/scorecard-action@" in text and bool(
        re.search(r"results_format:\s*sarif\b", text)
    )
    checks.append(
        check(
            "scorecard",
            "pass" if scorecard else "warn",
            "Scorecard SARIF output is configured"
            if scorecard
            else "workflow has no Scorecard SARIF output step",
        )
    )

    network_lines = [
        {"line": line_number, "text": line.strip()[:240]}
        for line_number, line in enumerate(lines, start=1)
        if NETWORK_RE.search(line)
    ]
    if network_lines:
        checks.append(
            check(
                "network-egress",
                "warn",
                "workflow contains outbound/package-install commands; review its allowlist",
                lines=network_lines,
            )
        )
    else:
        checks.append(check("network-egress", "pass", "no obvious outbound command was found"))

    return {
        "file": str(path),
        "checks": checks,
        "actions": actions,
        "network_lines": network_lines,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Inspect GitHub Actions supply-chain posture")
    parser.add_argument("command", nargs="?", default="scan", choices=("scan",))
    parser.add_argument("repo", nargs="?", default=".")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--strict", action="store_true", help="return 2 when warnings remain")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    repo = Path(args.repo).expanduser().resolve()
    if not repo.is_dir():
        print(f"ci-posture: repository not found: {repo}", file=sys.stderr)
        return 2

    files = workflow_files(repo)
    workflows = [scan_workflow(path) for path in files]
    findings = [
        {"file": workflow["file"], **item}
        for workflow in workflows
        for item in workflow["checks"]
        if item["status"] in {"fail", "warn"}
    ]
    if not workflows:
        status = "not-applicable"
    elif any(item["status"] == "fail" for item in findings):
        status = "fail"
    elif findings:
        status = "warn"
    else:
        status = "pass"

    report = {
        "schema_version": 1,
        "gate": "ci-supply-chain-posture",
        "status": status,
        "repo": str(repo),
        "workflow_count": len(workflows),
        "workflows": workflows,
        "findings": findings,
        "started_at": timestamp(),
        "ended_at": timestamp(),
    }
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(f"ci-posture: {status} ({len(workflows)} workflow(s))")
        for finding in findings:
            print(f"  [{finding['status']}] {finding['file']}: {finding['detail']}")

    if status == "fail":
        return 1
    if status == "warn" and args.strict:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
