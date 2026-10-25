# Backend roadmap

The APIs still to build, in the order that gets the app to spending analytics
fastest. Each phase is usable on its own: the Flutter app can ship the screens
for a phase as soon as its endpoints are live.

Request and response shapes are in [API.md](API.md). How amounts, merchants,
locations and categories are detected is in [ANALYTICS.md](ANALYTICS.md).

| Phase | Goal                              | Unlocks in the app                        |
| ----- | --------------------------------- | ----------------------------------------- |
| 0     | Done today                        | Register, login, edit-profile stub        |
| 1     | Finish auth                       | Stay signed in, real profile              |
| 2     | Transactions                      | Add and list expenses manually            |
| 3     | Detection                         | Import bank SMS / UPI, auto-categorise    |
| 4     | Analytics                         | Home dashboard: totals, charts, insights  |
| 5     | Budgets                           | Monthly limits and alerts                 |
| —     | Platform work (any time)          | Reliability, debugging, tests             |

All routes under `/api/v1` require `Authorization: Bearer <access_token>` and
only ever read or write the calling user's data.

---

## Phase 0 — Done

| Method | Path              | Notes                                         |
| ------ | ----------------- | --------------------------------------------- |
| POST   | `/register`       | Creates the user in Keycloak and Postgres     |
| POST   | `/login`          | Returns Keycloak access and refresh tokens    |
| PUT    | `/api/v1/profile` | Behind auth middleware; echoes input, saves nothing yet |

---

## Phase 1 — Finish auth

Access tokens expire after 5 minutes, so without refresh the app signs the user
out mid-session.

| Method | Path              | What it does                                                |
| ------ | ----------------- | ----------------------------------------------------------- |
| POST   | `/auth/refresh`   | Exchanges a refresh token for new tokens (`gocloak.RefreshToken`) |
| POST   | `/auth/logout`    | Revokes the refresh token in Keycloak (`gocloak.Logout`)    |
| GET    | `/api/v1/me`      | Returns the user's profile from Postgres                    |
| PUT    | `/api/v1/profile` | Saves first/last name to Postgres **and** Keycloak          |

Also fix:

- `POST /login` returns `user_id` as the all-zero UUID; fill it from the token's
  `sub` and `user_name` from `preferred_username`.
- Map only Keycloak `invalid_grant` to `401 invalid email or password`; return
  `503` for other Keycloak errors so misconfiguration isn't reported as a wrong
  password.

**Done when** the app refreshes tokens silently, survives longer than 5 minutes,
and a profile edit is still there after logging in again.

---

## Phase 2 — Transactions

New `transactions` table (schema in [ANALYTICS.md](ANALYTICS.md#data-model)),
a GORM model in `internal/models`, and a migration in `internal/db`.

| Method | Path                          | What it does                                   |
| ------ | ----------------------------- | ---------------------------------------------- |
| POST   | `/api/v1/transactions`        | Create from fields (amount, merchant, category, date, payment method) |
| GET    | `/api/v1/transactions`        | List, newest first; filter by `from`, `to`, `category`, `merchant`, `q`; paginated |
| GET    | `/api/v1/transactions/{id}`   | One transaction                                |
| PATCH  | `/api/v1/transactions/{id}`   | Correct any field                              |
| DELETE | `/api/v1/transactions/{id}`   | Soft delete                                    |
| GET    | `/api/v1/categories`          | Fixed list: groceries, fuel, food, transport, … |

Rules: amounts are integers in paise, timestamps are UTC, a transaction that
belongs to another user returns `404`.

**Done when** a user can add, edit and delete expenses in the app and see them
in a list that survives restarts.

---

## Phase 3 — Detection

A pure Go package `internal/detect` with no HTTP or database code, so it can be
unit-tested with real messages.

| Method | Path                               | What it does                                      |
| ------ | ---------------------------------- | ------------------------------------------------- |
| POST   | `/api/v1/transactions/parse`       | Detect amount, type, merchant, location, category from text; **does not save** |
| POST   | `/api/v1/transactions` (`text`)    | Same detection, then save; duplicates return the existing row |
| POST   | `/api/v1/transactions/bulk`        | Import up to 500 messages; reports created / duplicate / skipped |
| GET    | `/api/v1/merchant-rules`           | List the user's merchant → category rules         |
| POST   | `/api/v1/merchant-rules`           | Add a rule, optionally re-categorise past transactions |
| DELETE | `/api/v1/merchant-rules/{id}`      | Remove a rule                                     |

`PATCH /api/v1/transactions/{id}` gains `remember: true`, which saves the
correction as a merchant rule.

Detection order: user rules → known merchants (DMart, Reliance Fresh, HPCL,
BPCL, Indian Oil, …) → merchant category code → keywords (`SUPERMARKET`,
`PETROL`, `FUEL`, …) → `other`. Every result carries a `confidence` score.

**Done when** pasting
`Rs.2,000.00 spent on HDFC Card XX9876 at HPCL FUEL STATION MUMBAI on 22-10-26`
returns `amount: 200000`, `merchant: HPCL`, `category: fuel`,
`location: Mumbai`, and `detect` has table tests covering at least 50 real
messages from different banks and UPI apps.

---

## Phase 4 — Analytics

SQL aggregates over `transactions`, scoped to the user. All accept `from` and
`to` (default: current month) and compare against the previous period.

| Method | Path                              | Powers                                        |
| ------ | --------------------------------- | --------------------------------------------- |
| GET    | `/api/v1/analytics/summary`       | "₹28,450 spent this month, 13% more than last" card |
| GET    | `/api/v1/analytics/categories`    | Pie chart: groceries 32%, fuel 21%, …         |
| GET    | `/api/v1/analytics/merchants`     | "Top places" list                             |
| GET    | `/api/v1/analytics/locations`     | Spend by city / area                          |
| GET    | `/api/v1/analytics/trend`         | Daily / weekly / monthly bar chart            |
| GET    | `/api/v1/analytics/insights`      | Tip cards: "Fuel spending is up 22%", "4 visits to DMart" |

Refunds are subtracted from their category, transfers are excluded unless
`include_transfers=true`, and empty days are returned as `0` so charts have no
gaps.

**Done when** the home screen shows a month summary, a category breakdown and
a trend chart built only from these endpoints.

---

## Phase 5 — Budgets

| Method | Path                         | What it does                                  |
| ------ | ---------------------------- | --------------------------------------------- |
| GET    | `/api/v1/budgets`            | Monthly limit per category with amount spent and % used |
| PUT    | `/api/v1/budgets/{category}` | Set or change a category's monthly limit      |
| DELETE | `/api/v1/budgets/{category}` | Remove a limit                                |

`/api/v1/analytics/insights` gains `budget_warning` (80% used) and
`budget_exceeded` insights.

**Done when** a user can set "Fuel: ₹5,000 / month" and sees a warning once
they pass ₹4,000.

---

## Platform work

Can be picked up at any point; the first two are worth doing before Phase 2.

| Item                         | Why                                                         |
| ---------------------------- | ----------------------------------------------------------- |
| `GET /healthz`               | Liveness check for Docker and uptime monitoring             |
| Fix audit-log status         | The middleware records the status before the handler runs, so every row says `200` |
| Panic recovery + request IDs | One failing request shouldn't crash the server; IDs tie app errors to log lines |
| Go tests in `make test`      | Handlers with a fake repository, and `detect` table tests   |
| Local token verification     | Verify JWTs with the realm's public keys instead of one Keycloak call per request |
| Rate limiting on `/login` and `/register` | Slow down password guessing                    |
| CORS                         | Only needed if a web client is added                        |
