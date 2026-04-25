"""Prompt template definitions.

Each entry describes a prompt type: its display label, the form fields a user
can tune, and a render function that produces the final prompt string from
the form values.

Templates aim to mirror the canonical strings in
~/repos/octopus-factory/prompts/{factory-loop-prompts.txt,examples.md} so this
GUI never drifts from the curated copy-paste library. When the canonical
prompts change, update render functions here in the same commit.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable


@dataclass
class Field:
    """One form input definition."""

    key: str
    label: str
    kind: str  # "path" | "text" | "int" | "choice" | "checkbox" | "multiline" | "paths"
    default: Any = ""
    choices: list[str] = field(default_factory=list)
    help: str = ""
    placeholder: str = ""
    min_value: int | None = None
    max_value: int | None = None


@dataclass
class Template:
    """A full prompt template — fields + a render fn."""

    key: str
    label: str
    description: str
    fields: list[Field]
    render: Callable[[dict[str, Any]], str]


# ─── Helpers ────────────────────────────────────────────────────────────────

def _flag(value: Any, flag: str) -> str:
    """Return the flag if value is truthy, else empty string."""
    return f" {flag}" if value else ""


def _path(value: Any) -> str:
    """Coerce a path field value, fall back to a placeholder if empty."""
    s = str(value).strip()
    return s or "<PATH>"


# ─── Render functions ──────────────────────────────────────────────────────

def render_factory_loop(v: dict[str, Any]) -> str:
    repo = _path(v.get("repo"))
    iters = v.get("iterations", 4)
    flags = ""
    flags += _flag(v.get("audit_only"), "--audit-only")
    flags += _flag(v.get("skip_preflight"), "--skip-preflight")
    flags += _flag(v.get("skip_scrub"), "--skip-scrub")
    flags += _flag(v.get("manual_scrub"), "--manual-scrub")
    flags += _flag(v.get("skip_wip"), "--skip-wip-adoption")
    flags += _flag(v.get("skip_logo"), "--skip-logo")
    flags += _flag(v.get("force_logo"), "--force-logo")
    flags += _flag(v.get("raster_logo"), "--raster-logo")
    flags += _flag(v.get("plan"), "--plan")
    flags += _flag(v.get("final_codex_pass"), "--final-codex-pass")
    flags += _flag(v.get("require_orchestrator"), "--require-orchestrator")
    flags += _flag(v.get("single_session"), "--single-session")

    preset = v.get("preset", "copilot-heavy")
    preset_swap = ""
    if preset != "copilot-heavy":
        preset_swap = (
            f"\nFirst swap the routing preset:\n"
            f"  bash ~/.claude-octopus/bin/octo-route.sh {preset}\n"
        )

    extra_notes = (v.get("notes") or "").strip()
    if extra_notes:
        extra_notes = f"\n\nAdditional context from the user:\n{extra_notes}\n"

    return f"""Run the factory loop on {repo}. Autonomous mode — decide and proceed,
no clarifying questions. Do substantial work. "Extensive" is the default
setting, not the opt-in.

Follow recipe-factory-loop.md in memory EXACTLY, end-to-end. The recipe is
the source of truth; anything restated below is backstop only.
{preset_swap}
PRE-FLIGHT (run before anything else):
- Invoke `bash ~/repos/octopus-factory/bin/factory-doctor.sh`. Surface the
  output to me ONCE before kicking off. Hard failures (exit 1) halt the run.
  Soft warnings (exit 2) proceed but acknowledge them.

CODEX DISPATCH:
- Audit phases (L3 Critic, U1 UX, T1 theming, Q1 security, Q2 review,
  roadmap-research Phase 5 self-audit) MUST shell out to
  `bash ~/repos/octopus-factory/bin/codex-direct.sh <phase>` for cross-family
  signal. On non-zero exit (auth/quota/timeout/refusal/internal), log the
  degradation and continue with master Claude doing the audit instead.

OFFLOAD POLICY:
- Routing preset is `{preset}`. Bulk research, synthesis, implementation,
  counter-passes, UX, theming, audit all route through Copilot
  Sonnet 4.6 / GPT-5.3-Codex.
- Claude Max (this session) only escalates on PEC UNCERTAIN ≥3, debate
  stalemate, security escalation, or novel architecture.

EXECUTE:
  /octo:factory {repo} --iterations {iters}{flags}

If you hit a genuinely ambiguous fork: stop and ask once. Otherwise proceed.{extra_notes}

Begin."""


def render_overnight(v: dict[str, Any]) -> str:
    repos_raw = v.get("repos", "")
    repos_list = [r.strip() for r in str(repos_raw).split("\n") if r.strip()]
    if not repos_list:
        repos_list = ["<PATH>"]

    duration = v.get("duration", "1h")
    if duration == "custom":
        duration = v.get("custom_duration", "1h").strip() or "1h"

    max_spend = v.get("max_spend_total", 10)
    convergence = v.get("convergence_rotations", 3)
    sleep = v.get("sleep_sec", 60)
    cycle_timeout = v.get("cycle_timeout_sec", 1800)
    no_rotate = v.get("no_rotate", False)
    quiet = v.get("quiet", False)
    fail_fast = v.get("fail_fast", False)
    require_clean = v.get("require_clean_tree", False)
    auto_discover = (v.get("auto_discover") or "").strip()

    repo_args = " \\\n        ".join(f'"{r}"' for r in repos_list)

    flags = ""
    flags += f" --duration {duration}" if duration else ""
    flags += f" --max-spend-total {max_spend}"
    flags += f" --convergence-rotations {convergence}"
    if sleep != 60:
        flags += f" --sleep {sleep}"
    if cycle_timeout != 1800:
        flags += f" --cycle-timeout {cycle_timeout}"
    flags += _flag(no_rotate, "--no-rotate")
    flags += _flag(quiet, "--quiet")
    flags += _flag(fail_fast, "--fail-fast")
    flags += _flag(require_clean, "--require-clean-tree")
    if auto_discover:
        flags += f" --auto-discover {auto_discover}"

    detached = v.get("detached", True)
    pre_flight = """Pre-flight:
1. Run `bash ~/repos/octopus-factory/bin/factory-doctor.sh` and surface the
   summary line. Halt only on hard failures (exit 1). Soft warnings are OK.
2. Confirm the active routing preset is `copilot-heavy`. If not, swap via
   `bash ~/.claude-octopus/bin/octo-route.sh copilot-heavy` first.
3. Confirm every target repo exists, is a git repo, and has a clean OR
   adoptable working tree.
"""

    if detached:
        launch = f"""Launch:
4. Run the wrapper detached so this session can return:
     nohup bash ~/repos/octopus-factory/bin/factory-overnight.sh \\
        {repo_args}{flags} \\
        > /tmp/factory-overnight-launch.log 2>&1 &
   Capture the background PID and the run-id from the wrapper's first
   event-log line.
5. Wait ~10s, then `just overnight --status` to confirm a live session.
   Retry once if the status file isn't ready yet.

Report back:
6. Surface: doctor summary, active preset, PID, run ID, event log path,
   status file path, expected end time, sample monitor/halt commands.
7. Exit cleanly. Do NOT block this session.

If steps 1-5 fail: halt loudly, do NOT silently proceed."""
    else:
        launch = f"""Launch:
4. Run the wrapper foreground so I can watch:
     bash ~/repos/octopus-factory/bin/factory-overnight.sh \\
        {repo_args}{flags}

5. Surface live cycle output as it arrives. End-of-run summary is at
   ~/.claude-octopus/logs/overnight/<run-id>/summary.md."""

    return f"""Launch a {duration} overnight factory run on the repo path(s) above.
Autonomous mode — decide and proceed.

{pre_flight}
{launch}

Begin."""


def render_audit_only(v: dict[str, Any]) -> str:
    repo = _path(v.get("repo"))
    iters = v.get("iterations", 1)
    final_codex = _flag(v.get("final_codex_pass"), "--final-codex-pass")

    return f"""Run the factory loop in audit-only mode on {repo}.
Follow recipe-factory-loop.md. Route audit work through Copilot GPT-5.3-Codex
(copilot-heavy preset). No new features.

Mode semantics: --audit-only skips P*, G-phase, L1/L2, U*, T*. Runs S*
(auto-scrub), L3/L4 (three-role audit debate), L5 (doc drift), L7 (commit
gate), D* (CVE/dep scan), Q* (security → review → release with rollback).

Audit phases (L3, Q1 security, Q2 review) MUST shell out to
bin/codex-direct.sh per the recipe's single-session contract.

  /octo:factory {repo} --iterations {iters} --audit-only{final_codex}

Begin."""


def render_plan(v: dict[str, Any]) -> str:
    repo = _path(v.get("repo"))
    iters = v.get("iterations", 4)

    return f"""Generate the factory plan + cost estimate + expected commit count
for {repo}. Do NOT execute anything. Follow recipe-factory-loop.md's --plan
mode behavior. Include the projected Copilot Premium Request count (research +
implementation + audit) alongside the USD estimate so I can judge quota
impact before kicking off.

  /octo:factory {repo} --iterations {iters} --plan

Begin."""


def render_single_task(v: dict[str, Any]) -> str:
    repo = _path(v.get("repo"))
    task_id = (v.get("task_id") or "").strip() or "<TASK-ID>"

    return f"""Advance task {task_id} in {repo}. Single task, single iteration,
no broader replenish or audit-only sweep.

Read the repo's ROADMAP.md to confirm the task ID exists in the Now or Next
tier. If it's been moved to Rejected since I asked, surface that and stop.

  /octo:factory {repo} --iterations 1 --task {task_id}

L1 research still runs in delta mode (per recipe), but L2 implementation
scopes to the single task. L3 audit fires after.

Begin."""


def render_roadmap_research(v: dict[str, Any]) -> str:
    repo = _path(v.get("repo"))
    commit_after = v.get("commit_after", True)

    commit_step = ""
    if commit_after:
        commit_step = """When done, commit the docs/research/* files + updated ROADMAP.md as
"docs(roadmap): five-phase research pass YYYY-MM-DD" and push.

"""

    return f"""Apply directive-roadmap-research.md to {repo}. Run all 5 phases
end-to-end. Do NOT enter the L2 implementation loop afterward — research-only.

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

{commit_step}Begin."""


def render_release_build(v: dict[str, Any]) -> str:
    repo = _path(v.get("repo"))
    version_override = (v.get("version") or "").strip()
    skip_patch_release = _flag(v.get("skip_patch_release"), "--skip-patch-release")

    version_line = ""
    if version_override:
        version_line = f"\nUser-requested version: {version_override}\n"

    return f"""Apply recipe-release-build.md to {repo}. This is a release-only
run — no feature work, no audit-only sweep. The release recipe handles:
{version_line}
  - Phase 0: version bump detection (major/minor/patch from conventional commits)
  - Phase 1: project type detection (Chrome ext / Python / Android / etc.)
  - Phase 2: type-specific build + sign pipeline
  - Phase 3: SBOM + SLSA L3 provenance + cosign signing + verification gate
  - Phase 4: draft release → artifact smoke test → promote to full release
  - Rollback: if any step fails, delete tag + revert version commit + nuke draft

Read recipe-release-build.md for the full per-stack sign + build details
(CRX3 with .pem, APK with keystore, EXE with Authenticode, etc.).

Pre-flight: confirm `gh` CLI authenticated, signing keys present in their
canonical locations, no uncommitted changes.

  cd {repo}
  ship release{skip_patch_release}

Begin."""


def render_ai_scrub(v: dict[str, Any]) -> str:
    repo = _path(v.get("repo"))
    mode = v.get("mode", "dry-run")
    include_files = v.get("include_files", False)

    mode_line = {
        "dry-run": "Run in DRY-RUN mode first — produce the report only, no rewrites.",
        "apply": "Apply locally only — backup bundle + remote backup branch + filter-repo. Do NOT push yet.",
        "push": "Apply AND push — full pipeline including --force-with-lease push to origin.",
    }.get(mode, "Run in DRY-RUN mode first — produce the report only, no rewrites.")

    files_arg = " --include-files" if include_files else ""

    return f"""Apply recipe-ai-scrub.md to {repo}.

{mode_line}

  bash ~/repos/octopus-factory/bin/ai-scrub.sh {repo} --{mode}{files_arg}

Pre-flight will halt if multi-contributor or signed commits are detected,
forcing manual confirmation. Backup bundle + remote backup branch are
created before any rewrite — rollback always possible via
`rtk git bundle unbundle` or `rtk git checkout pre-ai-scrub-<timestamp>`.

After completion, surface:
- Number of commits rewritten
- Backup bundle path
- Remote backup branch name
- Sample before/after commit message pairs

Begin."""


def render_pdf_redesign(v: dict[str, Any]) -> str:
    pdf_path = _path(v.get("pdf_path"))
    output_dir = (v.get("output_dir") or "").strip()
    style_notes = (v.get("style_notes") or "").strip()

    output_line = ""
    if output_dir:
        output_line = f"\nWrite the improved PDF + editable source + changelog to: {output_dir}\n"

    style_line = ""
    if style_notes:
        style_line = f"\nStyle notes from user:\n{style_notes}\n"

    return f"""Apply recipe-pdf-redesign.md to: {pdf_path}

Discover supporting materials in adjacent dirs, audit the PDF for
readability + structure + visual quality issues, redesign + rewrite,
produce: improved PDF, editable source (Pandoc/Typst/LaTeX as appropriate),
markdown changelog of changes.

The original PDF is NEVER modified. All output goes to a sibling directory
or the user-specified output dir.{output_line}{style_line}
Begin."""


def render_pdf_derivatives(v: dict[str, Any]) -> str:
    source_pdf = _path(v.get("source_pdf"))
    output_dir = (v.get("output_dir") or "").strip()
    mode = v.get("mode", "both")

    output_line = ""
    if output_dir:
        output_line = f"\nWrite all derivatives to: {output_dir}\n"

    mode_phrase = {
        "guides": "Produce STANDALONE SUB-GUIDE PDFs only — skip blog posts.",
        "blogs": "Produce BLOG-READY MARKDOWN POSTS with frontmatter only — skip standalone PDFs.",
        "both": "Produce BOTH standalone sub-guide PDFs AND blog-ready markdown posts.",
    }.get(mode, "Produce BOTH standalone sub-guide PDFs AND blog-ready markdown posts.")

    return f"""Apply recipe-pdf-derivatives.md to: {source_pdf}

{mode_phrase}

Survey the source PDF, write an INVENTORY of candidate extracts, reject
thin or invention-dependent topics, then produce derivatives for the
viable candidates only.

The source PDF is NEVER modified.{output_line}
Begin."""


# ─── Template registry ─────────────────────────────────────────────────────

TEMPLATES: dict[str, Template] = {
    "factory_loop": Template(
        key="factory_loop",
        label="Factory Loop (interactive)",
        description="Single-invocation factory run — you watch in this Claude session.",
        fields=[
            Field("repo", "Project directory", "path", placeholder="~/repos/<NAME>",
                  help="Absolute path to the target repo."),
            Field("iterations", "Iterations", "int", default=4, min_value=1, max_value=7,
                  help="Loop iterations (recipe caps at 7 absolute max)."),
            Field("preset", "Routing preset", "choice", default="copilot-heavy",
                  choices=["copilot-heavy", "balanced", "claude-heavy", "codex-heavy",
                           "direct-only", "copilot-only"],
                  help="copilot-heavy is canonical (preserves Claude Max quota)."),
            Field("audit_only", "Audit-only (no new features)", "checkbox", default=False),
            Field("skip_preflight", "Skip preflight (existing repo)", "checkbox", default=False,
                  help="Auto-detected if repo has .git — usually leave unchecked."),
            Field("skip_scrub", "Skip S-phase (AI-reference history scrub)", "checkbox",
                  default=False),
            Field("manual_scrub", "Manual scrub (interactive confirmation)", "checkbox",
                  default=False),
            Field("skip_wip", "Skip W-phase WIP adoption", "checkbox", default=False),
            Field("skip_logo", "Skip G-phase (logo generation)", "checkbox", default=False),
            Field("force_logo", "Force logo regen (archives existing icons)", "checkbox",
                  default=False),
            Field("raster_logo", "Use gpt-image-1 (skip Copilot SVG path)", "checkbox",
                  default=False, help="Only for photographic / complex briefs."),
            Field("final_codex_pass", "Direct Codex audit on final iter", "checkbox",
                  default=False, help="Release-day high-signal audit; burns ChatGPT Pro quota."),
            Field("plan", "--plan (preview only, no execution)", "checkbox", default=False),
            Field("require_orchestrator", "Require orchestrator (no single-session fallback)",
                  "checkbox", default=False),
            Field("single_session", "Force single-session", "checkbox", default=False),
            Field("notes", "Additional context for Claude (optional)", "multiline", default="",
                  help="Anything you want surfaced to the agent — version target, known gotchas, etc."),
        ],
        render=render_factory_loop,
    ),

    "overnight": Template(
        key="overnight",
        label="Overnight Loop (multi-hour)",
        description="External wrapper — multi-cycle round-robin across one or more repos.",
        fields=[
            Field("repos", "Project directories (one per line)", "paths",
                  placeholder="~/repos/Astra-Deck\n~/repos/NovaCut",
                  help="One path per line. Multiple repos = round-robin."),
            Field("duration", "Duration", "choice", default="1h",
                  choices=["1h", "2h", "4h", "8h", "weekend (48h)", "custom"]),
            Field("custom_duration", "Custom duration (e.g. 90m, 12h)", "text", default="",
                  help="Only used when Duration = custom."),
            Field("max_spend_total", "Max spend total (USD)", "int", default=10,
                  min_value=1, max_value=500),
            Field("convergence_rotations", "Convergence rotations", "int", default=3,
                  min_value=1, max_value=10,
                  help="Repo retires after N consecutive no-op cycles."),
            Field("sleep_sec", "Sleep between cycles (sec)", "int", default=60,
                  min_value=0, max_value=600),
            Field("cycle_timeout_sec", "Per-cycle timeout (sec)", "int", default=1800,
                  min_value=300, max_value=10800),
            Field("auto_discover", "Auto-discover dir (depth=1 git repos)", "path",
                  default="", placeholder="~/repos",
                  help="Optional — adds every git repo under this dir."),
            Field("no_rotate", "No round-robin (finish each repo before next)", "checkbox",
                  default=False),
            Field("quiet", "Quiet (suppress live cycle output)", "checkbox", default=False),
            Field("fail_fast", "Fail-fast (abort on first non-zero cycle)", "checkbox",
                  default=False),
            Field("require_clean_tree", "Require clean tree (no uncommitted changes)",
                  "checkbox", default=False),
            Field("detached", "Launch detached (Claude exits after launch)", "checkbox",
                  default=True,
                  help="On = nohup background launch. Off = run foreground in this session."),
        ],
        render=render_overnight,
    ),

    "audit_only": Template(
        key="audit_only",
        label="Audit-Only Pass",
        description="Security + quality review before release. No new features.",
        fields=[
            Field("repo", "Project directory", "path", placeholder="~/repos/<NAME>"),
            Field("iterations", "Iterations", "int", default=1, min_value=1, max_value=3),
            Field("final_codex_pass", "Add direct Codex audit on final iter",
                  "checkbox", default=False),
        ],
        render=render_audit_only,
    ),

    "plan": Template(
        key="plan",
        label="Plan / Dry-Run Preview",
        description="Preview cost + commits + plan without executing anything.",
        fields=[
            Field("repo", "Project directory", "path", placeholder="~/repos/<NAME>"),
            Field("iterations", "Iterations to plan for", "int", default=4,
                  min_value=1, max_value=7),
        ],
        render=render_plan,
    ),

    "single_task": Template(
        key="single_task",
        label="Single Task (one ROADMAP item)",
        description="Scope to advancing one specific task ID.",
        fields=[
            Field("repo", "Project directory", "path", placeholder="~/repos/<NAME>"),
            Field("task_id", "Task ID (from ROADMAP.md)", "text",
                  placeholder="V8-04 / S-02 / T1.5"),
        ],
        render=render_single_task,
    ),

    "roadmap_research": Template(
        key="roadmap_research",
        label="Roadmap Research (no implementation)",
        description="Five-phase research pass that builds/expands ROADMAP.md without coding.",
        fields=[
            Field("repo", "Project directory", "path", placeholder="~/repos/<NAME>"),
            Field("commit_after", "Commit + push research artifacts when done",
                  "checkbox", default=True),
        ],
        render=render_roadmap_research,
    ),

    "release_build": Template(
        key="release_build",
        label="Release Build",
        description="Version bump + sign + GitHub Release with artifact smoke test.",
        fields=[
            Field("repo", "Project directory", "path", placeholder="~/repos/<NAME>"),
            Field("version", "Version override (optional)", "text", default="",
                  placeholder="vX.Y.Z (leave blank to auto-detect from commits)"),
            Field("skip_patch_release", "Skip GitHub Release on patch bumps", "checkbox",
                  default=False, help="Patch bumps still commit + push, just no Release."),
        ],
        render=render_release_build,
    ),

    "ai_scrub": Template(
        key="ai_scrub",
        label="AI Scrub (git history rewrite)",
        description="Remove AI attribution from git history. Backup-enforced, dry-run default.",
        fields=[
            Field("repo", "Project directory", "path", placeholder="~/repos/<NAME>"),
            Field("mode", "Mode", "choice", default="dry-run",
                  choices=["dry-run", "apply", "push"],
                  help="Always start with dry-run. Push is irreversible."),
            Field("include_files", "Also purge CLAUDE.md / .claude/ / CODEX_CHANGELOG.md",
                  "checkbox", default=False),
        ],
        render=render_ai_scrub,
    ),

    "pdf_redesign": Template(
        key="pdf_redesign",
        label="PDF Redesign",
        description="Improve a single PDF's readability + structure + visual quality.",
        fields=[
            Field("pdf_path", "PDF path", "path", placeholder="~/Desktop/document.pdf"),
            Field("output_dir", "Output dir (optional)", "path", default="",
                  placeholder="(leave blank for sibling directory)"),
            Field("style_notes", "Style notes (optional)", "multiline", default="",
                  help="Tone / audience / brand constraints to honor."),
        ],
        render=render_pdf_redesign,
    ),

    "pdf_derivatives": Template(
        key="pdf_derivatives",
        label="PDF Derivatives (mine for sub-guides + blog posts)",
        description="Extract standalone sub-guide PDFs + blog posts from a long-form PDF.",
        fields=[
            Field("source_pdf", "Source PDF", "path", placeholder="~/Desktop/long-guide.pdf"),
            Field("output_dir", "Output dir (optional)", "path", default=""),
            Field("mode", "Mode", "choice", default="both",
                  choices=["both", "guides", "blogs"],
                  help="both = sub-PDFs + blog posts. guides = sub-PDFs only. blogs = MD only."),
        ],
        render=render_pdf_derivatives,
    ),
}


def get_template(key: str) -> Template:
    return TEMPLATES[key]


def list_templates() -> list[Template]:
    return list(TEMPLATES.values())
