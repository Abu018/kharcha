# API reference

Base URL: `$API_URL` (wherever you run the API)

Each endpoint is marked with its status:

- **Live** — implemented and running today.
- **Planned** — designed here, not built yet. Shapes may change while it is
  being implemented.

How amounts, merchants and categories are detected is described in
[ANALYTICS.md](ANALYTICS.md).

## Conventions

### Response envelope

Every response uses the same JSON envelope:

```json
{
  "success": true,
  "message": "Human readable message",
  "data": {}
}
```

`data` is omitted when there is nothing to return. On failure `success` is
`false` and `message` explains the error.

### Authentication

Every endpoint except register and login requires the Keycloak access token
returned by `POST /api/v1/login`:

```
Authorization: Bearer <access_token>
```

A missing or expired token returns `401`. Every query is scoped to the user in
the token, so a user can never read another user's transactions.

### Money

Amounts are integers in the smallest currency unit (paise for INR) to avoid
floating-point rounding: `45050` means ₹450.50. Every amount is sent together
with an ISO 4217 `currency` code (default `INR`).

### Dates

- Timestamps are RFC 3339 in UTC: `2026-10-23T11:20:00Z`.
- Range filters `from` and `to` take a date (`2026-10-01`). `from` is
  inclusive and `to` is exclusive.
- If no range is given, analytics endpoints default to the current calendar
  month.

### Pagination

List endpoints accept `page` (default `1`) and `limit` (default `20`, max
`100`) and return:

```json
"data": {
  "items": [],
  "page": 1,
  "limit": 20,
  "total": 134
}
```

### Status codes

| Code | Meaning                                          |
| ---- | ------------------------------------------------ |
| 200  | OK                                               |
| 201  | Created                                          |
| 400  | Invalid JSON or failed validation                |
| 401  | Missing/invalid token, or wrong email/password   |
| 404  | Resource not found (or belongs to another user)  |
| 409  | Conflict, e.g. email already registered          |
| 422  | Text could be read but no amount was detected    |
| 500  | Unexpected server error (details only in logs)   |

---

## Auth

### `POST /api/v1/register` — Live

Creates the user in Keycloak and in Postgres.

```json
{
  "user_name": "user",
  "first_name": "Jane",
  "last_name": "Doe",
  "email": "user@example.com",
  "password": "<your-password>"
}
```

All fields are required. `password` is 8–72 characters.

| Status | `message`                  |
| ------ | -------------------------- |
| 200    | `Success`                  |
| 400    | `invalid JSON` / `invalid input` |
| 409    | `email already registered` |

```sh
curl -X POST "$API_URL"/api/v1/register \
  -H "Content-Type: application/json" \
  -d '{"user_name":"user","first_name":"Jane","last_name":"Doe","email":"user@example.com","password":"<your-password>"}'
```

### `POST /api/v1/login` — Live

Exchanges email and password for Keycloak tokens.

```json
{ "email": "user@example.com", "password": "<your-password>" }
```

`200`:

```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "access_token": "eyJhbGciOi...",
    "refresh_token": "eyJhbGciOi...",
    "token_type": "Bearer",
    "expires_in": 300,
    "refresh_expires_in": 1800,
    "user_id": "00000000-0000-0000-0000-000000000000",
    "user_name": ""
  }
}
```

`user_id` and `user_name` are not filled in yet.

| Status | `message`                    |
| ------ | ---------------------------- |
| 400    | `invalid JSON` / `Invalid Input` |
| 401    | `invalid email or password`  |

```sh
curl -X POST "$API_URL"/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"<your-password>"}'
```

### `POST /auth/refresh` — Planned

Body `{ "refresh_token": "..." }`. Returns the same `data` as `/login`.

---

## Transactions

A transaction is one spend (or refund). It can be entered manually or detected
from raw text such as a bank SMS, a UPI notification or a receipt.

### `POST /api/v1/expense` — Live

Saves a manually entered transaction for the user in the token.

```json
{
  "amount_paise": 45050,
  "currency": "INR",
  "bank_name": "HDFC",
  "account_type": "savings",
  "type": "debit",
  "vendor": "Swiggy",
  "vendor_upi": "swiggy@upi"
}
```

| Field          | Rules                                                      |
| -------------- | ---------------------------------------------------------- |
| `amount_paise` | Required, greater than 0                                   |
| `currency`     | Required, 3 letters                                        |
| `bank_name`    | Required                                                   |
| `account_type` | Required: `savings`, `current`, `credit_card`, `upi_wallet` |
| `type`         | Required: `debit` or `credit`                              |
| `vendor`, `vendor_upi` | Optional                                           |

`201` returns the saved row with its `id`, `user_id`, `created_at` and
`updated_at`.

| Status | `message`                        |
| ------ | -------------------------------- |
| 400    | `invalid JSON` / validation error |
| 401    | `missing token` / `invalid token` |
| 500    | `failed to save transaction`     |

```sh
curl -X POST "$API_URL"/api/v1/expense \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount_paise":45050,"currency":"INR","bank_name":"HDFC","account_type":"savings","type":"debit","vendor":"Swiggy"}'
```

### Transaction object

```json
{
  "id": "8d0f6f8e-2a7c-4c39-9a57-3b1f8f0f2d11",
  "type": "debit",
  "amount": 45050,
  "currency": "INR",
  "merchant": "Reliance Fresh",
  "category": "groceries",
  "location": "Bengaluru",
  "payment_method": "card",
  "account_last4": "1234",
  "occurred_at": "2026-10-23T11:20:00Z",
  "source": "sms",
  "raw_text": "Rs.450.50 debited from A/c XX1234 at RELIANCE FRESH BANGALORE on 23-10-26",
  "confidence": 0.92,
  "note": "",
  "created_at": "2026-10-23T11:21:04Z"
}
```

| Field            | Notes                                                              |
| ---------------- | ------------------------------------------------------------------ |
| `type`           | `debit` (money out) or `credit` (refund / money in)                |
| `category`       | One of the slugs from `GET /api/v1/categories`                     |
| `location`       | City or area if detected, otherwise `null`                         |
| `payment_method` | `upi`, `card`, `netbanking`, `cash`, `wallet` or `unknown`         |
| `source`         | `manual`, `sms`, `notification` or `receipt`                       |
| `confidence`     | 0–1, how sure the detector is about merchant + category. `1` for manual entries |

### `POST /api/v1/transactions/parse` — Planned

Runs detection on raw text and returns what was found **without saving it**.
Use it to show the user a preview they can correct before saving.

```json
{
  "text": "Rs.2,000.00 spent on your HDFC Card XX9876 at HPCL FUEL STATION MUMBAI on 22-10-26",
  "source": "sms"
}
```

`200`:

```json
{
  "success": true,
  "message": "detected",
  "data": {
    "type": "debit",
    "amount": 200000,
    "currency": "INR",
    "merchant": "HPCL",
    "category": "fuel",
    "location": "Mumbai",
    "payment_method": "card",
    "account_last4": "9876",
    "occurred_at": "2026-10-22T00:00:00Z",
    "confidence": 0.95
  }
}
```

`422` when no amount is found (for example an OTP message or a promotion).

### `POST /api/v1/transactions` — Planned

Saves a transaction. Send **either** `text` (it is detected server-side, same
as `/parse`) **or** the fields directly. Any field you send overrides the
detected value.

```json
{ "text": "Rs.450.50 debited from A/c XX1234 at RELIANCE FRESH on 23-10-26", "source": "sms" }
```

```json
{
  "amount": 12000,
  "merchant": "Chai Point",
  "category": "food",
  "occurred_at": "2026-10-23T09:00:00Z",
  "payment_method": "upi"
}
```

`201` returns the transaction object. Sending the same `text` twice for the
same user returns the existing transaction with `200` instead of creating a
duplicate.

### `POST /api/v1/transactions/bulk` — Planned

Imports many messages at once, e.g. the first sync of the user's SMS inbox.

```json
{
  "source": "sms",
  "items": [
    { "text": "Rs.450.50 debited ...", "received_at": "2026-10-23T11:20:00Z" },
    { "text": "Your OTP is 123456" }
  ]
}
```

`200`:

```json
"data": {
  "created": 1,
  "duplicates": 0,
  "skipped": 1,
  "results": [
    { "index": 0, "status": "created", "id": "8d0f6f8e-..." },
    { "index": 1, "status": "skipped", "reason": "no amount detected" }
  ]
}
```

Max 500 items per request.

### `GET /api/v1/transactions` — Planned

Lists the user's transactions, newest first.

| Query      | Example          | Notes                         |
| ---------- | ---------------- | ----------------------------- |
| `from`     | `2026-10-01`     |                               |
| `to`       | `2026-11-01`     |                               |
| `category` | `fuel`           | Repeatable: `category=fuel&category=groceries` |
| `merchant` | `HPCL`           | Case-insensitive contains     |
| `type`     | `debit`          |                               |
| `q`        | `fresh`          | Search merchant, note, raw text |
| `page`, `limit` |             | See pagination                |

### `GET /api/v1/transactions/{id}` — Planned

Returns one transaction.

### `PATCH /api/v1/transactions/{id}` — Planned

Corrects a transaction. Send only the fields to change:

```json
{ "category": "groceries", "merchant": "DMart", "remember": true }
```

With `remember: true`, the merchant → category correction is saved as a
merchant rule, so future transactions from that merchant are categorised the
same way.

### `DELETE /api/v1/transactions/{id}` — Planned

Soft-deletes the transaction. Returns `200`.

---

## Categories

### `GET /api/v1/categories` — Planned

```json
"data": [
  { "slug": "groceries",     "name": "Groceries & Supermarket" },
  { "slug": "fuel",          "name": "Fuel / Petrol" },
  { "slug": "food",          "name": "Food & Dining" },
  { "slug": "transport",     "name": "Transport" },
  { "slug": "shopping",      "name": "Shopping" },
  { "slug": "bills",         "name": "Bills & Utilities" },
  { "slug": "health",        "name": "Health & Pharmacy" },
  { "slug": "entertainment", "name": "Entertainment" },
  { "slug": "travel",        "name": "Travel" },
  { "slug": "transfers",     "name": "Transfers" },
  { "slug": "other",         "name": "Other" }
]
```

## Merchant rules

User-specific overrides that take priority over the built-in keyword list.

### `GET /api/v1/merchant-rules` — Planned

```json
"data": [
  { "id": "c1f...", "pattern": "SRI BALAJI STORES", "category": "groceries", "merchant": "Sri Balaji Stores" }
]
```

### `POST /api/v1/merchant-rules` — Planned

```json
{ "pattern": "SRI BALAJI", "category": "groceries", "merchant": "Sri Balaji Stores" }
```

`pattern` is matched case-insensitively against the detected merchant text.
`201` returns the rule. Add `"apply_to_existing": true` to re-categorise past
transactions that match.

### `DELETE /api/v1/merchant-rules/{id}` — Planned

---

## Analytics

All analytics endpoints accept `from` and `to` (defaults to the current month)
and only count `debit` transactions unless stated otherwise. Refunds
(`credit`) are subtracted from the matching category.

### `GET /api/v1/analytics/summary` — Planned

```json
"data": {
  "from": "2026-10-01",
  "to": "2026-11-01",
  "currency": "INR",
  "total_spent": 2845000,
  "total_refunds": 50000,
  "transaction_count": 64,
  "average_transaction": 44453,
  "daily_average": 91774,
  "top_category": { "slug": "groceries", "amount": 920000 },
  "top_merchant": { "name": "DMart", "amount": 410000 },
  "previous_period": {
    "total_spent": 2510000,
    "change_percent": 13.3
  }
}
```

`previous_period` is the range of the same length immediately before `from`.

### `GET /api/v1/analytics/categories` — Planned

Spend per category, largest first.

```json
"data": {
  "total_spent": 2845000,
  "categories": [
    { "slug": "groceries", "amount": 920000, "percent": 32.3, "count": 14, "change_percent": 4.1 },
    { "slug": "fuel",      "amount": 600000, "percent": 21.1, "count": 5,  "change_percent": 22.5 },
    { "slug": "food",      "amount": 480000, "percent": 16.9, "count": 21, "change_percent": -8.0 }
  ]
}
```

### `GET /api/v1/analytics/merchants` — Planned

Top merchants. Extra query: `category` (filter), `limit` (default 10).

```json
"data": [
  { "merchant": "DMart", "category": "groceries", "amount": 410000, "count": 4, "last_visit": "2026-10-21T13:02:00Z" },
  { "merchant": "HPCL",  "category": "fuel",      "amount": 400000, "count": 2, "last_visit": "2026-10-22T00:00:00Z" }
]
```

### `GET /api/v1/analytics/locations` — Planned

Spend grouped by detected location. Transactions without a location are
grouped under `null`.

```json
"data": [
  { "location": "Bengaluru", "amount": 1900000, "count": 41 },
  { "location": "Mumbai",    "amount": 600000,  "count": 6 },
  { "location": null,        "amount": 345000,  "count": 17 }
]
```

### `GET /api/v1/analytics/trend` — Planned

Spend over time, for line or bar charts.

| Query      | Values                    | Default |
| ---------- | ------------------------- | ------- |
| `interval` | `day`, `week`, `month`    | `day`   |
| `category` | category slug (optional)  | all     |

```json
"data": {
  "interval": "week",
  "category": "fuel",
  "points": [
    { "period_start": "2026-10-05", "amount": 150000, "count": 1 },
    { "period_start": "2026-10-12", "amount": 0,      "count": 0 },
    { "period_start": "2026-10-19", "amount": 450000, "count": 4 }
  ]
}
```

Empty periods are included with `0`, so charts don't skip gaps.

### `GET /api/v1/analytics/insights` — Planned

Short, ready-to-display observations computed from the endpoints above.

```json
"data": [
  {
    "type": "category_spike",
    "category": "fuel",
    "message": "Fuel spending is up 22% compared to last month.",
    "change_percent": 22.5
  },
  {
    "type": "frequent_merchant",
    "merchant": "DMart",
    "message": "You visited DMart 4 times this month, spending ₹4,100 in total."
  },
  {
    "type": "large_transaction",
    "transaction_id": "8d0f6f8e-...",
    "message": "₹12,500 at Croma is your largest purchase this month."
  }
]
```

Insight types: `category_spike`, `category_drop`, `frequent_merchant`,
`large_transaction`, `new_merchant`, `weekend_spending`.
