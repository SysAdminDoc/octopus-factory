# Prompt examples

Ready-to-use prompts for common scenarios. Each example has:

- **When to use** — the situation it fits
- **Setup** — say this to Claude before pasting (e.g. naming the target repo)
- **Prompt** — the full body to copy-paste
- **What you'll see** — expected outcome + how to monitor

For the canonical long-form factory prompt + audit-only / plan / final-codex-pass / overnight variants, see [`factory-loop-prompts.txt`](factory-loop-prompts.txt). This file is curated example combinations, not a replacement.

---

## 1 — 1-hour unattended run on a single repo

**When to use:** You have an hour to spare (lunch, school run, errand) and want the factory to make progress on one specific repo. Detached — Claude exits after launch.

**Setup:** `Run a 1-hour overnight on ~/repos/<NAME>`

**Prompt:**

```
Launch a 1-hour overnight factory run on the repo path I just gave you.
Autonomous mode — decide and proceed.

Pre-flight:
1. Run `bash ~/repos/octopus-factory/bin/factory-doctor.sh` and surface the
   summary line. Halt only on hard failures (exit 1). Soft warnings (exit 2)
   are OK — note them and proceed.
2. Confirm the active routing preset is `copilot-heavy`. If not, swap via
   `bash ~/.claude-octopus/bin/octo-route.sh copilot-heavy` first.
3. Confirm the target repo exists, is a git repo, and has a clean OR
   adoptable working tree.

Launch:
4. Run the wrapper detached:
     nohup bash ~/repos/octopus-factory/bin/factory-overnight.sh \
         <THE_PATH_I_GAVE_YOU> \
         --duration 1h \
         --max-spend-total 10 \
         --convergence-rotations 3 \
         > /tmp/factory-overnight-launch.log 2>&1 &
   Capture the background PID and the run-id from the wrapper's first
   event-log line.
5. Wait ~10s, then `just overnight --status` to confirm a live session.
   Retry once if the status file isn't ready yet.

Report back:
6. Surface: doctor summary, active preset, PID, run ID, event log path,
   status file path, expected end time, sample monitor/halt commands.
7. Exit cleanly. Do NOT block this session.

If steps 1-5 fail: halt loudly, do NOT silently proceed.

Begin.
```

**What you'll see:** 2-3 cycles (~25-30 min each), atomic per-task commits + push, ROADMAP grows from research, `state.yaml` gains `cycle_outcome` lines. Monitor with `just overnight --status` or `tail -f ~/.claude-octopus/logs/overnight/<run-id>/overnight.log`.

---

## 2 — Overnight run on a single repo (8 hours)

**When to use:** Kick off before bed, see progress in the morning. Single focused repo, deep work.

**Setup:** Open a terminal that survives logout (Windows Terminal that stays open, tmux, screen).

**Prompt:** None — run directly from the terminal:

```bash
just overnight ~/repos/<NAME> --until 06:00 --max-spend-total 40
```

Or with explicit duration:

```bash
just overnight ~/repos/<NAME> --duration 8h --max-spend-total 40
```

**What you'll see:** ~15-20 cycles. On smaller repos, convergence-rotation typically retires the repo somewhere between cycle 8-20 and the wrapper exits early. Larger repos keep producing through the full 8 hours. Summary at `~/.claude-octopus/logs/overnight/<run-id>/summary.md`.

---

## 3 — Multi-repo round-robin overnight

**When to use:** You have 3-5 repos that all need attention. Wrapper rotates: cycle 1 = repo A, cycle 2 = repo B, etc. When repo X reports `no-op` 3 cycles in a row, it retires.

**Prompt:** None — run from terminal:

```bash
just overnight \
    ~/repos/Astra-Deck \
    ~/repos/NovaCut \
    ~/repos/StreamKeep \
    --duration 8h \
    --max-spend-total 50
```

**What you'll see:** Each repo gets ~5-7 cycles depending on convergence behavior. Total wrapper events log shows the rotation pattern. Per-repo summary in the end-of-run brief tells you which repo absorbed the most work.

---

## 4 — Full weekend autopilot (48 hours, multi-repo)

**When to use:** Friday evening to Sunday night. You're away, the factory drains everything it can.

**Prompt:** None — run from a terminal that survives 48 hours (cloud server, NUC, whatever you have that stays online):

```bash
just overnight \
    ~/repos/<A> \
    ~/repos/<B> \
    ~/repos/<C> \
    ~/repos/<D> \
    ~/repos/<E> \
    --duration 48h \
    --max-spend-total 200 \
    --max-cycles 100 \
    --convergence-rotations 4
```

**What you'll see:** ~80-100 cycles distributed across 5 repos. Most repos converge before the 48h mark. Halt early at any time with `just overnight --stop`. The wrapper writes a status file every cycle so you can `cat ~/.factory-overnight.status` from any terminal to see live progress.

---

## 5 — Single-pass interactive run (no detach, you watch)

**When to use:** You want to actually watch the factory work, intervene if it goes sideways. Single iteration, ~15-30 min.

**Setup:** `Run the factory loop on ~/repos/<NAME>`

**Prompt:** Use the full canonical prompt from [`factory-loop-prompts.txt`](factory-loop-prompts.txt) — the `THE ONLY PROMPT YOU NEED` section. That prompt blocks the session for the duration of one full iteration.

**What you'll see:** Recipe walks through every phase in this Claude session, surfacing each step. Slower than overnight cycles (no parallel dispatch) but you see everything as it happens.

---

## 6 — Audit-only pass before a release

**When to use:** Code is feature-complete, you want a thorough security + quality review before tagging the release. No new features, no UX changes.

**Setup:** `Run an audit-only factory pass on ~/repos/<NAME>`

**Prompt:**

```
Run the factory loop in audit-only mode on the repo path I just gave you.
Follow recipe-factory-loop.md. Route audit work through Copilot GPT-5.3-Codex
(copilot-heavy preset). Single iteration; no new features.

Mode semantics from the recipe:
  --audit-only skips P*, G-phase, L1/L2, U*, T*. Runs S* (auto-scrub),
  L3/L4 (three-role audit debate), L5 (doc drift), L7 (commit gate),
  D* (CVE/dep scan), Q* (security → review → release with rollback).

Audit phases (L3, Q1 security, Q2 review) MUST shell out to
bin/codex-direct.sh per the recipe's single-session contract.

  /octo:factory <THE_PATH_I_GAVE_YOU> --iterations 1 --audit-only

Begin.
```

**What you'll see:** Real cross-family audit signal (Codex GPT-5.4 critic + Claude defender), CVE scan, security pass, final review pass, release preparation. No feature work. Findings get committed as fixes; if a finding is too large to fix in this run, it lands as a `Now`-tier item in ROADMAP.md instead.

---

## 7 — Dry-run plan preview (no execution)

**When to use:** You want to know what the factory WOULD do, what it'll cost, how many commits to expect — without spending tokens.

**Setup:** `Plan a factory run on ~/repos/<NAME>`

**Prompt:**

```
Generate the factory plan + cost estimate + expected commit count for the
repo path I just gave you. Do NOT execute anything. Follow
recipe-factory-loop.md's --plan mode behavior. Include the projected
Copilot Premium Request count (research + implementation + audit) alongside
the USD estimate so I can judge quota impact.

  /octo:factory <THE_PATH_I_GAVE_YOU> --iterations 4 --plan

Begin.
```

**What you'll see:** Per-phase forecast with expected token usage, commit count, gates that will fire, projected runtime. No commits, no pushes, no token burn beyond planning itself (~$0.05).

---

## 8 — Single-task scoped run

**When to use:** You want the factory to advance ONE specific ROADMAP item. Quick, focused.

**Setup:** `Advance task <TASK-ID> in ~/repos/<NAME>` (substitute the actual task ID from the repo's ROADMAP.md)

**Prompt:**

```
Advance the named task in the repo path I just gave you. Single task,
single iteration, no broader replenish or audit-only sweep.

Read the repo's ROADMAP.md to confirm the task ID exists in the Now or Next
tier. If it's been moved to Rejected since I asked, surface that and stop.

  /octo:factory <THE_PATH_I_GAVE_YOU> --iterations 1 --task <TASK-ID>

L1 research still runs in delta mode (per recipe), but L2 implementation
scopes to the single task. L3 audit fires after.

Begin.
```

**What you'll see:** PEC rubric written to `.factory/rubrics/<TASK-ID>.yaml`, implementation, build + tests, audit, atomic commit + push. ~10-20 min.

---

## 9 — Roadmap research only (no implementation)

**When to use:** You want a fresh comprehensive roadmap built but not implemented. Useful when you're about to plan a sprint and need a deep external scan to inform priorities.

**Setup:** `Run roadmap research on ~/repos/<NAME>`

**Prompt:**

```
Apply directive-roadmap-research.md to the repo path I just gave you. Run
all 5 phases end-to-end. Do NOT enter the L2 implementation loop afterward
— this is research-only.

  Phase 0: repo recon → docs/research/iter-1-state-of-repo.md
  Phase 1: external research, 30-60 source floor, 9 source classes →
           sources.md + landscape.md
  Phase 2: quantity-first feature harvesting (80-200+ raw items) →
           harvest.md
  Phase 3: 6-dim scoring + 5-tier bucketing → scored.md
  Phase 4: author/reconcile ROADMAP.md (preserve useful, supersede outdated)
  Phase 5: 7-check adversarial self-audit on different model family →
           audit.md

Routing: copilot-heavy (gemini:flash for breadth, copilot-sonnet for depth +
synth, copilot-codex for the cross-family Phase 5 audit). Halt only if
Phase 5 fails cleanly after 3 rework rounds.

When done, commit the docs/research/* files + updated ROADMAP.md as
"docs(roadmap): five-phase research pass YYYY-MM-DD" and push.

Begin.
```

**What you'll see:** ~30-60 min depending on repo scope. Comprehensive ROADMAP.md with Now/Next/Later/Under Consideration/Rejected sections + Appendix of every source URL. Five artifact files in `docs/research/`.

---

## 10 — Ship a release on a repo that's ready

**When to use:** You've been shipping commits to main, you want to cut a release with proper version bumping, signing, GitHub Release, artifact smoke test, and rollback if anything fails.

**Setup:** `Cut a release on ~/repos/<NAME>`

**Prompt:**

```
Apply recipe-release-build.md to the repo path I just gave you. This is a
release-only run — no feature work, no audit-only sweep. The release recipe
handles:

  - Phase 0: version bump detection (major/minor/patch from conventional commits)
  - Phase 1: project type detection (Chrome ext / Python / Android / etc.)
  - Phase 2: type-specific build + sign pipeline
  - Phase 3: SBOM + SLSA L3 provenance + cosign signing + verification gate
  - Phase 4: draft release → artifact smoke test → promote to full release
  - Rollback: if any step fails, delete tag + revert version commit + nuke draft

Read recipe-release-build.md for the full per-stack sign + build details
(CRX3 with .pem, APK with keystore, EXE with Authenticode, etc.).

Pre-flight: confirm `gh` CLI authenticated, signing keys present in their
canonical locations, no uncommitted changes (W-phase will halt if dirty).

Begin.
```

**What you'll see:** Version bumped across every manifest / README / CHANGELOG / @version string, atomic commit, tag + push, GitHub Release created with all artifacts attached, smoke test verifies each artifact loads, install instructions in release notes. Rollback on any failure.

---

## 11 — Cleanup: scrub AI references from a repo's git history

**When to use:** You forked or inherited a repo whose git history has `Co-Authored-By: Claude` trailers, "Generated with Claude Code" signatures, or `.claude/` artifacts you want to remove before making the repo public.

**Setup:** `Scrub AI references from ~/repos/<NAME>`

**Prompt:** See [`ai-scrub-prompts.txt`](ai-scrub-prompts.txt) — has the canonical 7-phase scrub prompt with backup-enforced workflow.

---

## 12 — Doctor + status only (no run)

**When to use:** You want a quick environment check before kicking off a longer run, or you want to see what an active overnight session is doing.

**Prompt:** None — run from terminal:

```bash
# Environment check
just doctor

# Active overnight session status
just overnight --status

# Live event log for an in-flight session
tail -f ~/.claude-octopus/logs/overnight/*/overnight.log

# What does the active preset route each phase to?
just doctor --route-only
```

---

## 13 — Halt a running overnight session cleanly

**When to use:** A long-running session is going off-track, OR you need to free up cost budget for something else.

**Prompt:** None — run from terminal:

```bash
just overnight --stop
```

The wrapper finishes its current cycle, writes the summary, releases the lockfile, and exits. The next cycle never starts. Atomic — no partial commits left dangling.

---

## 14 — Routing-preset experiment (compare audit signal across modes)

**When to use:** You suspect Codex GPT-5.4 is catching things Copilot's GPT-5.3-Codex misses (or vice versa) and want to A/B test on the same repo.

**Prompt:**

```
Run the same audit-only pass on the repo path I just gave you THREE times,
once per preset, capturing each pass's audit findings to a separate file.

Pass 1 — copilot-heavy (Copilot GPT-5.3-Codex via shell-out):
  octo-route.sh copilot-heavy
  /octo:factory <PATH> --iterations 1 --audit-only
  Save findings to /tmp/audit-copilot-heavy.md

Pass 2 — balanced (direct Codex CLI for review/security):
  octo-route.sh balanced
  /octo:factory <PATH> --iterations 1 --audit-only
  Save findings to /tmp/audit-balanced.md

Pass 3 — codex-heavy (all audit phases via direct Codex):
  octo-route.sh codex-heavy
  /octo:factory <PATH> --iterations 1 --audit-only
  Save findings to /tmp/audit-codex-heavy.md

Restore copilot-heavy at the end:
  octo-route.sh copilot-heavy

Diff the three findings files and surface deltas — what each preset caught
that the others missed. This is the experimental signal that informs
whether to invest direct-ChatGPT-Pro quota on a routine basis.

Begin.
```

**What you'll see:** Three audit reports + a delta analysis. Burns ~3x normal cost; only run when you genuinely want to calibrate routing.

---

## Notes on cost and quota

| Run shape | Typical cost | Quota burned |
|---|---|---|
| 1-hour overnight (1 repo) | $5-10 | Copilot Premium (~30-60 requests) |
| 8-hour overnight (1 repo) | $30-50 | Copilot Premium (~150-300 requests) |
| 8-hour overnight (3 repos) | $40-60 | Copilot Premium (~200-350 requests) |
| Audit-only single pass | $1-3 | ChatGPT Pro Codex (1-2 calls) + Copilot Premium (~10) |
| Roadmap research only | $1-2 | Gemini Flash (free tier) + Copilot Premium (~20) + ChatGPT Pro (1 self-audit) |
| Release-only (Q3 stack) | $0.50-2 | Mostly local — signing + build + gh CLI |
| Single-task scoped | $1-3 | Copilot Premium (~10-20 requests) |

These are rough — actual costs depend on repo size, ROADMAP depth, and how much research the L1 phase finds.

## Pre-flight checklist for any unattended run

```bash
just doctor                          # green or only-warnings
just hooks-install                   # one-time, blocks bad commits
ls ~/.factory-overnight.lock         # should NOT exist (no other session running)
df -h ~                              # at least 1GB free for logs
```

If any of these fail, fix before launching. The factory's commit gate + secret scan are always-on, but the doctor catches routing pitfalls those gates can't.
