#!/usr/bin/env python3
"""Deterministic local contract harness for the factory loop.

The built-in adapter deliberately performs tiny, known repairs in synthetic
repositories. The harness then verifies the artifacts a real factory run must
produce. A provider adapter can replace those repairs for nightly runs through
the documented environment contract; provider output is never trusted without
the same post-run checks.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = ROOT / "tests" / "agent-evals" / "fixtures"
TRAJECTORY_SCRIPT = ROOT / "bin" / "factory-trajectory.sh"
CHECKPOINT_SCRIPT = ROOT / "bin" / "checkpoint.sh"


class EvalError(RuntimeError):
    """A harness configuration or fixture failure."""


def now_stamp() -> str:
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


def safe_id(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-")
    if not cleaned:
        raise EvalError(f"cannot build a safe id from {value!r}")
    return cleaned


def resolve_cli_path(value: str) -> Path:
    """Accept native Windows paths when the harness runs under WSL Bash."""
    if os.name != "nt" and re.match(r"^[A-Za-z]:[\\/]", value):
        drive = value[0].lower()
        remainder = value[2:].replace("\\", "/").lstrip("/")
        return (Path("/mnt") / drive / remainder).resolve()
    return Path(value).resolve()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EvalError(f"could not read JSON fixture {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise EvalError(f"fixture JSON must be an object: {path}")
    return value


def run_command(
    command: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        env=merged_env,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )


def git(repo: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return run_command(["git", "-C", str(repo), *arguments], cwd=repo)


def require_success(result: subprocess.CompletedProcess[str], label: str) -> None:
    if result.returncode:
        details = (result.stdout + result.stderr).strip()
        raise EvalError(f"{label} failed with exit {result.returncode}: {details[-500:]}")


def find_bash() -> str:
    candidates = [
        os.environ.get("OCTOPUS_BASH", ""),
        os.environ.get("ProgramFiles", "") + r"\Git\bin\bash.exe",
        os.environ.get("ProgramW6432", "") + r"\Git\bin\bash.exe",
        "/usr/bin/bash",
        shutil.which("bash") or "",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise EvalError("bash is required to emit the canonical trajectory")


def trajectory_env(run_id: str, repo: Path, trajectory_root: Path) -> dict[str, str]:
    return {
        "OCTOPUS_RUN_ID": run_id,
        "OCTOPUS_TRAJECTORY_REPO": str(repo),
        "OCTOPUS_TRAJECTORY_ROOT": str(trajectory_root),
        "OCTOPUS_TRAJECTORY_SOURCE": "agent-eval",
    }


def trajectory_call(
    bash: str,
    run_id: str,
    repo: Path,
    trajectory_root: Path,
    command: str,
    *arguments: str,
) -> subprocess.CompletedProcess[str]:
    env = trajectory_env(run_id, repo, trajectory_root)
    return run_command(
        [bash, str(TRAJECTORY_SCRIPT), command, *arguments], cwd=repo, env=env
    )


def trajectory_init(bash: str, run_id: str, repo: Path, trajectory_root: Path) -> None:
    result = trajectory_call(bash, run_id, repo, trajectory_root, "init")
    require_success(result, "trajectory init")


def trajectory_emit(
    bash: str,
    run_id: str,
    repo: Path,
    trajectory_root: Path,
    event: str,
    payload: dict[str, Any],
    phase: str = "eval",
    iteration: str = "1",
    actor: str = "agent-eval",
) -> None:
    env = trajectory_env(run_id, repo, trajectory_root)
    env["OCTOPUS_TRAJECTORY_PAYLOAD"] = json.dumps(payload, separators=(",", ":"))
    result = run_command(
        [
            bash,
            str(TRAJECTORY_SCRIPT),
            "emit",
            event,
            "--phase",
            phase,
            "--iteration",
            iteration,
            "--actor",
            actor,
            "--payload-env",
            "OCTOPUS_TRAJECTORY_PAYLOAD",
        ],
        cwd=repo,
        env=env,
    )
    require_success(result, f"trajectory emit {event}")


def trajectory_export(
    bash: str, run_id: str, repo: Path, trajectory_root: Path
) -> dict[str, Any]:
    result = trajectory_call(
        bash, run_id, repo, trajectory_root, "export-eval", run_id
    )
    require_success(result, "trajectory export-eval")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise EvalError(f"trajectory export was not JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise EvalError("trajectory export must be a JSON object")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def count_unchecked(roadmap: Path) -> int:
    if not roadmap.exists():
        return 0
    return len(re.findall(r"(?m)^\s*-\s*\[ \]\s+", roadmap.read_text(encoding="utf-8")))


def copy_fixture(fixture: Path, manifest: dict[str, Any], repo: Path) -> None:
    for relative_name in manifest.get("files", []):
        relative = Path(str(relative_name))
        if relative.is_absolute() or ".." in relative.parts:
            raise EvalError(f"fixture path escapes fixture root: {relative}")
        source = fixture / relative
        target = repo / relative
        if not source.is_file():
            raise EvalError(f"fixture file missing: {source}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    roadmap_source = manifest.get("roadmap_source", "roadmap.txt")
    source = fixture / str(roadmap_source)
    if not source.is_file():
        raise EvalError(f"roadmap fixture missing: {source}")
    (repo / "ROADMAP.md").write_text(source.read_text(encoding="utf-8"), encoding="utf-8")


def initialize_repo(fixture: Path, manifest: dict[str, Any], repo: Path) -> None:
    repo.mkdir(parents=True, exist_ok=True)
    (repo / ".gitignore").write_text(".factory/\n", encoding="utf-8")
    copy_fixture(fixture, manifest, repo)
    require_success(run_command(["git", "init", "--quiet", str(repo)]), "git init")
    require_success(git(repo, "config", "user.email", "eval-agent@example.invalid"), "git config email")
    require_success(git(repo, "config", "user.name", "octopus-factory eval"), "git config name")
    require_success(git(repo, "add", "-A"), "initial git add")
    require_success(git(repo, "commit", "--quiet", "-m", "fixture: initialize eval repo"), "initial commit")


def apply_builtin_repair(repo: Path, repair: str) -> list[str]:
    changed: list[str] = []
    replacements = {
        "broken-python-cli": (repo / "cli.py", "return left - right", "return left + right"),
        "stale-ui": (repo / "index.html", "Old Factory UI", "Factory UI"),
        "vulnerable-dependency": (
            repo / "requirements.txt",
            "vulnerable-package==1.0",
            "safe-package==2.0",
        ),
    }
    if repair in replacements:
        path, old, new = replacements[repair]
        text = path.read_text(encoding="utf-8")
        if old not in text:
            raise EvalError(f"built-in repair target not found in {path}: {old}")
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
        changed.append(str(path.relative_to(repo)))
    elif repair == "malformed-roadmap":
        path = repo / "ROADMAP.md"
        path.write_text("# Roadmap\n\n- [ ] Repair malformed roadmap entry\n", encoding="utf-8")
        changed.append("ROADMAP.md")
    elif repair == "dirty-worktree":
        # The dirty fixture is intentionally left untouched; the harness checks
        # that the user-owned file survives the agent commit.
        pass
    else:
        raise EvalError(f"unknown built-in repair: {repair}")

    return changed


def remove_first_roadmap_item(roadmap: Path) -> None:
    text = roadmap.read_text(encoding="utf-8")
    updated, count = re.subn(
        r"(?m)^\s*-\s*\[ \]\s+.*(?:\n|$)", "", text, count=1
    )
    if count == 0:
        raise EvalError("ROADMAP.md has no actionable row after adapter execution")
    if not updated.strip():
        updated = "# Roadmap\n"
    roadmap.write_text(updated, encoding="utf-8")


def make_secret_scanner(repo: Path) -> tuple[list[str], Path, Path]:
    factory_dir = repo / ".factory"
    factory_dir.mkdir(parents=True, exist_ok=True)
    marker = factory_dir / "eval-secret-scan.invoked"
    event_log = factory_dir / "eval-events.jsonl"
    script = factory_dir / "eval-secret-scan.py"
    script.write_text(
        "import os\n"
        "from pathlib import Path\n"
        "Path(os.environ['OCTOPUS_EVAL_SECRET_MARKER']).write_text('invoked\\n', encoding='utf-8')\n"
        "Path(os.environ['OCTOPUS_EVAL_EVENT_LOG']).open('a', encoding='utf-8').write('{\"event\":\"secret_scan\"}\\n')\n",
        encoding="utf-8",
    )
    return [sys.executable, str(script)], marker, event_log


def invoke_adapter(
    adapter: Path | None,
    bash: str,
    repo: Path,
    scenario: str,
    event_log: Path,
    secret_scanner: list[str],
    run_id: str,
    trajectory_root: Path,
    provider: str,
) -> subprocess.CompletedProcess[str]:
    if adapter is None:
        changed = apply_builtin_repair(repo, scenario)
        return subprocess.CompletedProcess(["builtin-adapter"], 0, "\n".join(changed), "")

    if not adapter.is_file():
        raise EvalError(f"adapter does not exist: {adapter}")
    if adapter.suffix.lower() == ".py":
        command = [sys.executable, str(adapter)]
    elif adapter.suffix.lower() in {".sh", ".bash"}:
        command = [bash, str(adapter)]
    else:
        command = [str(adapter)]
    command.extend([str(repo), scenario, str(event_log)])
    return run_command(
        command,
        cwd=repo,
        env={
            "OCTOPUS_EVAL_REPO": str(repo),
            "OCTOPUS_EVAL_SCENARIO": scenario,
            "OCTOPUS_EVAL_PROVIDER": provider,
            "OCTOPUS_EVAL_EVENT_LOG": str(event_log),
            "OCTOPUS_EVAL_SECRET_SCAN": os.fspath(secret_scanner[0]),
            "OCTOPUS_EVAL_RUN_ID": run_id,
            "OCTOPUS_EVAL_TRAJECTORY_ROOT": str(trajectory_root),
        },
    )


def run_fixture_tests(repo: Path, artifact_dir: Path) -> tuple[bool, bool, str]:
    command = [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"]
    result = run_command(command, cwd=repo)
    output = (result.stdout + result.stderr).strip()
    (artifact_dir / "test-output.txt").write_text(output + "\n", encoding="utf-8")
    return True, result.returncode == 0, output[-1000:]


def run_rollback_check(
    bash: str,
    run_id: str,
    repo: Path,
    trajectory_root: Path,
) -> bool:
    target = repo / ".eval-rollback-target.txt"
    target.write_text("stable\n", encoding="utf-8")
    require_success(git(repo, "add", str(target.relative_to(repo))), "rollback seed add")
    require_success(git(repo, "commit", "--quiet", "-m", "eval: seed rollback target"), "rollback seed commit")

    init = run_command([bash, str(CHECKPOINT_SCRIPT), "init"], cwd=repo, env=trajectory_env(run_id, repo, trajectory_root))
    require_success(init, "checkpoint init")
    snapshot = run_command(
        [bash, str(CHECKPOINT_SCRIPT), "snapshot", "EVAL", "0"],
        cwd=repo,
        env=trajectory_env(run_id, repo, trajectory_root),
    )
    require_success(snapshot, "checkpoint snapshot")
    target.write_text("injected failure\n", encoding="utf-8")
    rollback = run_command(
        [bash, str(CHECKPOINT_SCRIPT), "rollback", "EVAL", "0"],
        cwd=repo,
        env=trajectory_env(run_id, repo, trajectory_root),
    )
    require_success(rollback, "checkpoint rollback")
    return target.read_text(encoding="utf-8") == "stable\n"


def git_head(repo: Path) -> str:
    result = git(repo, "rev-parse", "HEAD")
    require_success(result, "git rev-parse")
    return result.stdout.strip()


def run_one(
    fixture: Path,
    manifest: dict[str, Any],
    provider: str,
    adapter: Path | None,
    bash: str,
    artifact_root: Path,
    temp_root: Path,
    keep_repos: bool,
) -> dict[str, Any]:
    scenario = str(manifest["id"])
    scenario_id = safe_id(f"{provider}-{scenario}")
    run_id = safe_id(f"eval-{provider}-{scenario}-{time.time_ns()}")
    artifact_dir = artifact_root / scenario_id
    artifact_dir.mkdir(parents=True, exist_ok=True)
    repo = temp_root / scenario_id
    trajectory_root = artifact_dir / "trajectory"
    checks: dict[str, bool] = {
        "commit_made": False,
        "tests_run": False,
        "tests_passed": False,
        "roadmap_updated": False,
        "secret_scan_invoked": False,
        "rollback_on_injected_failure": False,
        "dirty_worktree_preserved": True,
    }
    result: dict[str, Any] = {
        "scenario": scenario,
        "provider": provider,
        "run_id": run_id,
        "status": "fail",
        "checks": checks,
        "artifact_dir": str(artifact_dir),
    }

    try:
        initialize_repo(fixture, manifest, repo)
        base_head = git_head(repo)
        if manifest.get("dirty_file"):
            dirty_path = repo / str(manifest["dirty_file"])
            dirty_path.parent.mkdir(parents=True, exist_ok=True)
            dirty_path.write_text("user-owned dirty worktree\n", encoding="utf-8")
        else:
            dirty_path = None

        trajectory_init(bash, run_id, repo, trajectory_root)
        trajectory_emit(
            bash,
            run_id,
            repo,
            trajectory_root,
            "prompt_dispatch",
            {"scenario": scenario, "provider": provider, "adapter": bool(adapter)},
        )

        secret_command, secret_marker, event_log = make_secret_scanner(repo)
        adapter_result = invoke_adapter(
            adapter,
            bash,
            repo,
            str(manifest.get("repair", scenario)),
            event_log,
            secret_command,
            run_id,
            trajectory_root,
            provider,
        )
        trajectory_emit(
            bash,
            run_id,
            repo,
            trajectory_root,
            "command_output",
            {"command": "agent-adapter", "exit_code": adapter_result.returncode},
        )
        if adapter_result.returncode:
            result["adapter_error"] = (adapter_result.stdout + adapter_result.stderr)[-1000:]

        roadmap = repo / "ROADMAP.md"
        before_hash = sha256_file(roadmap)
        before_rows = count_unchecked(roadmap)
        if adapter is None and str(manifest.get("repair")) == "malformed-roadmap":
            # The built-in repair creates the valid actionable row first.
            pass
        remove_first_roadmap_item(roadmap)
        after_hash = sha256_file(roadmap)
        checks["roadmap_updated"] = before_hash != after_hash and (
            count_unchecked(roadmap) < before_rows or str(manifest.get("repair")) == "malformed-roadmap"
        )
        trajectory_emit(
            bash,
            run_id,
            repo,
            trajectory_root,
            "file_diff",
            {"path": "ROADMAP.md", "before_sha256": before_hash, "after_sha256": after_hash},
        )

        scan_result = run_command(
            secret_command,
            cwd=repo,
            env={
                "OCTOPUS_EVAL_SECRET_MARKER": str(secret_marker),
                "OCTOPUS_EVAL_EVENT_LOG": str(event_log),
            },
        )
        checks["secret_scan_invoked"] = secret_marker.is_file() and scan_result.returncode == 0
        trajectory_emit(
            bash,
            run_id,
            repo,
            trajectory_root,
            "gate_result",
            {"name": "secret-scan", "status": "pass" if checks["secret_scan_invoked"] else "fail"},
        )

        tests_started, tests_passed, test_tail = run_fixture_tests(repo, artifact_dir)
        checks["tests_run"] = tests_started
        checks["tests_passed"] = tests_passed
        trajectory_emit(
            bash,
            run_id,
            repo,
            trajectory_root,
            "tool_command",
            {"command": "python -m unittest discover", "exit_code": 0 if tests_passed else 1},
        )
        trajectory_emit(
            bash,
            run_id,
            repo,
            trajectory_root,
            "gate_result",
            {"name": "fixture-tests", "status": "pass" if tests_passed else "fail"},
        )
        result["test_output_tail"] = test_tail

        if adapter is None or git_head(repo) == base_head:
            require_success(git(repo, "add", "-A"), "agent change add")
            if dirty_path is not None:
                reset = git(repo, "reset", "--", str(dirty_path.relative_to(repo)))
                require_success(reset, "dirty worktree unstage")
            staged = git(repo, "diff", "--cached", "--quiet")
            if staged.returncode == 0:
                raise EvalError("adapter produced no committed changes")
            commit = git(repo, "commit", "--quiet", "-m", f"agent: repair {scenario}")
            require_success(commit, "agent commit")
        checks["commit_made"] = git_head(repo) != base_head
        trajectory_emit(
            bash,
            run_id,
            repo,
            trajectory_root,
            "commit",
            {"sha": git_head(repo), "scenario": scenario},
        )

        checks["rollback_on_injected_failure"] = run_rollback_check(
            bash, run_id, repo, trajectory_root
        )
        if dirty_path is not None:
            status = git(repo, "status", "--porcelain")
            checks["dirty_worktree_preserved"] = (
                status.returncode == 0
                and str(manifest["dirty_file"]) in status.stdout
            )
        trajectory_emit(
            bash,
            run_id,
            repo,
            trajectory_root,
            "phase_decision",
            {"decision": "pass" if all(checks.values()) else "fail", "checks": checks},
        )
        trajectory_emit(
            bash,
            run_id,
            repo,
            trajectory_root,
            "run_end",
            {"status": "completed" if all(checks.values()) else "failed"},
        )
        result["trajectory"] = trajectory_export(bash, run_id, repo, trajectory_root)
        result["status"] = "pass" if all(checks.values()) else "fail"
        if keep_repos:
            preserved_repo = artifact_dir / "repo"
            shutil.copytree(repo, preserved_repo, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".git"))
            result["preserved_repo"] = str(preserved_repo)
    except (EvalError, OSError, subprocess.SubprocessError) as exc:
        result["error"] = str(exc)

    (artifact_dir / "result.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return result


def load_manifests() -> list[tuple[Path, dict[str, Any]]]:
    index = read_json(FIXTURE_ROOT / "index.json")
    entries = index.get("fixtures")
    if not isinstance(entries, list):
        raise EvalError("fixture index must contain a fixtures list")
    manifests: list[tuple[Path, dict[str, Any]]] = []
    for entry in entries:
        scenario = str(entry)
        fixture = FIXTURE_ROOT / scenario
        manifest = read_json(fixture / "manifest.json")
        if manifest.get("id") != scenario:
            raise EvalError(f"fixture id mismatch: {fixture}")
        manifests.append((fixture, manifest))
    return manifests


def print_human(report: dict[str, Any]) -> None:
    print(
        f"eval-agent: {report['status'].upper()} "
        f"({report['passed']}/{report['scenario_count']} scenarios)"
    )
    for item in report["results"]:
        print(f"  {item['provider']}/{item['scenario']}: {item['status'].upper()}")
    print(f"  report: {report['report_file']}")
    print(f"  artifacts: {report['artifact_root']}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=("run", "nightly"), default="run")
    parser.add_argument("--scenario", default="all", help="comma-separated fixture ids or all")
    parser.add_argument(
        "--providers",
        default="copilot-sonnet,codex-direct,gemini-flash",
        help="nightly provider labels (no provider is invoked by the built-in adapter)",
    )
    parser.add_argument("--adapter", help="external adapter executable or Python/Bash script")
    parser.add_argument("--output", help="JSON report path")
    parser.add_argument("--artifact-dir", help="directory for reports and exported trajectories")
    parser.add_argument("--json", action="store_true", help="print the report as JSON")
    parser.add_argument(
        "--keep-repos",
        action="store_true",
        help="copy synthetic repositories into the artifact directory for debugging",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        bash = find_bash()
        manifests = load_manifests()
        by_id = {manifest["id"]: (fixture, manifest) for fixture, manifest in manifests}
        if args.scenario == "all":
            selected = manifests
        else:
            names = [name.strip() for name in args.scenario.split(",") if name.strip()]
            missing = [name for name in names if name not in by_id]
            if missing:
                raise EvalError(f"unknown fixture(s): {', '.join(missing)}")
            selected = [by_id[name] for name in names]

        if args.command == "nightly":
            providers = [safe_id(name.strip()) for name in args.providers.split(",") if name.strip()]
            if not providers:
                raise EvalError("nightly requires at least one provider label")
        else:
            providers = ["local"]

        mode_stamp = f"{args.command}-{now_stamp()}-{os.getpid()}"
        default_artifact_root = ROOT / ".factory" / "evals" / mode_stamp
        artifact_root = resolve_cli_path(args.artifact_dir) if args.artifact_dir else default_artifact_root
        artifact_root.mkdir(parents=True, exist_ok=True)
        report_path = resolve_cli_path(args.output) if args.output else ROOT / ".factory" / "evals" / "latest.json"
        report_path.parent.mkdir(parents=True, exist_ok=True)

        results: list[dict[str, Any]] = []
        with tempfile.TemporaryDirectory(prefix="octopus-factory-eval-") as temp_name:
            temp_root = Path(temp_name)
            adapter = resolve_cli_path(args.adapter) if args.adapter else None
            for provider in providers:
                for fixture, manifest in selected:
                    results.append(
                        run_one(
                            fixture,
                            manifest,
                            provider,
                            adapter,
                            bash,
                            artifact_root,
                            temp_root,
                            args.keep_repos,
                        )
                    )

        passed = sum(item["status"] == "pass" for item in results)
        report: dict[str, Any] = {
            "schema_version": 1,
            "harness": "octopus-factory-agent-evals",
            "mode": args.command,
            "adapter": str(Path(args.adapter).resolve()) if args.adapter else "builtin-contract",
            "provider_execution": "external-adapter" if args.adapter else "synthetic-contract",
            "started_at": mode_stamp,
            "scenario_count": len(results),
            "passed": passed,
            "failed": len(results) - passed,
            "status": "pass" if passed == len(results) else "fail",
            "artifact_root": str(artifact_root),
            "report_file": str(report_path),
            "results": results,
        }
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        if args.json:
            print(json.dumps(report, indent=2, sort_keys=True))
        else:
            print_human(report)
        return 0 if report["status"] == "pass" else 1
    except EvalError as exc:
        print(f"eval-agent: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
