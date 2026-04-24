---
name: Three-Role Debate Directive
description: Rubric-conditioned multi-agent debate pattern for L3/L4 audit phases. Replaces sequential Codex-then-Claude audit with Grader / Critic / Defender + Beta-Binomial adaptive stopping. Proven in ICLR 2026 ("Rethinking LLMs as Verifiers") and arXiv 2510.12697 to outperform majority vote and single counter-pass.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
triggers: [debate, rubric, grader, critic, defender, verification]
agents: [grader, critic, defender]
---
# Three-Role Debate Directive

Referenced by the factory-loop audit phase (replaces the simple L3→L4 sequential flow with a structured debate). Rubric-conditioned, adaptive-stop, heterogeneous-agent.

## Why

The ICLR 2026 paper "Rethinking LLMs as Verifiers" shows LLMs are *less* accurate at verification than at solving. The gap closes only when the verifier is conditioned on an explicit rubric and/or uses a different model family than the builder. Multi-agent debate with adaptive stopping (Hu et al., arXiv 2510.12697) further improves accuracy vs. fixed-round debate while cutting cost ~30%.

Our prior L3/L4 was two sequential passes by two models. The upgrade: three roles running simultaneously against a pre-declared rubric, with a stability detector that stops when verdicts converge.

## Preflight: build the rubric

Before the debate runs, a rubric must exist. The rubric comes from the PEC-declared acceptance criteria of each task implemented in L2:

```yaml
# Example rubric entry (generated automatically by L2 pre-implementation)
task_id: L2-task-03
goal: "Add DPAPI key rotation path to CryptoService"
acceptance_criteria:
  - "public RotateDek() method returns Task<bool>"
  - "new DEK persisted via atomic write before old DEK zeroed"
  - "rollback path on save failure restores old DEK"
  - "ZeroMemory called on old DEK buffer after rotation"
  - "unit test covers rotation under concurrent access"
failure_modes:
  - "save-fails mid-rotation leaves user without decryptable data"
  - "ZeroMemory before save allows key recovery from memory dump"
rollback_trigger: "any acceptance criterion fails"
```

No rubric → no debate. If L2 didn't declare a rubric, the phase halts and re-runs L2 with rubric generation enforced.

## Roles

### Grader (cheap model — Haiku / Flash / GPT-5-mini)

**Model tier:** cheap. This role is mechanical scoring, not reasoning.

**Inputs:** the rubric + the diff + test output.

**Output:** for each acceptance criterion, emit `PASS` / `FAIL` / `UNCERTAIN` with a one-line evidence citation (file:line or test-name). Emit an overall verdict: `PASS` / `PARTIAL` / `FAIL`. Emit a confidence score 0.0–1.0.

Must cite evidence for every verdict. Unsupported verdicts are ignored.

### Critic (strong model — Codex / Opus / Gemini 3.1 Pro, different from Defender)

**Model tier:** premium.

**Inputs:** rubric + diff + Grader output + ability to call tools (read files, run tests, search logs).

**Job:** attack the implementation. Find:

- Acceptance criteria the Grader missed
- Edge cases / failure modes not covered
- Tests that pass but don't actually verify the claim
- Silent regressions in unrelated code
- Security / performance issues the rubric didn't anticipate but that matter

**Output:** a structured list of findings with severity (`critical` / `high` / `medium` / `low`) and evidence.

### Defender (strong model — Claude Max, different family than Critic)

**Model tier:** premium.

**Inputs:** rubric + diff + Grader output + Critic output + tool access.

**Job:** respond to each Critic finding. Either:

- Fix the finding (modify code, add test, adjust rubric if it was wrong).
- Rebut with evidence (the finding is a false positive, cite why).
- Accept and defer (finding is real but out of scope — document in session log for future iteration).

**Output:** an updated diff + a response to each Critic finding.

## Adaptive stopping (Beta-Binomial stability detector)

After each debate round, compute the verdict distribution across roles for each acceptance criterion. A round's verdict is a 3-tuple `(grader, critic-survived, defender)`.

Maintain a running Beta distribution for each criterion's pass probability. After each round, compute the Kolmogorov–Smirnov distance between consecutive rounds' distributions.

**Stopping rules:**

- **Converged** — KS distance < 0.05 for 2 consecutive rounds. Debate terminates; final verdict = majority.
- **Stalemate** — 4 rounds without convergence. Debate terminates; findings escalated to user (interactive) or documented as "unresolved" in session log (autonomous).
- **Obvious pass** — round 1 produces unanimous PASS on every criterion with confidence > 0.9 from Grader. Skip Critic + Defender, accept.
- **Obvious fail** — round 1 produces ≥2 critical findings from Critic with tool-verified evidence. Skip remaining rounds, roll back iteration, report.

Typical convergence: 2-3 rounds. Fixed-4-round debate would be ~33% more expensive.

## Model family diversity (hard requirement)

Critic and Defender MUST be different model families. The research is explicit: verification by the same model family shares blind spots.

Valid pairings for our setup:

| Critic | Defender | Notes |
|---|---|---|
| Codex (gpt-5.4) | Claude (Opus/Sonnet) | Default, strongest signal |
| Codex (gpt-5.4) | Gemini (3.1 Pro) | Alternate if Claude budget low |
| Gemini (3.1 Pro) | Claude (Opus/Sonnet) | Alternate if Codex budget low |

Same family on both sides halts the debate with a configuration error.

## Tool access for evidence

Grader, Critic, and Defender all have read access to:

- Repo file tree
- Test output (current + baseline)
- Lint / type-check output
- Git log / blame
- Runtime logs from the L2 "exercise feature" step

No write access except Defender, which can only modify code as part of responding to findings.

## Cost / cadence

Full three-role debate runs on:

- Iteration 1 (baseline establishing)
- Final iteration (ship-quality gate)
- Every 3rd iteration

Smoke audit (single model, rubric-only pass-fail check, no debate) runs on the other iterations. If smoke finds any FAIL, escalate that iteration to full debate.

## Output

At phase end, emit to session log:

```yaml
phase: L3-L4-debate
iteration: 3
rounds: 2
converged: true
ks_distance: 0.032
rubric_entries_evaluated: 10
verdicts:
  - task_id: L2-task-03
    final: PASS
    confidence: 0.94
  - task_id: L2-task-07
    final: FAIL
    reason: "Critic finding #2 (concurrent-write race) not addressed by Defender"
    action: rollback
critic_findings:
  total: 5
  fixed: 3
  rebutted: 1
  deferred: 1
cost_tokens: 342891
```

## Fallback

If three-role debate can't run (e.g., one of the required model families is rate-limited), fall back to the simpler sequential L3→L4 (single Codex audit, single Claude counter-audit) but note the degradation in the session log. Never silently skip the audit phase.
