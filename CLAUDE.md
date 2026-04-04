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

### F. External Integrations
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
| Variant / Parallel | string |
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
│       │   ├── guards/        # AuthGuard (CanActivate)
│       │   └── services/      # auth, cards, ebay, checklist, alerts
│       └── features/
│           ├── dashboard/
│           ├── collection/    # collection-list + item-detail
│           ├── comps/         # comps-search (valuation/lookup)
│           └── wishlist/
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

## Implementation Progress

### Done
- [x] Angular app scaffolded (Angular 21, SCSS, standalone components)
- [x] Tailwind CSS v4 + PrimeNG 21 installed and configured (Aura theme, CSS layer order set)
- [x] App shell with `<router-outlet>` and bottom tab bar (Collection, Dashboard FAB, Comps, Wishlist)
- [x] Routes wired: `/dashboard`, `/collection`, `/collection/:id`, `/comps`, `/wishlist`
- [x] Feature component stubs in place for all four main views

### Up Next
- [ ] Dashboard — P/L summary cards, sport/player distribution charts, highest-value card
- [ ] Collection list — card grid/list, search, inline edit
- [ ] Item detail — full card editor
- [ ] Comps search — text + image search, results with eBay sold prices, lookup history
- [ ] Wishlist — list view, price threshold editor
- [ ] Auth — login page, AuthGuard, Supabase session
- [ ] Backend API — Express routes, Supabase client, eBay service
- [ ] Database — Supabase migrations, RLS policies