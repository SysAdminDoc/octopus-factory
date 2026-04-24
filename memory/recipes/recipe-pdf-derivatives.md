---
name: PDF Derivatives Recipe
description: Content-mining pipeline for extracting standalone smaller guides and blog posts from a larger PDF (or folder of PDFs). Surveys source material, proposes a derivative inventory, produces focused sub-guide PDFs + blog-ready markdown posts. Preserves meaning + attribution, no fabrication. Originals never modified.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
---
# PDF Derivatives Recipe

Mines one large PDF (or a folder of PDFs) for content that can be productively repackaged into:
- **Standalone sub-guides** (shorter, focused PDFs covering one topic from the parent)
- **Blog posts** (markdown-ready articles with frontmatter, tags, dek, CTA back to the parent)

Source material is never modified. Derivatives live in a `derivatives/` subfolder with a master index.

## Invoke

Trigger phrases:
- **"extract derivatives from the PDF at &lt;path&gt;"**
- **"mine PDFs in &lt;dir&gt; for guides and blog posts"**
- **"pull blog posts from &lt;path&gt;"**

Copy the prompt from `~/repos/ai-prompts/pdf-derivatives-prompts.txt` and paste.

## Directive (followed end-to-end)

Act as **senior content strategist + editorial director + technical writer + SEO-aware blog editor**.

**Goal:** Identify content in the source PDFs that is valuable enough to stand alone. Produce polished derivative sub-guides and blog posts. Preserve meaning, attribute source, no invention.

### Phase 1 — Survey

Scan the target path (single PDF or folder) and any subdirectories for:
- PDFs (primary sources)
- Supporting materials: Word docs, markdown, text, decks, spreadsheets, images, diagrams, logos, brand assets, notes

Read each primary PDF. Map:
- Document type + audience + tone + voice
- Top-level structure + section-level structure
- Self-contained chapters / how-tos / process docs / case studies / FAQs / checklists / reference material
- Opinionated passages / myth-busting / problem-solution narratives / listicles / executive summaries
- Brand cues: logos, typography, accent colors, iconography

### Phase 2 — Derivative Inventory

Propose (write to `derivatives/INVENTORY.md` before producing any output) a list of candidates. For each candidate, record:

- **Title** (final, not placeholder)
- **Type** (sub-guide | blog post)
- **Source** (parent PDF path + page range or section name)
- **Audience** (who this specifically serves)
- **Angle** (the single thesis / question / job-to-be-done)
- **Est. length** (sub-guide: pages; blog post: word count)
- **Standalone effort** (low / med / high — how much rewriting is needed for it to make sense without the parent)
- **Value rationale** (one line — why this is worth publishing separately, not just a copy-paste)

**Candidate filters — include if:**
- Topic has a clear, focused thesis
- A reader who never sees the parent would still benefit
- Reshaping improves reach (shorter format, new audience, different platform)

**Reject if:**
- Content only makes sense in parent context
- Rewriting would require invention or speculation
- Topic is too thin to stand alone
- Duplicate of another candidate

### Phase 3 — Production

Create a clean `derivatives/` folder next to the source(s):

```
<source-folder>/
  derivatives/
    guides/
      <slug>.pdf
      <slug>_editable.<ext>
    blog/
      <slug>.md
    INVENTORY.md
    INDEX.md
```

**Sub-guides** (PDF output):
- Standalone — port in enough context from the parent that a fresh reader can follow
- Polished layout: strong cover, clean typography, consistent hierarchy, tasteful callouts
- Shorter than the parent — focused on one topic or workflow
- Include a "Learn more in the full guide" pointer to the parent (title + section reference)
- Use the same design / brand cues as the parent when present; infer a minimal professional system if not
- Editable source alongside each PDF (best practical format for the environment; do not claim editability if flattened)

**Blog posts** (markdown output with frontmatter):
```markdown
---
title: <Final title, not placeholder>
slug: <url-safe-slug>
date: <YYYY-MM-DD>
author: <from source or directory context>
tags: [<3-6 relevant tags>]
summary: <1-2 sentence dek>
source_pdf: <parent filename>
source_section: <section name or page range>
reading_time: <minutes>
hero_image_suggestion: <what an appropriate hero would show — do not fabricate a file reference>
---

<Opening hook — not a generic intro>

<Body — structured with H2/H3 subheads, short paragraphs, bulleted lists where natural>

<Closing CTA linking back to the full guide>
```

Blog post standards:
- Target 800-2000 words unless the source genuinely warrants more or less
- Opinionated where the source is opinionated; neutral where it's reference
- No corporate filler ("in today's fast-paced world")
- Concrete examples preserved from the source
- Every claim traceable to the source PDF — no invention

**INDEX.md** — master catalog of all derivatives produced, with one line per output:
```markdown
## Guides
- [Title](guides/slug.pdf) — one-line dek | from: parent.pdf §2.3
## Blog Posts
- [Title](blog/slug.md) — one-line dek | from: parent.pdf §4
```

## Non-Negotiable Rules

- **Never modify source PDFs.** All output lives in `derivatives/`.
- **Never invent** facts, statistics, quotes, case studies, or examples not present in the source.
- **Attribute every derivative** back to the parent PDF + specific section/page.
- **Preserve technical correctness** — don't simplify accuracy out of existence.
- **No silent content drops** — if you decide a warning or disclaimer belongs in a sub-guide, include it.
- **No brand fabrication.** Reuse nearby logos/colors/typography. Infer minimal professional system if none exist. Don't invent conflicting identity.
- **Source conflicts:** note in INVENTORY.md, don't guess.
- **Image-based PDFs:** extract structurally first, OCR if needed, validate against pages.
- **Work autonomously** — don't ask unnecessary questions. Make grounded editorial decisions.

## Quality Gates

Before marking any derivative as done, verify:

**Sub-guides:**
- A reader who never sees the parent can follow it
- Design is clean, restrained, professional — suitable for real stakeholders
- Cover, hierarchy, typography, spacing, page rhythm, tables all polished
- Learn-more pointer to parent is present and accurate

**Blog posts:**
- Opens with a real hook (not a generic intro)
- Every claim is sourceable in the parent
- Tags + slug + summary are accurate and useful
- CTA to parent guide is present and specific (names the full guide + what the reader gets from it)
- Reads like a human wrote it — no filler, no corporate hedging

## Writing + Editing Standards

- Preserve source voice + tone unless clearly weak
- Tighten, don't pad
- Keep terminology consistent with the parent
- Concrete over abstract — use source's examples
- One thesis per piece — no kitchen-sink extracts

## Decision-Making

- Assertive editorial judgment, grounded in source material
- Favor fewer high-quality derivatives over many thin ones
- Reject candidates that only survive by padding or invention
- Prefer clarity over cleverness
- Prefer faithful repurposing over speculative expansion

## Quality Bar

Real publishing-grade derivatives — sub-guides someone would pay for, blog posts an editor would approve. Not content-farm output. If a candidate can't clear that bar, cut it from the inventory.
