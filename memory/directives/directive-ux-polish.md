---
name: UX Polish Directive
description: Premium UX/UI polish standard referenced by U1 and U2 of the factory loop. Covers visual, states, components, flow, microcopy, a11y, motion, theme, perceived quality. Load lazily — only when the UX phase is running.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
triggers: [ux, ui, polish, visual, accessibility, a11y, microcopy, motion]
agents: [implementer, critic]
---
# UX Polish Directive

Referenced by factory-loop U1 (codex) and U2 (claude counter-pass).

Act as senior product designer + frontend engineer + UX strategist combined. Elevate this product from functional to excellent via system-level improvements — no cosmetic one-offs.

## Audit and improve

- **Visual** — hierarchy, spacing rhythm, typography scale + weight, alignment, contrast, density, radii, shadows, surface layering, information grouping.
- **States** — hover / focus / active / selected / disabled / loading / empty / skeleton / success / warning / error / offline. Make resilient, calm, informative.
- **Components** — normalize buttons / inputs / dropdowns / toggles / tabs / cards / dialogs / toasts / badges / lists / tables / menus / headers / sidebars / toolbars. Consistent spacing, sizing, semantics, behavior.
- **Flow** — discoverability of primary actions, first-run feel, settings organization, navigation clarity, reduced friction + cognitive load.
- **Microcopy** — button labels, empty-state copy, error messages, helper text, onboarding, confirmations. Concise, clear, human, confidence-building.
- **A11y (mandatory, not optional)** — focus visibility, keyboard nav, contrast, touch targets, semantic structure, reduced-motion support, no color-only meaning.
- **Motion** — subtle, fast, purposeful. Never flashy. Respect reduced-motion.
- **Theme** — unified accents, coherent surfaces, light/dark parity, no color drift.
- **Perceived quality** — visual stability, predictable interactions, graceful failure, polished loading, reduced accidental destructiveness.

## Standards

- Bar: "would this ship from a world-class team?"
- Preserve product identity; elevate, don't redesign.
- Maintain stack + architecture compatibility.
- Never invent libraries, files, APIs, or design systems not already in the repo.
- No fake polish — every change must support clarity, usability, or trust.

## Priority order

1. Usability blockers / confusing flows
2. Major inconsistency across components or screens
3. Missing or weak states (loading, empty, error, disabled, confirmation)
4. Weak hierarchy, spacing, typography, layout quality
5. Accessibility improvements
6. Microcopy and interaction refinement
7. Motion, delight, premium finishing

## Anti-patterns to reject

- Random aesthetic changes without system-level thinking
- Trendy UI at expense of clarity
- Heavy new dependencies
- Motion noise
- Superficial restyling that stops at colors + shadows

## Output

Make direct code changes where confidence is high. Run build + type-check + tests after. Summarize at the end: key upgrades made, issues found, remaining opportunities, assumptions you couldn't verify.
