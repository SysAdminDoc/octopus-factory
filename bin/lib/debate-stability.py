#!/usr/bin/env python3
"""
debate-stability.py — Beta-Binomial adaptive-stopping for multi-agent debate

Ships the math described in directive-debate.md. Reference:
  Hu et al., "Multi-Agent Debate for LLM Judges with Adaptive Stability Detection"
  arXiv 2510.12697  (https://arxiv.org/abs/2510.12697)

Usage:
  debate-stability.py add <run_id> <round> <criterion> <verdict>
      # record one judge verdict. verdict ∈ {PASS, FAIL, UNCERTAIN}

  debate-stability.py decide <run_id> [--max-rounds N] [--ks-threshold 0.05]
      # inspect accumulated history and output one of:
      #   "CONTINUE"    — run another round
      #   "STOP:converged"   — KS distance < threshold for 2 consecutive rounds
      #   "STOP:stalemate"   — hit max_rounds (default 4) without convergence
      #   "STOP:obvious-pass" — round-1 unanimous PASS, confidence > 0.9
      #   "STOP:obvious-fail" — round-1 ≥2 critical findings from Critic

  debate-stability.py summary <run_id>
      # print compact decision summary (per-criterion verdict + KS trace)

State file: .factory/debate-<run_id>.json  (JSON-lines per event, readable)

Algorithm sketch (Hu et al. 2510.12697):
  1. After each round, build a histogram: for each criterion, count PASS agreements.
  2. Fit a Beta distribution via Method of Moments: α/(α+β) ≈ sample mean;
     α+β ≈ sample mean (1-mean) / variance  (when variance is well-defined).
  3. Compute Kolmogorov-Smirnov distance between current round's distribution
     and previous round's. If KS < threshold for 2 rounds in a row → STOP.

No third-party dependencies beyond the Python stdlib — runs on stock Python 3.10+
that ships with Git Bash, macOS, and every Linux distribution.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from pathlib import Path
from typing import Iterable

VERDICT_WEIGHT = {"PASS": 1.0, "UNCERTAIN": 0.5, "FAIL": 0.0}


def _state_path(run_id: str) -> Path:
    base = os.environ.get("OCTOPUS_DEBATE_DIR") or ".factory"
    p = Path(base)
    p.mkdir(parents=True, exist_ok=True)
    return p / f"debate-{run_id}.json"


def _load_events(run_id: str) -> list[dict]:
    path = _state_path(run_id)
    if not path.exists():
        return []
    with path.open(encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def _append_event(run_id: str, event: dict) -> None:
    path = _state_path(run_id)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")


def _rounds(events: Iterable[dict]) -> dict[int, dict[str, list[float]]]:
    """round_num → {criterion: [verdict_weights...]}"""
    out: dict[int, dict[str, list[float]]] = {}
    for e in events:
        if e.get("type") != "verdict":
            continue
        r = e["round"]
        c = e["criterion"]
        v = VERDICT_WEIGHT.get(e["verdict"], 0.0)
        out.setdefault(r, {}).setdefault(c, []).append(v)
    return out


def _beta_params_mom(samples: list[float]) -> tuple[float, float] | None:
    """Method of Moments Beta fit. Returns (alpha, beta) or None if degenerate."""
    if len(samples) < 2:
        return None
    n = len(samples)
    m = sum(samples) / n
    if not 0 < m < 1:
        return None
    var = sum((x - m) ** 2 for x in samples) / (n - 1)
    if var <= 0:
        return None
    concentration = (m * (1 - m) / var) - 1
    if concentration <= 0:
        return None
    a = m * concentration
    b = (1 - m) * concentration
    return (a, b)


def _beta_cdf(x: float, a: float, b: float) -> float:
    """Regularized incomplete beta function via continued fraction (Lentz)."""
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    lbeta = math.lgamma(a) + math.lgamma(b) - math.lgamma(a + b)
    ln_front = a * math.log(x) + b * math.log(1 - x) - lbeta
    if x < (a + 1) / (a + b + 2):
        return math.exp(ln_front) * _betacf(x, a, b) / a
    return 1.0 - math.exp(ln_front) * _betacf(1 - x, b, a) / b


def _betacf(x: float, a: float, b: float) -> float:
    """Continued fraction expansion used by _beta_cdf."""
    max_iter = 200
    eps = 3e-7
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < 1e-30:
        d = 1e-30
    d = 1.0 / d
    h = d
    for m in range(1, max_iter + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < 1e-30:
            d = 1e-30
        c = 1.0 + aa / c
        if abs(c) < 1e-30:
            c = 1e-30
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < 1e-30:
            d = 1e-30
        c = 1.0 + aa / c
        if abs(c) < 1e-30:
            c = 1e-30
        d = 1.0 / d
        dm = d * c
        h *= dm
        if abs(dm - 1.0) < eps:
            break
    return h


def _ks_distance(params_a: tuple[float, float] | None,
                 params_b: tuple[float, float] | None) -> float:
    """KS distance between two Beta distributions, evaluated on a grid."""
    if params_a is None or params_b is None:
        return 1.0
    grid = [i / 100 for i in range(1, 100)]
    max_diff = 0.0
    for x in grid:
        diff = abs(_beta_cdf(x, *params_a) - _beta_cdf(x, *params_b))
        if diff > max_diff:
            max_diff = diff
    return max_diff


# ─── CLI commands ────────────────────────────────────────────────────────


def cmd_add(args: argparse.Namespace) -> int:
    if args.verdict not in VERDICT_WEIGHT:
        print(f"invalid verdict: {args.verdict} (must be PASS/FAIL/UNCERTAIN)", file=sys.stderr)
        return 2
    _append_event(args.run_id, {
        "type": "verdict",
        "round": args.round,
        "criterion": args.criterion,
        "verdict": args.verdict,
        "confidence": args.confidence,
    })
    print(f"recorded: round={args.round} criterion={args.criterion} verdict={args.verdict}")
    return 0


def cmd_decide(args: argparse.Namespace) -> int:
    events = _load_events(args.run_id)
    rounds = _rounds(events)
    if not rounds:
        print("CONTINUE")
        return 0

    round_numbers = sorted(rounds.keys())
    latest = round_numbers[-1]

    # Obvious-pass check — only on round 1
    if latest == 1:
        r1 = rounds[1]
        all_pass = all(all(v == 1.0 for v in vals) for vals in r1.values())
        any_uncertain = any(any(v == 0.5 for v in vals) for vals in r1.values())
        high_conf_events = [e for e in events
                            if e.get("round") == 1
                            and e.get("type") == "verdict"
                            and float(e.get("confidence", 0.0)) >= 0.9]
        if all_pass and not any_uncertain and len(high_conf_events) >= max(1, len(r1)):
            print("STOP:obvious-pass")
            return 0

    # Obvious-fail check — look for 2+ critical findings from Critic in round 1
    critical_findings = sum(
        1 for e in events
        if e.get("type") == "finding"
        and e.get("round") == 1
        and str(e.get("severity", "")).upper() == "CRITICAL"
    )
    if critical_findings >= 2:
        print("STOP:obvious-fail")
        return 0

    # Stalemate
    if latest >= args.max_rounds:
        print("STOP:stalemate")
        return 0

    # Convergence: KS distance below threshold for 2 consecutive rounds
    if latest >= 2:
        def flat_samples(r: int) -> list[float]:
            vals: list[float] = []
            for arr in rounds.get(r, {}).values():
                vals.extend(arr)
            return vals
        params_prev = _beta_params_mom(flat_samples(latest - 1))
        params_now = _beta_params_mom(flat_samples(latest))
        d_now = _ks_distance(params_prev, params_now)

        if latest >= 3:
            params_2back = _beta_params_mom(flat_samples(latest - 2))
            d_prev = _ks_distance(params_2back, params_prev)
            if d_now < args.ks_threshold and d_prev < args.ks_threshold:
                print(f"STOP:converged ks={d_now:.4f}")
                return 0

    print("CONTINUE")
    return 0


def cmd_summary(args: argparse.Namespace) -> int:
    events = _load_events(args.run_id)
    rounds = _rounds(events)
    if not rounds:
        print(f"no events for run: {args.run_id}")
        return 0
    print(f"run: {args.run_id}")
    print(f"total events: {len(events)}")
    print(f"rounds recorded: {sorted(rounds.keys())}")
    for r in sorted(rounds.keys()):
        print(f"\nround {r}:")
        for c, vs in sorted(rounds[r].items()):
            mean = sum(vs) / len(vs)
            print(f"  {c}: n={len(vs)} mean_pass_weight={mean:.2f}")
    # KS trace
    round_nums = sorted(rounds.keys())
    if len(round_nums) >= 2:
        print("\nKS-distance trace:")
        for i in range(1, len(round_nums)):
            def flat(r: int) -> list[float]:
                return [v for arr in rounds[r].values() for v in arr]
            p_prev = _beta_params_mom(flat(round_nums[i - 1]))
            p_now = _beta_params_mom(flat(round_nums[i]))
            d = _ks_distance(p_prev, p_now)
            print(f"  round {round_nums[i - 1]} -> {round_nums[i]}: KS={d:.4f}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="debate-stability")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_add = sub.add_parser("add", help="record one judge verdict")
    p_add.add_argument("run_id")
    p_add.add_argument("round", type=int)
    p_add.add_argument("criterion")
    p_add.add_argument("verdict", choices=list(VERDICT_WEIGHT))
    p_add.add_argument("--confidence", type=float, default=0.8)
    p_add.set_defaults(func=cmd_add)

    p_dec = sub.add_parser("decide", help="decide CONTINUE or STOP")
    p_dec.add_argument("run_id")
    p_dec.add_argument("--max-rounds", type=int, default=4)
    p_dec.add_argument("--ks-threshold", type=float, default=0.05)
    p_dec.set_defaults(func=cmd_decide)

    p_sum = sub.add_parser("summary", help="print decision summary")
    p_sum.add_argument("run_id")
    p_sum.set_defaults(func=cmd_summary)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args) or 0)


if __name__ == "__main__":
    raise SystemExit(main())
