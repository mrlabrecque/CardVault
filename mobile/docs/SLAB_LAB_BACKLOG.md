# Slab Lab feedback — working backlog

Internal reference from bug review / UX feedback (“Slab Lab”). Update this file as items ship or scope changes.

### If you ask the assistant “what’s next?” or “what’s left on our list?”

The assistant does **not** automatically see this file every turn. Do one of the following so answers stay accurate:

1. **Attach the doc** — In chat, reference `@mobile/docs/SLAB_LAB_BACKLOG.md` (or add it to the context for that message).
2. **Optional Cursor Memory** — Save something like: *When I ask what’s next or what’s left on the Slab Lab list, read `mobile/docs/SLAB_LAB_BACKLOG.md` and answer from the “Suggested implementation order” and open sections, marking what’s already done if known from the repo.*

Then questions like “what’s next to work on?” map directly to **Open items** below and **Suggested implementation order**.

---

## Product decision: Portfolio Movers (2026-05)

| Topic | Decision |
|-------|----------|
| **Name** | **Portfolio Movers** (was “Market Movers” in UI). |
| **Signal** | Aggregate **all users’** `user_cards`: **avg(`current_value`) vs avg(`previous_value`)** per **player + sport** (from `master_card_definitions` + `releases.sport`), after comps refresh. |
| **Why not lookups / comps-only views** | A one-off comps lookup does not imply market movement; we only trust **stored value changes** on **owned** cards. |
| **Why not `master_card_definitions` alone** | Catalog rows are not the system of record for “last refresh”; movement lives on **`user_cards`** (and optionally future comp-history tables). |
| **Backend** | Postgres RPC **`portfolio_movers_from_vault(p_sport)`** (`SECURITY DEFINER`). No batch eBay scrape from the app for this screen. |
| **Legacy** | Edge function **`market-movers-refresh`** is a **no-op stub** (Bright Data removed); disable old cron if desired. |
| **Routes** | Primary: `/portfolio-movers`, `/admin/portfolio-movers`. Aliases: `/market-movers`, `/admin/market-movers` → same screens. |

---

## Completion status (repo audit)

Legend: **Done** = implemented in current Flutter code · **Partial** = some of it shipped · **Open** = not done / not verified

| Bucket | Done | Partial | Open |
|--------|------|---------|------|
| Quick wins | Set/checklist rows, USD commas, Lot Builder browse, **Portfolio Movers** shell | — | Grading half-blur |
| Grading recommendations | Edge `grading-comps-sold-analyze` + UI consume results | Cached TTL / “as of” not verified in UI | Blur-left layout bug |
| Lot Builder | Browse `_filtered` excludes null/zero value; basket `ListItemUsdText`; checklist via `fromUserCard` | — | Optional: “move basket” overlap tuning if still reported |
| Portfolio Movers | Glass nav, vault RPC, fair quota per sport in “all sports” view | — | — |
| General / cross-cutting | — | — | All rows in that table still open |
| New features (spec TBD) | — | — | All open |

---

## Quick wins (localized Flutter fixes)

| Status | Item | Notes | Primary locations |
|--------|------|--------|-------------------|
| **Done** | Missing **set / product line** on rows | `UserCard.fromJson` sets `checklist` from `master → sets.name` and `set` from release; `CardInfoSection.fromUserCard` shows checklist when present; collection fetch includes nested `sets` / `releases`. | `user_card.dart`, `cards_service.dart`, `grading_screen.dart`, `lot_builder_screen.dart` |
| **Done** | Lot Builder: **N/A vs $0.00** | `_filtered` requires `currentValue != null && currentValue > 0`, so browse never lists no-value cards. Basket rows use `ListItemUsdText` (N/A when value missing/zero). | `lot_builder_screen.dart` `_filtered`, `_BasketCardRow` |
| **Done** | **Portfolio Movers** header / list chrome | `buildGlassNavBar` with blur; list/error/skeleton inset via `navOffset`; sport filter in app bar. | `portfolio_movers_screen.dart` |
| **Done** | **Commas in prices** | Central `lib/core/utils/currency_format.dart` (`formatUsd`, `formatUsdOrNa`, …) + `ListItemUsdText`; major screens use them. Residual: occasional `toStringAsFixed` worth grepping. | `currency_format.dart`, feature screens |
| **Open** | **Grading: half-blur** | Needs on-device repro; likely clipping/stacking under frosted header stack. | `grading_screen.dart`, `frosted_chrome_layer.dart`, `sliver_frosted_header.dart` |

## Grading recommendations

| Status | Item | Notes |
|--------|------|--------|
| **Open** | **Cached avg pricing** | Validate caching/TTL on `grading-comps-sold-analyze`; optional **“as of”** or refresh in UI. |
| **Done** | **Missing set name** | Same data path as checklist row fix (`UserCard` + `CardInfoSection.fromUserCard`). |
| **Open** | **Blur only on left** | Same as quick win “half-blur”. |

Relevant files: `lib/core/services/grading_service.dart`, `lib/features/grading/grading_screen.dart`, Supabase function `grading-comps-sold-analyze`.

## Lot Builder

| Status | Item | Notes |
|--------|------|--------|
| **Done** | N/A or hide **0** values | Enforced by `_filtered`; browse UI never receives zero/null current value for that list. |
| **Open** | **Move basket panel down** | If overlap remains: tune `navOffset` / `_BasketHeader` / chrome stacking. |
| **Done** | **Missing set / checklist** | `CardInfoSection.fromUserCard(card)` supplies checklist from `UserCard`. |

File: `lib/features/lot_builder/lot_builder_screen.dart`.

## Portfolio Movers

| Status | Item | Notes |
|--------|------|--------|
| **Done** | **Implementation** | RPC `portfolio_movers_from_vault`; Flutter `portfolio_movers_service.dart`, `portfolio_movers_screen.dart`; admin explainer `admin_portfolio_movers_screen.dart`. |

Files: `lib/features/portfolio_movers/portfolio_movers_screen.dart`, `lib/core/services/portfolio_movers_service.dart`, `supabase/migrations/20260511120000_market_movers_vault_rpc.sql`, `20260512120000_drop_legacy_market_movers_from_vault.sql`.

## General / cross-cutting

| Status | Item | Notes |
|--------|------|--------|
| **Open** | **Lazy-load images when browsing a set** | Viewport or batch visible IDs. |
| **Open** | **Revamp scan + OCR (front/back)** | Larger initiative. |
| **Open** | **Bulk add / rip mode** | UX pass — `catalog_screen.dart` and related. |
| **Open** | **Fix math on sets** | Needs repro (screen + wrong total). |
| **Open** | **Fonts consistency** | `AppFonts` vs raw `TextStyle`. |
| **Open** | **Scan results below header** | Layout / scroll padding under app bar. |
| **Open** | **Scan → catalog detail never loads** | Trace `CatalogScanEntry`, router extras, async failures. |
| **Open** | **Catalog card detail as own route** | Dedicated `GoRoute` + extract detail for deep links / scan. |

Key files: `lib/features/scan/scan_screen.dart`, `lib/features/collection/catalog_screen.dart`, `lib/core/router.dart`.

## New features (spec TBD)

| Status | Feature | Direction |
|--------|---------|-----------|
| **Open** | **Good deal / bad deal** | Heuristic UI (comps vs ask vs paid). |
| **Open** | **Parallel reference** | Browse/education per set — `set_parallels` / catalog. |
| **Open** | **User upload image** | Storage + permissions; override vs master image. |
| **Open** | **Watchlist** | Clarify vs **Wishlist**. |
| **Open** | **Market Data → player sales drilldown** | Tap a Market Data row → Card Hedge [`POST /v1/cards/sales-stats-by-player`](https://api.cardhedger.com/docs#tag/market-data/POST/v1/cards/sales-stats-by-player): bucketed sale **count** / **total USD** / **avg** by day/week/month (player name matched in listing text). Implement via Edge `cardhedge-sales-stats-by-player` + detail route/chart; **parked until after 1.0** (Flutter + Edge code removed from repo). |

---

## What’s next (only open work)

1. **Grading blur** — Reproduce on device; fix frosted header / layer bounds.
2. **Optional polish** — Grep `toStringAsFixed` for prices; Grading search could include `checklist` in text filter (minor).
3. **Scan / catalog** — Pick one repro (results under header, detail not loading, or dedicated route) and fix before larger OCR/bulk tracks.

_Last updated: 2026-05-12 — Market Data player sales drilldown parked on backlog; Flutter + Edge stub removed until post–1.0._
