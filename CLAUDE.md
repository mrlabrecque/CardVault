# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

A responsive, mobile-first web application for collectors to manage, value, and sell sports trading cards. Supports multi-tenancy so the owner and invited friends can each maintain independent, private collections.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Angular 21 (mobile-first, modern responsive UI) |
| UI Libraries | Tailwind CSS v4 (utility styling) + PrimeNG 21 (components) |
| Backend | Node.js with Express.js |
| Database & Auth | Supabase (PostgreSQL + Supabase Auth) |
| Integrations | eBay Browse/Trading APIs, Checklist Data Providers |

---

## Core Features

### A. Authentication & Multi-tenancy
- Secure login for the primary user and invited friends
- Full data isolation — each user manages their own private collection

### B. Dashboard (Analytics)
- P/L (Profit/Loss) visualizations
- Card distribution breakdowns by Sport and Player
- Highest value card identification
- Inventory valuation tools

### C. Collection Management
- List and organize cards with multi-property grouping
- Fuzzy search with real-time autocomplete
- Quick inline editing for card details
- Dedicated Item Page for deep editing and detailed metadata
- One-click "Post to eBay" integration

### D. Valuation & Lookup (Comps)
- Text-based search and Image-to-Value (photo search)
- Retrieve and display recent eBay "Sold" values
- Rolling log of the last 50 lookups (per user)
- Add card directly to collection from search results, including "Price Paid" entry

### E. Wishlist & Alerts
- Add cards from lookup results to a personal Wishlist
- Set price thresholds on specific cards
- Automated email alerts when eBay listings appear below the set threshold

### F. Admin — Set Management
- Only accessible when `isAppAdmin` is `true`; guarded by `adminGuard` at the route level
- **"Manage Sets" link** appears in the avatar dropdown (above Sign Out) for admin users only
- Route: `/admin/sets` — `SetBuilder` component (`features/admin/set-builder/`)
- Create new product releases (e.g. "2025 Panini Prizm Basketball") that act as global parents for user cards
- Fields: `name`, `year`, `sport` (Basketball / Baseball / Football / Soccer), `release_type` (Hobby / Retail / FOTL), `ebay_search_template`
- Auto-generates a `set_slug` (e.g. `2025-prizm-basketball-hobby`) used in clean URLs
- Duplicate guard: checks (name, year, sport) before saving; shows inline error if a match exists
- Real-time eBay template preview replaces `{year}`, `{brand}`, `{player_name}`, `{card_number}` tokens using "Victor Wembanyama #298" as dummy values
- Success PrimeNG Toast on create; form resets and sets list reloads automatically

### G. External Integrations
- **eBay API**: Real-time market value sync from sold listings; automated listing creation
- **Checklist Integration**: Sync with sports card checklist databases to standardize card naming and numbering during the "Add to Collection" workflow

---

## Data Models (High-Level)

### User
| Field | Type |
|---|---|
| ID | UUID (PK) |
| Email | string |
| Preferences | jsonb |

### Card
| Field | Type |
|---|---|
| ID | UUID (PK) |
| OwnerID | UUID (FK → User) |
| Player | string |
| Sport | string |
| Set | string |
| Year | integer |
| Parallel | string |
| Grade | string |
| Price Paid | decimal |
| Current Value | decimal |

### LookupHistory
| Field | Type |
|---|---|
| UserID | UUID (FK → User) |
| Query | string |
| Results | jsonb |
| Timestamp | timestamptz |

### Wishlist
| Field | Type |
|---|---|
| UserID | UUID (FK → User) |
| CardDetails | jsonb |
| TargetPrice | decimal |
| AlertStatus | string / enum |

---

## Commands

### Frontend (`frontend/`)
| Command | Description |
|---|---|
| `ng serve` | Dev server at `http://localhost:4200` |
| `ng build` | Production build to `dist/` |
| `ng test` | Run unit tests via Karma |
| `ng generate component features/<name>` | Add a new feature component |

### Backend (`backend/`)
| Command | Description |
|---|---|
| `npm run dev` | Dev server with hot-reload (ts-node-dev) |
| `npm run build` | Compile TypeScript to `dist/` |
| `npm start` | Run compiled production build |

### Database
- Apply migrations: `supabase db push` or run `supabase/migrations/20240101000000_init.sql` in the Supabase SQL editor
- Local dev seed: `supabase/seed.sql`

---

## Project Structure

```
card-vault/
├── frontend/                  # Angular app
│   └── src/app/
│       ├── core/
│       │   ├── auth/login/    # Login component
│       │   ├── guards/        # authGuard (CanActivate), adminGuard (isAppAdmin check)
│       │   └── services/      # auth, cards, ebay, checklist, alerts, sets
│       └── features/
│           ├── dashboard/
│           ├── collection/    # collection-list + item-detail
│           ├── comps/         # comps-search (valuation/lookup)
│           ├── wishlist/
│           └── admin/
│               └── set-builder/  # Admin-only set management UI
├── backend/                   # Express API
│   └── src/
│       ├── db/supabase.ts     # Supabase client
│       ├── middleware/auth.ts # JWT auth middleware
│       ├── routes/            # cards, comps, wishlist, ebay
│       ├── services/          # ebay.service, checklist.service, alerts.service
│       └── jobs/alertJob.ts   # Hourly cron for price alerts
└── supabase/
    ├── migrations/            # SQL schema (RLS enabled)
    └── seed.sql
```

### API Routes
| Method | Path | Description |
|---|---|---|
| GET/POST/PATCH/DELETE | `/api/cards` | Card CRUD |
| POST | `/api/comps/search` | eBay sold comps search (writes to lookup_history) |
| GET | `/api/comps/history` | Last 50 lookups for user |
| GET/POST/PATCH/DELETE | `/api/wishlist` | Wishlist CRUD |
| POST | `/api/ebay/list/:cardId` | Post card to eBay |

---

## Key Architectural Notes

- **Multi-tenancy** is enforced at the data layer via `OwnerID` on all user-scoped records. Supabase Row Level Security (RLS) should be used to ensure users can only access their own data.
- **eBay integration** is used in two directions: read (fetching sold comps for valuation) and write (creating listings from the collection).
- **Lookup history** is capped at 50 entries per user — implement a rolling window with deletion of the oldest entry on insert when the limit is reached.
- **Price alerts** require a background job or webhook mechanism to poll eBay and trigger email notifications when thresholds are met.

---

## UI / Styling Conventions

- **Tailwind CSS v4** — use utility classes for all layout, spacing, typography, and color. Config lives in `frontend/.postcssrc.json`.
- **PrimeNG 21** — use for complex components: data tables (`<p-table>`), charts (`<p-chart>`), dialogs (`<p-dialog>`), buttons (`<p-button>`), etc. Theme: **Aura** (configured in `app.config.ts`).
- **CSS layer order**: `tailwind-base → primeng → tailwind-utilities`. Tailwind utilities always win over PrimeNG component styles. Do not add component-scoped overrides that fight this order.
- **Dark mode**: toggled via `.dark` class on the root element (not `prefers-color-scheme`).
- **App shell**: max-width 480px, centered, with a fixed bottom tab bar (height `72px`). The dashboard is the default landing route (`/`). Tabs: Collection, Dashboard (center FAB), Comps, Wishlist.
- **Global styles entry**: `frontend/src/styles.scss` — Tailwind and PrimeIcons are imported here. Do not import them anywhere else.

---

## Authentication

- **Flow**: Supabase Auth, PKCE, passwordless Magic Link only (no social providers).
- **`AuthService`** (`core/services/auth.ts`) — wraps the Supabase client; exposes signals: `user`, `isAuthenticated`, `isAppAdmin`. Calls `fetchProfile()` on every sign-in which upserts a `profiles` row (safe for pre-existing users) and then separately syncs the email field.
- **`authGuard`** (`core/guards/auth-guard.ts`) — async `CanActivateFn`; calls `getSession()` directly to avoid timing races on first load. All feature routes are guarded; `/login` is public.
- **`isAppAdmin`** — boolean flag in the `profiles` table, default `false`. Must be flipped manually in the Supabase dashboard (no client-side update path for this field). Gates the "Manage Sets" link in the avatar dropdown and the `/admin/sets` route.
- **`adminGuard`** (`core/guards/admin-guard.ts`) — async `CanActivateFn`; does a live Supabase query for `is_app_admin` (does not rely on signal timing). Redirects non-admins to `/dashboard`.
- **Tab bar + header** are hidden on the login page — both gated with `@if (auth.isAuthenticated())` in `app.html`.

## App Shell

- **Header** (`app.html` / `app.scss`) — sticky flex item (not `position: fixed`) at the top of `.app-shell`. Shows "Card Vault" eyebrow + current page title (derived from route URL via `toSignal` + `NavigationEnd`). Avatar button (user's email initial) opens a dropdown with email, optional "App Admin" badge, optional "Manage Sets" link (admin only), and Sign Out.
- **Tab bar** — `position: fixed`, bottom, primary color, 72px tall. Tabs: Collection, Dashboard (center FAB), Comps, Wishlist.
- **Content area** — `flex: 1; overflow-y: auto`. When authenticated, `padding-bottom: var(--tab-bar-height)` keeps content clear of the tab bar. Header is in normal flow so no `padding-top` offset is needed.

## Styling Conventions (additions)

- **Component SCSS files** — do NOT use `@apply`. Other component SCSS files in this project are empty; put all styles as Tailwind utility classes directly in the HTML template. Reserve component SCSS only for things Tailwind cannot express (keyframe animations, pseudo-element tricks, third-party overrides with `!important`).
- **PrimeNG button dark-mode conflict** — `p-button` inherits dark-mode overrides from the Aura theme. For any button where appearance is critical (e.g. the login CTA), use a plain `<button>` with hand-written styles instead of `p-button`.

---

## Implementation Progress

### Done
- [x] Angular app scaffolded (Angular 21, SCSS, standalone components)
- [x] Tailwind CSS v4 + PrimeNG 21 installed and configured (Aura theme, CSS layer order set)
- [x] App shell — header (title + avatar/logout), bottom tab bar, routes, feature stubs
- [x] Routes wired: `/login`, `/dashboard`, `/collection`, `/collection/:id`, `/comps`, `/wishlist`
- [x] Auth — Magic Link login page (PSA slab design), `AuthService`, `AuthGuard`, all feature routes guarded
- [x] `profiles` table — `id`, `email`, `is_app_admin`; trigger auto-creates on signup; frontend upserts on every sign-in; RLS locks down admin promotion
- [x] Database — RLS on `cards`, `lookup_history`, `wishlist`; `master_card_definitions` read-only catalog migration
- [x] Dashboard, Collection list, Comps search, Wishlist — UI stubs with sample data in place
- [x] Admin Set Builder — `/admin/sets` route; `SetBuilder` component; `SetsService`; `adminGuard`; `sets` table with RLS; "Manage Sets" link in avatar dropdown

### Up Next
- [ ] Dashboard — wire to real Supabase data (P/L, sport distribution, top cards)
- [ ] Collection list — wire to real `cards` table; inline edit
- [ ] Item detail — full card editor; "Post to eBay" button
- [ ] Comps search — eBay sold listings integration; lookup history
- [ ] Wishlist — price threshold editor; alert status
- [ ] Backend API — Express routes, Supabase client, eBay service

### Supabase Migrations (apply in order)
| File | Description |
|---|---|
| `20240101000000_init.sql` | Core schema: `cards`, `lookup_history`, `wishlist` + RLS |
| `20260404000000_rls_master_catalog.sql` | `master_card_definitions` public read-only table |
| `20260404000001_profiles.sql` | `profiles` table + trigger + select/insert RLS |
| `20260404000002_profiles_insert_policy.sql` | Insert policy for self-service profile creation |
| `20260404000003_profiles_add_email.sql` | `email` column + update policy + trigger update |
| `20260404000004_sets.sql` | `sets` table + RLS (all auth users read; admin-only write) |