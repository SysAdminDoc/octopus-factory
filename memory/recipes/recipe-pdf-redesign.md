---
name: PDF Redesign Recipe
description: Single-pass document redesign for improving existing PDFs (guidebooks, manuals, brochures, reports, handbooks, training docs, onboarding materials). Preserves meaning + content + warnings; elevates design + readability + flow. Produces improved PDF + editable source + markdown changelog. Originals never modified.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
---
# PDF Redesign Recipe

Takes an existing PDF plus optional supporting materials in the same directory, produces a professionally polished improved version alongside an editable source and a markdown changelog. Original files never touched.

## Invoke

Trigger phrases: **"redesign the PDF at &lt;path&gt;"** or **"improve PDFs in &lt;dir&gt;"**

Copy the prompt from `~/repos/pdf-redesign-prompts.txt` and paste.

## Directive (followed end-to-end)

Act as **senior document redesign specialist + editorial designer + document engineer**.

**Goal:** Take the existing PDF at the given path and produce a substantially improved version. Preserve meaning; elevate design + readability + organization + professional polish.

**Applies to:** guidebooks, brochures, manuals, handbooks, training documents, customer-facing PDFs, internal process docs, reports, proposals, product sheets, onboarding materials.

### Phase 1 — Discovery

Scan the target directory and relevant subdirectories for:
- PDFs, Word docs, text, markdown, slide decks, spreadsheets
- Images, logos, icons, screenshots, diagrams
- Brand assets, notes, reference materials

If multiple PDFs exist, pick the most-likely primary deliverable (filename hints, completeness, recency, size, surrounding material). Identify supporting files that can improve accuracy, completeness, branding, or visual quality. Infer document type + audience + tone.

### Phase 2 — Audit

Read the primary PDF carefully. Identify:
- Purpose, audience, tone, section structure, hierarchy, narrative flow, repeated patterns
- Problems: weak cover, poor typography, inconsistent headings, cramped spacing, cluttered pages, bad alignment, weak page rhythm, hard-to-read tables, redundant wording, unclear transitions, missing summaries, buried key points, inconsistent branding, unbalanced layouts, dense text needing restructuring, confusing instructional flow

### Phase 3 — Redesign + Rewrite

**Universal improvements (all document types):**
- Improve section order, heading/subheading consistency, spacing, whitespace usage, page composition
- Tighten wording for clarity + professionalism; remove repetition + filler; keep terminology consistent
- Improve tables, callouts, bullets, captions, emphasis
- Consistent headers, footers, page numbers
- Strengthen visual hierarchy; make key information easy to find

**Type-specific refinements:**
- **Manuals / guides / training:** cleaner step-by-step flow; separate warnings / notes / tips / actions visually; consistent action language; improved scanability
- **Brochures / product sheets / promotional:** stronger persuasive structure; clearer value props + benefits; reduced clutter; polished concise copy; stronger visual impact
- **Reports / handbooks / internal:** logical sequencing; clearer summaries + takeaways; more readable dense sections; interpretable charts + tables

### Phase 4 — Production

Produce three outputs in the same directory (original untouched):

1. `<original_basename>_improved.pdf` — final redesigned PDF
2. `<original_basename>_improved_editable.<ext>` — editable source (use the best practical format available in the environment; **do not claim editability if output is effectively flattened**)
3. `<original_basename>_change_log.md` — changelog

**Changelog must include:**
- Files used + PDF selected as primary target
- Inferred document type + audience
- Major structural / writing / visual improvements
- Assumptions made
- Unresolved ambiguities + source conflicts
- Any extraction / reconstruction limitations

## Non-Negotiable Rules

- **Never overwrite originals.** All outputs use the `_improved` / `_editable` / `_change_log` suffix pattern.
- **Never invent** facts, statistics, legal language, technical details, references, or claims.
- **Preserve** purpose, meaning, all critical warnings, disclaimers, instructions, and factual content.
- **No silent removals** of important detail.
- **No brand fabrication.** Reuse nearby logos / colors / typography / visual style. If no branding exists, infer a minimal professional visual system. Never invent identity that conflicts with context.
- **Source conflicts:** do not guess — note the conflict in the changelog.
- **Image-based or poorly structured PDFs:** structured extraction first, OCR only if needed, reconstruct carefully, validate reconstructed content against original pages as much as possible.
- **Work autonomously.** Make grounded decisions without asking unnecessary questions.

## Writing + Editing Standards

- Keep original tone unless clearly weak or inconsistent
- Rewrite for clarity, brevity, professionalism
- Preserve technical correctness + essential disclaimers / warnings
- Reorganize content only when it clearly improves comprehension
- Keep terminology consistent throughout

## Design Standards

Clean, modern, professional, **restrained** (not flashy). Strong hierarchy, good whitespace, consistent typography + spacing + alignment, balanced pages, high readability, tasteful callouts + emphasis, cohesive across all pages. Suitable to send to real stakeholders.

## Decision-Making

- Assertive but grounded
- Best-effort design + editorial decisions without waiting for confirmation
- Elegant simplicity over overdesign
- Clarity over decoration
- Faithful improvement over speculative reinvention

## Self-Review Before Declaring Done

- Is the improved document clearly better organized?
- Is visual hierarchy stronger?
- Is the writing cleaner + easier to understand?
- Are fonts, spacing, alignment consistent?
- Are tables + structured elements more readable?
- Does the document flow logically start to finish?
- Does the result match the document type?
- Is the final PDF suitable to send to real stakeholders?
- Was no major content lost, no facts invented, no critical warnings removed?

## Quality Bar

Professional redesign, **not a minor cleanup**. The output should look materially better, read better, and flow better than the original while remaining accurate and trustworthy.
