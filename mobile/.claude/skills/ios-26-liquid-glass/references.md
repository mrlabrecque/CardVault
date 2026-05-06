# iOS 26 Quick Reference

Practical reference extracted from:
- https://www.learnui.design/blog/ios-design-guidelines-templates.html

Use this with `ios-hig-design` for baseline HIG, accessibility, and native correctness.

## Layout Tokens (Practical Defaults)

| Area | Practical Value | Notes |
| --- | --- | --- |
| Minimum touch target | `44x44pt` | Applies to all tappable controls |
| Home indicator reserved zone | `21pt` bottom zone | Keep fixed controls out of this space |
| Inset tab bar margin | `~21pt` left/right/bottom | Floating capsule look in iOS 26 |
| Tab count | `2-5` | Use "More" pattern if destinations exceed 5 |

## Scroll-Edge Behavior

| Region | Typical Treatment |
| --- | --- |
| Top (status/nav overlap) | Fade + blur for legibility |
| Bottom (tab overlap) | Fade only (usually no blur) |

## Navigation & Search Expectations

- Keep primary destinations in bottom tab bar.
- Keep per-tab navigation state when switching tabs.
- Tapping active tab can pop back to tab root.
- Search is commonly lower/reachable (tab area, often right-side island).
- Hide tab bar when keyboard is visible.
- Hide tab bar during focused modal tasks.

## Liquid Glass Usage Boundary

Apply Liquid Glass mostly to:
- nav/tool bars
- floating page-level action controls
- menus and other elevated action surfaces

Avoid applying Liquid Glass broadly to:
- long-form content surfaces
- list row backgrounds
- dense data layouts where clarity is reduced

## Typography Snapshot

| Role | Typical Style |
| --- | --- |
| Large title (unscrolled) | `34pt bold` |
| Small title (scrolled) | `17pt semibold` |
| Body / primary list text | `17pt regular` |
| Secondary text | `15pt regular` |
| Tertiary/caption | `13pt regular` |
| Tab label | `11pt regular` |

Use semantic text styles and Dynamic Type support rather than hardcoded sizes in implementation.

## iOS 26 Icon Workflow

- Plan for layered icon variants:
  - light
  - dark
  - mono
- Use Apple Icon Composer when possible.
- Expect system lighting treatment and subtle parallax behavior.

## QA Checklist (Fast Pass)

- [ ] Safe areas respected on small and large iPhone sizes
- [ ] No interactive control below `44x44pt`
- [ ] Home indicator zone remains clear for fixed controls
- [ ] Tab bar uses inset/floating treatment when targeting iOS 26 look
- [ ] Search entry is reachable and consistent
- [ ] Dark mode maintains hierarchy and contrast
- [ ] Liquid Glass limited to elevated navigation/action layers
- [ ] Back swipe + modal swipe-down behaviors remain intact

## Flutter Mapping (Cupertino-First)

Use these mappings when implementing iOS-like behavior in Flutter.

| iOS expectation | Flutter approach |
| --- | --- |
| Safe-area-respecting content | `SafeArea` around page content; avoid placing tappables in unsafe edges |
| Native large/small title behavior | `CupertinoSliverNavigationBar` in a `CustomScrollView` |
| iOS tab navigation baseline | `CupertinoTabScaffold` + `CupertinoTabBar` + one `Navigator` per tab |
| Per-tab back stack memory | Keep tab-local navigators alive (default pattern with `CupertinoTabView`) |
| Modal sheet with swipe-down dismissal | `showCupertinoModalPopup` or `CupertinoPageRoute(fullscreenDialog: true)` with standard affordances |
| iOS search experience | `CupertinoSearchTextField` with dedicated search route/screen |
| iOS lists/forms | `CupertinoListSection` + `CupertinoListTile` (or equivalent row pattern) |
| Native toggles/pickers | `CupertinoSwitch`, `CupertinoDatePicker`, `CupertinoPicker` |
| Dynamic text scaling | Respect `MediaQuery.textScaleFactor`; avoid fixed-height text containers that clip |
| Haptics for key outcomes | `HapticFeedback.selectionClick/lightImpact/mediumImpact/heavyImpact` |

### Flutter Notes for iOS 26 Styling

- Keep Liquid Glass-like styling opt-in and localized to nav/action layers.
- Prefer platform-native feel over heavy custom blur stacks.
- If adding inset/floating tab bar visuals, ensure:
  - `SafeArea` bottom handling remains correct
  - keyboard avoids overlapping controls
  - touch targets remain `>= 44x44pt`
  - tab semantics and labels remain clear for accessibility

### Practical Pattern (Structure)

- Root: `CupertinoTabScaffold`
- Tab screen: `CustomScrollView` + `CupertinoSliverNavigationBar`
- Content: standard list/cards without global glass overlays
- Elevated actions: selective blur/material treatment only where needed
