# Slab Lab feedback — working backlog

Internal reference from bug review / UX feedback (“Slab Lab”). Update this file as items ship or scope changes.

### If you ask the assistant “what’s next?” or “what’s left on our list?”

The assistant does **not** automatically see this file every turn. Do one of the following so answers stay accurate:

1. **Attach the doc** — In chat, reference `@mobile/docs/SLAB_LAB_BACKLOG.md` (or add it to the context for that message).
2. **Optional Cursor Memory** — Save something like: *When I ask what’s next or what’s left on the Slab Lab list, read `mobile/docs/SLAB_LAB_BACKLOG.md` and answer from the “Suggested implementation order” and open sections, marking what’s already done if known from the repo.*

Then questions like “what’s next to work on?” map directly to **Suggested implementation order** at the bottom plus any unchecked items above.

## Quick wins (localized Flutter fixes)

| Item | Notes | Primary locations |
|------|--------|-------------------|
| Missing **set / product line** on rows | `CardInfoSection` often gets `set:` but not `checklist:`. Data may store the line in `checklist`. | `lib/features/grading/grading_screen.dart` (`_CardRow`), `lib/features/lot_builder/lot_builder_screen.dart` (`_BrowseCardRow`, `_BasketCardRow`) |
| Lot Builder: **N/A vs $0.00** | Align with rest of app: show `N/A` (or omit) when value is null or zero; optional filter-out zeros. | `lot_builder_screen.dart` price `Text` widgets |
| **Market Movers header** | Screen uses `Column` + `AppBreadcrumb` only — no glass nav / `extendBodyBehindAppBar` / safe-area parity vs Tools siblings. | `lib/features/market_movers/market_movers_screen.dart` |
| **Commas in prices** | Introduce or reuse a single USD formatter (e.g. `intl` `NumberFormat`) and replace raw `toStringAsFixed` in lists. | Grading, Lot Builder, collection, item detail, etc. |
| **Grading: half-blur** | Reproduce on device; suspect layout width/clipping under `SliverFrostedHeader` / `FrostedChromeLayer`, not shader alone. | `grading_screen.dart`, `frosted_chrome_layer.dart`, `sliver_frosted_header.dart` |

## Grading recommendations

| Item | Notes |
|------|--------|
| **Cached avg pricing** | Flow: `GradingService.analyzeCard` → edge `grading-comps-sold-analyze`. Validate caching/TTL server-side; UI may need “as of” or refresh. |
| **Missing set name** | Same as checklist fix above. |
| **Blur only on left** | See quick wins table. |

Relevant files: `lib/core/services/grading_service.dart`, `lib/features/grading/grading_screen.dart`, Supabase function `grading-comps-sold-analyze`.

## Lot Builder

| Item | Notes |
|------|--------|
| N/A or hide **0** values | See quick wins. |
| **Move basket panel down** | UX: `_BasketScrollView` / `_BasketHeader` — reduce overlap with nav; tune `navOffset` / chrome stacking. |
| **Missing set** | Pass `checklist` into `CardInfoSection`. |

File: `lib/features/lot_builder/lot_builder_screen.dart`.

## Market Movers

| Item | Notes |
|------|--------|
| **Fix header** | Align with other Tools routes (`GlassNavBar`, safe area, padding). |

Files: `lib/features/market_movers/market_movers_screen.dart`, `lib/core/services/market_movers_service.dart`.

## General / cross-cutting

| Item | Notes |
|------|--------|
| **Lazy-load images when browsing a set** | Fetch CardSight / storage images when cards enter viewport (or batch visible IDs). See repo guidance on lazy image edge after add. |
| **Revamp scan + OCR (front/back)** | Larger initiative: capture flow, possibly two images, edge contract updates. |
| **Bulk add / rip mode** | UX pass on bulk flows — likely `catalog_screen.dart` and related. |
| **Fix math on sets** | Needs repro: which screen, which totals wrong? |
| **Fonts consistency** | Audit `AppFonts` vs raw `TextStyle`; unify via theme / shared styles. |
| **Scan results below header** | Layout / `SafeArea` / scroll padding under app bar. |
| **Scan → catalog detail never loads** | Trace `CatalogScanEntry`, `_openCatalogFromScan`, `router.dart` extras; check async failures / missing IDs. |
| **Catalog card detail as own route** | Add dedicated `GoRoute` and extract detail widget so scan/deep links push a real screen (not only in-flow state). |

Key files: `lib/features/scan/scan_screen.dart`, `lib/features/collection/catalog_screen.dart`, `lib/core/router.dart`.

## New features (spec TBD)

| Feature | Direction |
|---------|-----------|
| **Good deal / bad deal** | Heuristic UI (comps vs ask vs paid), similar to automotive pricing sites. |
| **Parallel reference** | Browse/education per set — ties to `set_parallels` / catalog. |
| **User upload image** | Storage + permission model; likely `user_cards` override vs master image. |
| **Watchlist** | Clarify vs existing **Wishlist** — eBay listing watch, alerts, or consolidate naming. |

---

## Suggested implementation order

1. Pass `checklist` into `CardInfoSection` wherever only `set` is passed (grading + lot builder).
2. Lot Builder: N/A for zero/null current value; Market Movers header parity.
3. Shared `formatUsd` (or equivalent) and adopt in high-traffic screens.
4. Scan layout + catalog navigation bugs (repro-driven).
5. Larger items (scan OCR, bulk revamp, deal meter) as separate tracks.

_Last updated: 2026-05-10_
