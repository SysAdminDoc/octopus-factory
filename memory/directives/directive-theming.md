---
name: Theming Directive
description: Theme system audit + repair standard referenced by T1 and T2 of the factory loop. Covers token architecture, contrast, states across all modes, accessibility. Load lazily — only when the theming phase is running.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
triggers: [theme, theming, dark mode, light mode, tokens, contrast, wcag]
agents: [implementer, critic]
---
# Theming Directive

Referenced by factory-loop T1 (codex) and T2 (claude counter-pass).

Audit, repair, and harden the app's theming system. Every visible UI element must look intentional, accessible, and consistent in every theme.

- **If themes already exist:** preserve public behavior, improve the implementation.
- **If themes don't exist:** implement cleanly using the repo's existing framework, styling approach, and design patterns. Do not introduce a new UI library.

## Inspect first

- Framework, styling system, theme provider, tokens, CSS variables, Tailwind config, component library, design system
- All surfaces: pages, layouts, shared components, dialogs, forms, tables, navigation, cards, buttons, charts, icons, alerts, empty/loading/error/disabled states

## Audit

- Hardcoded colors, opacity hacks, one-off backgrounds, weak borders, unreadable text, invisible icons, broken hover/focus states
- Components that only look right in one theme
- Foreground/background contrast; interaction states
- Nested surfaces specifically: modals, popovers, dropdowns, sidebars, tables, tooltips, toasts, code blocks

## Fix architecture

- Semantic tokens only: background / foreground / surface / muted / border / accent / destructive / success / warning / focus
- No scattered raw hex colors in components — centralize everything
- Theme switching reliable + persistent (if persistence already exists)
- Respect system theme preference
- Preserve existing visual identity; make palette feel complete across all modes

## Fix every affected element

- Text, icons, borders, inputs, buttons, menus, cards, badges, shadows, overlays, links, charts, focus rings — must work in every theme
- All states visually distinct in every theme: hover / active / selected / disabled / loading / empty / error / success
- Keyboard focus visible in every theme
- Disabled elements look disabled but remain legible
- Placeholders, helper text, validation messages, secondary text have sufficient contrast per WCAG AA minimum

## Verify

- Run existing lint / typecheck / tests / build
- If Storybook / Playwright / Cypress / visual tests exist, exercise each theme
- If practical, add a theme coverage route that renders common components across all modes
- Check desktop and mobile layouts

## Constraints

- Follow existing repo patterns
- Keep changes focused on theming — no unrelated logic rewrites
- Do not introduce a new UI library unless absolutely necessary
- Do not remove existing themes or user-facing theme settings without a clear reason
- Prefer accessible, semantic, maintainable styling over cosmetic patchwork

## Acceptance

- No major UI element is unreadable, invisible, or broken in any theme
- Theme colors come primarily from centralized semantic tokens
- Interactive states polished and consistent across all modes
- Forms, navigation, modals, tables, cards, alerts, and loading/error/empty states are all theme-aware
- Build / lint / typecheck / tests pass (or document pre-existing failures)
