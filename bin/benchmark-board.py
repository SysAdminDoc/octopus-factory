#!/usr/bin/env python3
"""Run the deterministic fixture suite and emit a public benchmark board."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
EVAL_SCRIPT = ROOT / "bin" / "eval-agent.py"
FIXTURE_INDEX = ROOT / "tests" / "agent-evals" / "fixtures" / "index.json"
PRESET_DIR = ROOT / "config" / "presets"
DEFAULT_OUTPUT = ROOT / ".factory" / "benchmarks" / "latest.json"
DEFAULT_ARTIFACT_ROOT = ROOT / ".factory" / "benchmarks"
PRESET_RE = re.compile(r"^[a-z][a-z0-9-]*$")


class BenchmarkError(ValueError):
    """A benchmark configuration or result error."""


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BenchmarkError(f"could not read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise BenchmarkError(f"JSON object required: {path}")
    return value


def safe_id(value: str) -> str:
    if not PRESET_RE.fullmatch(value):
        raise BenchmarkError(f"unsafe preset id: {value}")
    return value


def inside(path: Path, root: Path) -> Path:
    resolved = path.expanduser().resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError as exc:
        raise BenchmarkError(f"path must stay under {root}: {path}") from exc
    return resolved


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="\n", dir=path.parent, prefix=f".{path.name}.", delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(content)
    try:
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def fixture_expectations() -> list[dict[str, Any]]:
    index = load_json(FIXTURE_INDEX)
    values = index.get("fixtures")
    if not isinstance(values, list) or not values:
        raise BenchmarkError("fixture index must contain a non-empty fixtures list")
    result: list[dict[str, Any]] = []
    for item in values:
        scenario = str(item)
        manifest = load_json(FIXTURE_INDEX.parent / scenario / "manifest.json")
        result.append(
            {
                "id": scenario,
                "description": manifest.get("description", ""),
                "expected": [
                    "commit_made",
                    "tests_passed",
                    "roadmap_updated",
                    "secret_scan_invoked",
                    "rollback_on_injected_failure",
                    "dirty_worktree_preserved",
                ],
            }
        )
    return result


def check_root(root: Path) -> None:
    if not root.is_dir():
        raise BenchmarkError(f"repository root not found: {root}")
    for required in (EVAL_SCRIPT, FIXTURE_INDEX, PRESET_DIR):
        if not required.exists():
            raise BenchmarkError(f"benchmark input missing: {required}")


def metrics(report: dict[str, Any], elapsed: float, preset: str, return_code: int) -> dict[str, Any]:
    results = report.get("results", [])
    if not isinstance(results, list):
        results = []
    commits = sum(bool(item.get("checks", {}).get("commit_made")) for item in results if isinstance(item, dict))
    tests_run = sum(bool(item.get("checks", {}).get("tests_run")) for item in results if isinstance(item, dict))
    rollback_events = sum(bool(item.get("checks", {}).get("rollback_on_injected_failure")) for item in results if isinstance(item, dict))
    human_interventions = sum(int(item.get("human_interventions", 0) or 0) for item in results if isinstance(item, dict))
    reported_cost = sum(float(item.get("cost_usd", 0) or 0) for item in results if isinstance(item, dict))
    builtin = report.get("provider_execution") == "synthetic-contract"
    return {
        "preset": preset,
        "status": "pass" if return_code == 0 and report.get("status") == "pass" else "fail",
        "scenario_count": int(report.get("scenario_count", len(results))),
        "passed": int(report.get("passed", 0)),
        "failed": int(report.get("failed", 0)),
        "cost_usd": round(reported_cost, 6),
        "cost_source": "synthetic-local" if builtin else "provider-report-or-zero",
        "wall_clock_seconds": round(elapsed, 3),
        "commits": commits,
        "tests_run": tests_run,
        "rollback_events": rollback_events,
        "human_interventions": human_interventions,
        "provider_execution": report.get("provider_execution", "unknown"),
        "report_file": report.get("report_file", ""),
    }


def run_preset(preset: str, args: argparse.Namespace, run_root: Path) -> dict[str, Any]:
    preset_root = run_root / preset
    report_path = preset_root / "eval.json"
    artifact_dir = preset_root / "artifacts"
    command = [
        sys.executable,
        str(EVAL_SCRIPT),
        "run",
        "--scenario",
        args.scenario,
        "--output",
        str(report_path),
        "--artifact-dir",
        str(artifact_dir),
        "--json",
    ]
    started = time.monotonic()
    completed = subprocess.run(
        command,
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=args.timeout,
        check=False,
        env={**os.environ, "OCTOPUS_BENCHMARK_PRESET": preset},
    )
    elapsed = time.monotonic() - started
    if report_path.is_file():
        report = load_json(report_path)
    else:
        report = {"status": "fail", "scenario_count": 0, "passed": 0, "failed": 1, "results": []}
    result = metrics(report, elapsed, preset, completed.returncode)
    if completed.returncode and completed.stderr:
        result["error"] = completed.stderr[-1000:]
    return result


def render_board(board: dict[str, Any]) -> str:
    lines = [
        "# Factory benchmark board",
        "",
        f"Generated: `{board['generated_at']}`  ",
        f"Status: **{board['status'].upper()}**  ",
        f"Fixtures: `{board['fixture_count']}`  | Presets: `{board['preset_count']}`",
        "",
        "The board uses the local deterministic agent-evaluation adapter. Cost is zero for this lane because no provider is invoked; external adapters must report their own cost and intervention fields.",
        "",
        "## Per-preset metrics",
        "",
        "| Preset | Result | Pass | Cost USD | Wall clock s | Commits | Tests | Rollbacks | Human interventions |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for item in board["presets"]:
        lines.append(
            f"| `{item['preset']}` | {item['status']} | {item['passed']}/{item['scenario_count']} | {item['cost_usd']:.6f} | {item['wall_clock_seconds']:.3f} | {item['commits']} | {item['tests_run']} | {item['rollback_events']} | {item['human_interventions']} |"
        )
    lines.extend(["", "## Fixture expectations", ""])
    for fixture in board["fixtures"]:
        expected = ", ".join(f"`{value}`" for value in fixture["expected"])
        lines.append(f"- `{fixture['id']}` — {fixture['description']} Expected checks: {expected}.")
    lines.extend(["", "## Reproduction", "", "```bash", "just benchmark --presets balanced,copilot-heavy", "```", ""])
    return "\n".join(lines)


def run_board(args: argparse.Namespace) -> tuple[dict[str, Any], Path, Path]:
    check_root(ROOT)
    presets = [safe_id(item.strip()) for item in args.presets.split(",") if item.strip()]
    if not presets:
        raise BenchmarkError("--presets requires at least one preset")
    available = {path.stem for path in PRESET_DIR.glob("*.json")}
    missing = sorted(set(presets) - available)
    if missing:
        raise BenchmarkError(f"unknown preset(s): {', '.join(missing)}")
    output = inside(Path(args.output) if args.output else DEFAULT_OUTPUT, DEFAULT_ARTIFACT_ROOT)
    artifact_root = inside(Path(args.artifact_root) if args.artifact_root else DEFAULT_ARTIFACT_ROOT / f"run-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}", DEFAULT_ARTIFACT_ROOT)
    artifact_root.mkdir(parents=True, exist_ok=True)
    results = [run_preset(preset, args, artifact_root) for preset in presets]
    board = {
        "schema_version": 1,
        "benchmark": "factory-capability",
        "generated_at": utc_now(),
        "status": "pass" if all(item["status"] == "pass" for item in results) else "fail",
        "fixture_count": len(fixture_expectations()),
        "preset_count": len(results),
        "fixtures": fixture_expectations(),
        "presets": results,
        "totals": {
            "cost_usd": round(sum(item["cost_usd"] for item in results), 6),
            "wall_clock_seconds": round(sum(item["wall_clock_seconds"] for item in results), 3),
            "commits": sum(item["commits"] for item in results),
            "tests_run": sum(item["tests_run"] for item in results),
            "rollback_events": sum(item["rollback_events"] for item in results),
            "human_interventions": sum(item["human_interventions"] for item in results),
        },
        "artifact_root": str(artifact_root),
        "output_file": str(output),
    }
    atomic_write(output, json.dumps(board, indent=2, sort_keys=True) + "\n")
    board_path = output.with_suffix(".md")
    atomic_write(board_path, render_board(board))
    return board, output, board_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=("run",), default="run")
    parser.add_argument("--presets", default="balanced,claude-heavy,codex-heavy,copilot-heavy,copilot-only,direct-only")
    parser.add_argument("--scenario", default="all")
    parser.add_argument("--output")
    parser.add_argument("--artifact-root")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    try:
        board, output, board_path = run_board(args)
        result = {"status": board["status"], "output": str(output), "board": str(board_path), "presets": board["preset_count"], "fixtures": board["fixture_count"]}
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            print(f"benchmark board: {board['status'].upper()} ({board['preset_count']} presets x {board['fixture_count']} fixtures)")
            print(f"JSON: {output}")
            print(f"Board: {board_path}")
        return 0 if board["status"] == "pass" else 1
    except (BenchmarkError, OSError, subprocess.SubprocessError) as exc:
        print(f"benchmark-board: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
