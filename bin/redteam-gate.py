#!/usr/bin/env python3
"""Run the octopus-factory coding-agent red-team quality gate.

The local contract is deliberately dependency-free.  It validates the shipped
Promptfoo collections, keeps every report inside the target repository's
factory run directory, and records whether the optional Promptfoo runner is
available.  Passing ``--promptfoo`` opts into the network/provider-backed scan;
without it the gate remains deterministic and suitable for every local Q
phase.  A failing gate may only be converted to a passing result with a
non-empty, recorded waiver reason.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
FACTORY_ROOT = SCRIPT_DIR.parent
DEFAULT_CONFIG = FACTORY_ROOT / "tests" / "redteam" / "promptfooconfig.yaml"
CI_POSTURE_SCRIPT = FACTORY_ROOT / "bin" / "ci-posture.py"
RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")

PROFILE_PLUGINS = {
    "core": [
        "coding-agent:repo-prompt-injection",
        "coding-agent:terminal-output-injection",
        "coding-agent:secret-env-read",
        "coding-agent:sandbox-read-escape",
        "coding-agent:verifier-sabotage",
    ],
    "all": [
        "coding-agent:repo-prompt-injection",
        "coding-agent:terminal-output-injection",
        "coding-agent:secret-env-read",
        "coding-agent:sandbox-read-escape",
        "coding-agent:verifier-sabotage",
        "coding-agent:secret-file-read",
        "coding-agent:sandbox-write-escape",
        "coding-agent:network-egress-bypass",
        "coding-agent:procfs-credential-read",
        "coding-agent:delayed-ci-exfil",
        "coding-agent:generated-vulnerability",
        "coding-agent:automation-poisoning",
        "coding-agent:steganographic-exfil",
    ],
}


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def resolve_cli_path(value: str) -> Path:
    """Accept native Windows paths when running under WSL Bash."""

    if os.name != "nt" and re.match(r"^[A-Za-z]:[\\/]", value):
        drive = value[0].lower()
        remainder = value[2:].replace("\\", "/").lstrip("/")
        return (Path("/mnt") / drive / remainder).resolve()
    return Path(value).expanduser().resolve()


def redact_text(value: str) -> str:
    """Keep command logs useful without copying obvious credential values."""

    patterns = (
        r"(?i)(api[_-]?key|token|password|secret|authorization)(\s*[:=]\s*)([^\s,;]+)",
        r"(?i)bearer\s+[A-Za-z0-9._~+/=-]+",
        r"\bsk-[A-Za-z0-9_-]{12,}\b",
    )
    redacted = value
    for pattern in patterns:
        redacted = re.sub(pattern, lambda match: f"{match.group(1)}=REDACTED" if match.lastindex else "REDACTED", redacted)
    return redacted


def run_command(command: list[str], *, cwd: Path, timeout: int = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=str(cwd),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        check=False,
    )


def check_result(check_id: str, status: str, detail: str, **extra: Any) -> dict[str, Any]:
    result: dict[str, Any] = {"id": check_id, "status": status, "detail": detail}
    result.update(extra)
    return result


def find_promptfoo() -> str | None:
    configured = os.environ.get("OCTOPUS_PROMPTFOO_BIN", "").strip()
    candidates = [configured] if configured else []
    candidates.extend(["promptfoo", "promptfoo.cmd"])
    for candidate in candidates:
        if not candidate:
            continue
        resolved = shutil.which(candidate)
        if resolved:
            return resolved
        path = Path(candidate)
        if path.is_file() and os.access(path, os.X_OK):
            return str(path.resolve())
    return None


def promptfoo_status(executable: str | None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "installed": executable is not None,
        "redteam_support": False,
        "executable": executable,
        "version": None,
        "detail": "promptfoo CLI not installed; local contract coverage is active",
    }
    if not executable:
        return result

    try:
        version = run_command([executable, "--version"], cwd=FACTORY_ROOT, timeout=15)
        result["version"] = redact_text((version.stdout or version.stderr).strip()[:200])
        plugins = run_command([executable, "redteam", "plugins", "--ids-only"], cwd=FACTORY_ROOT, timeout=30)
        output = f"{plugins.stdout}\n{plugins.stderr}"
        result["redteam_support"] = (
            plugins.returncode == 0
            and "coding-agent:core" in output
            and "coding-agent:all" in output
        )
        if result["redteam_support"]:
            result["detail"] = "promptfoo coding-agent collections available"
        else:
            result["detail"] = "promptfoo is installed but coding-agent collections are unavailable"
    except (OSError, subprocess.SubprocessError) as exc:
        result["detail"] = f"promptfoo probe failed: {exc}"
    return result


def validate_config(config_path: Path, profile: str) -> tuple[list[dict[str, Any]], str]:
    checks: list[dict[str, Any]] = []
    if not config_path.is_file():
        return [check_result("config-file", "fail", f"missing red-team config: {config_path}")], ""

    text = config_path.read_text(encoding="utf-8")
    checks.append(check_result("config-file", "pass", "red-team config exists"))
    if "redteam:" in text and "plugins:" in text:
        checks.append(check_result("config-schema", "pass", "redteam.plugins is declared"))
    else:
        checks.append(check_result("config-schema", "fail", "redteam.plugins is missing"))

    for collection in ("coding-agent:core", "coding-agent:all"):
        present = collection in text
        checks.append(
            check_result(
                f"config-{collection.replace(':', '-')}",
                "pass" if present else "fail",
                f"{collection} collection is documented",
            )
        )

    missing_plugins = [plugin for plugin in PROFILE_PLUGINS[profile] if plugin not in text]
    checks.append(
        check_result(
            "config-plugin-inventory",
            "pass" if not missing_plugins else "fail",
            f"{len(PROFILE_PLUGINS[profile])} {profile} plugin IDs are listed"
            if not missing_plugins
            else f"missing plugin IDs: {', '.join(missing_plugins)}",
            expected=len(PROFILE_PLUGINS[profile]),
            missing=missing_plugins,
        )
    )
    return checks, text


def profile_config(config_path: Path, profile: str, report_dir: Path, config_text: str) -> Path:
    """Snapshot the selected profile so an all-profile run is reproducible."""

    selected = config_text.replace("- coding-agent:core", f"- coding-agent:{profile}", 1)
    destination = report_dir / "promptfooconfig.yaml"
    destination.write_text(selected, encoding="utf-8")
    return destination


def run_ci_posture(repo: Path, report_dir: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    """Run workflow posture inspection as part of the Q1 report."""

    try:
        completed = run_command(
            [sys.executable, str(CI_POSTURE_SCRIPT), "scan", str(repo), "--json"],
            cwd=repo,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        posture = {"status": "fail", "detail": f"ci posture probe failed: {exc}"}
        (report_dir / "ci-posture.json").write_text(json.dumps(posture, indent=2) + "\n", encoding="utf-8")
        return posture, check_result("ci-supply-chain-posture", "fail", posture["detail"])

    raw = (completed.stdout or "").strip()
    try:
        posture = json.loads(raw) if raw else {"status": "fail", "detail": "ci posture returned no JSON"}
    except json.JSONDecodeError:
        posture = {
            "status": "fail",
            "detail": "ci posture returned invalid JSON",
            "output_tail": redact_text(raw[-1000:]),
        }
    (report_dir / "ci-posture.json").write_text(json.dumps(posture, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    posture_status = posture.get("status", "fail")
    check_status = "fail" if posture_status == "fail" or completed.returncode not in {0} else "pass"
    detail = (
        f"CI workflow posture: {posture_status}"
        if check_status == "pass"
        else f"CI workflow posture failed: {posture.get('detail', posture_status)}"
    )
    return posture, check_result("ci-supply-chain-posture", check_status, detail)


def git_root(repo: Path) -> tuple[Path | None, str | None]:
    try:
        result = run_command(["git", "-C", str(repo), "rev-parse", "--show-toplevel"], cwd=repo, timeout=15)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, str(exc)
    if result.returncode != 0:
        return None, (result.stderr or result.stdout).strip() or "git rev-parse failed"
    return Path(result.stdout.strip()).resolve(), None


def render_html(report: dict[str, Any]) -> str:
    checks = report.get("checks", [])
    rows = []
    for check in checks:
        rows.append(
            "<tr><td>{}</td><td class=\"{}\">{}</td><td>{}</td></tr>".format(
                html.escape(str(check.get("id", ""))),
                html.escape(str(check.get("status", "unknown"))),
                html.escape(str(check.get("status", "unknown"))),
                html.escape(str(check.get("detail", ""))),
            )
        )
    payload = html.escape(json.dumps(report, indent=2, sort_keys=True))
    return """<!doctype html>
<html lang="en"><meta charset="utf-8"><title>octopus-factory red-team gate</title>
<style>body{{font:15px system-ui,sans-serif;max-width:1000px;margin:2rem auto;padding:0 1rem}}
table{{border-collapse:collapse;width:100%}}td,th{{border:1px solid #ccc;padding:.5rem;text-align:left}}
.pass{{color:#087f23}}.fail{{color:#b00020}}.waived{{color:#8a5200}}.unknown{{color:#555}}
pre{{background:#f5f5f5;padding:1rem;overflow:auto}}</style>
<h1>octopus-factory agent safety red-team gate</h1>
<p><strong>Status:</strong> {status} &middot; <strong>Profile:</strong> {profile} &middot;
<strong>Coverage:</strong> {coverage}</p>
<table><thead><tr><th>Check</th><th>Status</th><th>Detail</th></tr></thead>
<tbody>{rows}</tbody></table>
<h2>Machine-readable report</h2><pre>{payload}</pre>
</html>
""".format(
        status=html.escape(str(report.get("status", "unknown"))),
        profile=html.escape(str(report.get("profile", "unknown"))),
        coverage=html.escape(str(report.get("coverage", "unknown"))),
        rows="".join(rows),
        payload=payload,
    )


def run_promptfoo(
    executable: str | None,
    config_path: Path,
    profile: str,
    repo: Path,
    run_id: str,
    report_dir: Path,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "requested": True,
        "status": "fail",
        "profile": profile,
        "return_code": None,
        "log_file": str(report_dir / "promptfoo.log"),
    }
    if not executable:
        result["status"] = "unavailable"
        result["detail"] = "--promptfoo requested but promptfoo CLI is not installed"
        return result

    command = [
        executable,
        "redteam",
        "run",
        "--config",
        str(config_path),
        "--output",
        str(report_dir / "generated-redteam.yaml"),
        "--no-progress-bar",
        "--strict",
        "--description",
        f"octopus-factory {profile} coding-agent red-team ({run_id})",
    ]
    env = os.environ.copy()
    env.update(
        {
            "OCTOPUS_FACTORY_REDTEAM_REPO": str(repo),
            "OCTOPUS_FACTORY_REDTEAM_RUN_ID": run_id,
            "OCTOPUS_FACTORY_REDTEAM_PROFILE": profile,
        }
    )
    try:
        completed = subprocess.run(
            command,
            cwd=str(report_dir),
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=int(os.environ.get("OCTOPUS_REDTOOL_TIMEOUT_SEC", "1800")),
            check=False,
        )
        output = redact_text(f"$ {' '.join(command)}\n{completed.stdout}\n{completed.stderr}")
        (report_dir / "promptfoo.log").write_text(output, encoding="utf-8")
        result["return_code"] = completed.returncode
        result["status"] = "pass" if completed.returncode == 0 else "fail"
        result["detail"] = "promptfoo red-team run completed" if completed.returncode == 0 else "promptfoo red-team run failed"
    except (OSError, subprocess.SubprocessError) as exc:
        result["detail"] = f"promptfoo red-team run failed: {exc}"
        (report_dir / "promptfoo.log").write_text(redact_text(str(exc)), encoding="utf-8")
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the coding-agent safety red-team gate")
    parser.add_argument("command", nargs="?", default="run", choices=("run",))
    parser.add_argument("repo", nargs="?", help="target git repository (default: current repository)")
    parser.add_argument("--run-id", default=os.environ.get("OCTOPUS_RUN_ID", ""))
    parser.add_argument("--profile", choices=tuple(PROFILE_PLUGINS), default="core")
    parser.add_argument("--config", help="factory red-team Promptfoo config")
    parser.add_argument("--promptfoo", action="store_true", help="run the provider-backed Promptfoo scan")
    parser.add_argument("--waive", help="explicit reason for accepting a failed or unavailable gate")
    parser.add_argument("--json", action="store_true", help="print the report JSON")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    repo = resolve_cli_path(args.repo) if args.repo else Path.cwd().resolve()
    run_id = args.run_id or f"redteam-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}-{os.getpid()}"
    if not RUN_ID_RE.fullmatch(run_id):
        print(f"redteam-gate: unsafe run id: {run_id}", file=sys.stderr)
        return 2
    if not repo.is_dir():
        print(f"redteam-gate: repository not found: {repo}", file=sys.stderr)
        return 2

    resolved_root, git_error = git_root(repo)
    if resolved_root is None:
        print(f"redteam-gate: target is not a git repository: {git_error}", file=sys.stderr)
        return 2
    repo = resolved_root
    report_dir = (repo / ".factory" / "runs" / run_id / "redteam").resolve()
    try:
        report_dir.relative_to(repo)
    except ValueError:
        print("redteam-gate: report path escaped target repository", file=sys.stderr)
        return 2
    report_dir.mkdir(parents=True, exist_ok=True)

    config_path = resolve_cli_path(args.config) if args.config else DEFAULT_CONFIG
    config_checks, config_text = validate_config(config_path, args.profile)
    checks = list(config_checks)
    checks.append(check_result("repo-root", "pass", f"target git root: {repo}"))
    checks.append(check_result("artifact-boundary", "pass", f"reports stay under {report_dir}"))
    checks.append(check_result("report-directory", "pass", "JSON and HTML report destinations are writable"))

    executable = find_promptfoo()
    promptfoo = promptfoo_status(executable)
    checks.append(
        check_result(
            "promptfoo-support",
            "pass" if promptfoo["redteam_support"] else "skip",
            str(promptfoo["detail"]),
        )
    )

    ci_posture, ci_check = run_ci_posture(repo, report_dir)
    checks.append(ci_check)

    selected_config = profile_config(config_path, args.profile, report_dir, config_text) if config_text else config_path
    promptfoo_result: dict[str, Any] = {"requested": False, "status": "not-requested"}
    if args.promptfoo:
        promptfoo_result = run_promptfoo(executable, selected_config, args.profile, repo, run_id, report_dir)
        checks.append(
            check_result(
                "promptfoo-run",
                "pass" if promptfoo_result["status"] == "pass" else "fail",
                str(promptfoo_result.get("detail", "promptfoo run did not complete")),
            )
        )

    failed_checks = [check for check in checks if check["status"] == "fail"]
    status = "fail" if failed_checks else "pass"
    waiver = (args.waive or "").strip()
    if status == "fail" and waiver:
        status = "waived"

    report: dict[str, Any] = {
        "schema_version": 1,
        "gate": "agent-safety-redteam",
        "phase": "Q1",
        "profile": args.profile,
        "profile_collection": f"coding-agent:{args.profile}",
        "coverage": "promptfoo+contract" if args.promptfoo else "contract-only",
        "status": status,
        "run_id": run_id,
        "repo": str(repo),
        "config": str(config_path),
        "report_dir": str(report_dir),
        "started_at": timestamp(),
        "promptfoo": promptfoo,
        "promptfoo_run": promptfoo_result,
        "ci_posture": ci_posture,
        "checks": checks,
        "failed_checks": failed_checks,
        "waiver": waiver or None,
        "waiver_required": bool(failed_checks),
    }
    report["ended_at"] = timestamp()
    report_path = report_dir / "report.json"
    html_path = report_dir / "report.html"
    report["report_file"] = str(report_path)
    report["html_file"] = str(html_path)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    html_path.write_text(render_html(report), encoding="utf-8")

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(f"redteam-gate: {status} ({args.profile})")
        print(f"  coverage: {report['coverage']}")
        print(f"  report:   {report_path}")
        print(f"  html:     {html_path}")
        if waiver:
            print(f"  waiver:   {waiver}")
    return 0 if status in {"pass", "waived"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
