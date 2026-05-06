---
name: ios-26-liquid-glass
description: iOS 26 design pattern companion focused on Liquid Glass, inset tab bar behavior, search island placement, scroll-edge effects, and icon-composer expectations. Use alongside ios-hig-design when the user mentions iOS 26, Liquid Glass, updated tab bars, or modern iPhone UI conventions.
license: MIT
metadata:
  author: cardvault
  version: "1.0.0"
---

# iOS 26 Liquid Glass Companion

Use this skill **together with** `ios-hig-design`, not instead of it.

- `ios-hig-design` = baseline Apple platform correctness and accessibility.
- `ios-26-liquid-glass` = iOS 26 visual/interaction deltas and practical defaults.

If guidance conflicts, prioritize official Apple docs and current native component behavior.

## Source

Primary summary source:
- [Learn UI: iOS 26 Design Guidelines](https://www.learnui.design/blog/ios-design-guidelines-templates.html)

Treat this as a practical companion, not the canonical source of truth.

## Additional Reference

- [references.md](references.md): quick tokens, behavior tables, and QA checklist

## When to Apply

Apply this skill when user asks for:
- iOS 26 styling, Liquid Glass, or "new iOS look"
- native iPhone tab/navigation layout updates
- search placement conventions in modern iOS
- iOS icon updates (Icon Composer, layered variants)
- Figma/UI specs intended to feel current with iOS 26

## iOS 26 Deltas (Quick Reference)

### 1) Liquid Glass is a navigation-layer material

- Use Liquid Glass primarily for navigation and key controls that float above content.
- Keep content layers (lists/cards/forms) mostly conventional and readable.
- Do not apply glass treatment indiscriminately to all surfaces.

### 2) Controls float above scrolling content

- Nav and toolbar controls can appear fixed/floating while content scrolls beneath.
- Preserve legibility with scroll-edge effects where content passes under chrome.

### 3) Tab bar pattern changed

- Bottom tab bar is inset and capsule-like (not edge-to-edge full width).
- Typical inset guidance from source: ~21pt left/right/bottom spacing.
- Keep 2-5 top-level tabs.
- Search is commonly a separate circular island on the right when present.
- Hide tab bar when keyboard is shown or modal task is active.

### 4) Search reachability trend

- Prefer lower, thumb-reachable search entry points for frequent global search.
- Preserve standard search UX once entered (recent/popular suggestions optional).

### 5) Top vs bottom scroll-edge effects

- Top region often uses fade + blur for status/nav legibility.
- Bottom region commonly uses fade-only as content reaches tab bar area.

### 6) Icon expectations in iOS 26

- Account for layered icon outputs (light, dark, mono variants).
- Expect system lighting/parallax effects in presentation.
- Use Apple Icon Composer workflow when designing/exporting icon systems.

## Safe Defaults for Agent Output

When producing UI guidance, specs, or code-adjacent recommendations:

1. Start from native components and semantic system styles.
2. Apply Liquid Glass selectively to floating nav/action surfaces.
3. Keep text/content hierarchy clear and high-contrast first.
4. Enforce 44x44pt minimum touch targets.
5. Respect safe areas and reserve home-indicator space.
6. Ensure dark mode and accessibility remain fully intact.

## Anti-Patterns

- Making every surface glassy (visual noise, reduced readability)
- Breaking back-swipe, modal dismiss, or other native gestures
- Moving primary navigation away from expected bottom tab behavior
- Prioritizing style novelty over contrast, hierarchy, and accessibility
- Treating third-party summaries as more authoritative than Apple docs

## Implementation Note

For Flutter or cross-platform apps targeting iOS feel:
- Prefer iOS-congruent navigation structure and spacing tokens.
- Keep custom visual effects opt-in and restrained.
- Validate on smallest and largest supported iPhone widths.
