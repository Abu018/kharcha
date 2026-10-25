# Spending detection and analytics

Status: **Planned.** This describes how the API will turn raw payment text into
categorised transactions and analytics. The endpoints are in [API.md](API.md).

## Overview

```
raw text ──► normalise ──► detect fields ──► categorise ──► score ──► save
 (SMS,                     amount, type,     user rules,     confidence
  UPI,                     merchant,         keyword list,
  receipt)                 location, date,   fallback
                           payment method
                                                                   │
                                                                   ▼
                                               analytics (summary, categories,
                                               merchants, locations, trend,
                                               insights)
```

Detection runs on the server so every client gets the same result and the
rules can be improved without shipping a new app. `POST
/api/v1/transactions/parse` runs the pipeline without saving, so the app can
show a preview the user can correct.

## Inputs

| `source`       | Example                                                                 |
| -------------- | ----------------------------------------------------------------------- |
| `sms`          | `Rs.450.50 debited from A/c XX1234 at RELIANCE FRESH BANGALORE on 23-10-26` |
| `notification` | `Paid ₹2,000 to HPCL Fuel Station via UPI. UPI Ref 4291...`             |
| `receipt`      | Text extracted from a photo of a bill (OCR runs on the device)          |
| `manual`       | Fields typed by the user; detection is skipped                          |

## 1. Normalise

- Trim, collapse whitespace, keep the original in `raw_text`.
- Upper-case a copy for matching.
- Replace currency variants with one token: `Rs`, `Rs.`, `INR`, `₹` → `INR`.
- Drop messages that are clearly not spends before going further: OTPs
  (`OTP`, `one time password`), promotions (`offer`, `cashback upto`, `win`),
  balance-only alerts (`available balance` without a debit/credit verb).
  These return `422` from `/parse` and `skipped` from `/bulk`.

## 2. Detect fields

### Amount

Regex over the normalised text:

```
(?:INR)\s*([0-9]{1,3}(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)
```

- Handles Indian grouping (`1,00,000.00`) and western grouping (`100,000.00`).
- Stored as an integer in paise: `450.50` → `45050`.
- If several amounts appear, prefer the one closest to a debit/credit verb and
  ignore amounts after `avl bal`, `available balance`, `limit`.
- No amount → the message is rejected with `422`.

### Type

| Keywords                                                         | `type`   |
| ---------------------------------------------------------------- | -------- |
| `debited`, `spent`, `paid`, `sent`, `purchase`, `withdrawn`      | `debit`  |
| `credited`, `refund`, `reversed`, `received`, `cashback credited` | `credit` |

### Merchant

Tried in order; the first match wins:

1. Text after `at ` / `to ` / `towards ` / `Info:` up to ` on `, ` via `,
   ` ref`, ` UPI`, a date or the end of the sentence.
2. UPI VPA: `dmart@icici` → `DMART`; `paytmqr...@paytm` gives no merchant.
3. First line of a receipt.

Then clean it up: strip trailing city names (they go to `location`), store
numbers (`#1234`), `PVT LTD`, `LTD`, `INDIA`, and title-case it. A small alias
table maps variants to one name (`D MART`, `AVENUE SUPERMARTS` → `DMart`;
`IOCL`, `INDIAN OIL` → `Indian Oil`).

### Location

- If the merchant text ends with a known city or area (`BANGALORE`,
  `BENGALURU`, `MUMBAI`, `HSR LAYOUT`), move it to `location`.
- Normalise spellings: `BANGALORE` → `Bengaluru`, `BOMBAY` → `Mumbai`.
- Receipts: look for a city or PIN code (`560102`) in the address lines.
- Not found → `null`. Location is never guessed.

The city list starts with the top ~200 Indian cities and grows from the user
corrections in merchant rules.

### Date

Parse `dd-mm-yy`, `dd-mm-yyyy`, `dd/mm/yy`, `dd-Mon-yy`, `yyyy-mm-dd`. If the
text has no date, use the `received_at` time sent by the app, then the
server's current time.

### Payment method and account

| Pattern                              | `payment_method` |
| ------------------------------------ | ---------------- |
| `UPI`, `VPA`, `@` handle             | `upi`            |
| `card`, `credit card`, `debit card`  | `card`           |
| `NEFT`, `IMPS`, `RTGS`, `net banking`| `netbanking`     |
| `wallet`, `Paytm wallet`             | `wallet`         |
| none                                 | `unknown`        |

`XX1234`, `**1234`, `ending 1234` → `account_last4: "1234"`. Full card or
account numbers are never stored.

## 3. Categorise

Checked in this order; the first match wins:

1. **User merchant rules** (`/api/v1/merchant-rules`). Created by hand or when
   the user corrects a category with `remember: true`.
2. **Known merchants**: the alias table above maps each brand to a category.
3. **Keywords** in the merchant text.
4. Otherwise `other`.

### Built-in list (initial)

| Category    | Known merchants                                                                                     | Keywords                                                    |
| ----------- | --------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `groceries` | DMart, Reliance Fresh, Reliance Smart, More, Spencer's, Big Bazaar, Star Bazaar, Nature's Basket, Ratnadeep, BigBasket, Blinkit, Zepto, Swiggy Instamart, JioMart | `SUPERMARKET`, `HYPERMARKET`, `MART`, `KIRANA`, `PROVISION`, `GROCERY`, `FRESH` |
| `fuel`      | HPCL, BPCL, Indian Oil (IOCL), Shell, Nayara, Jio-bp, Essar                                          | `PETROL`, `FUEL`, `FILLING STATION`, `SERVICE STATION`, `PETROLEUM`, `PUMP`, `CNG` |
| `food`      | Swiggy, Zomato, McDonald's, Domino's, KFC, Starbucks, Chai Point                                     | `RESTAURANT`, `CAFE`, `HOTEL`, `BAKERY`, `FOODS`            |
| `transport` | Uber, Ola, Rapido, Namma Metro, IRCTC (suburban)                                                     | `METRO`, `CAB`, `TAXI`, `PARKING`, `FASTAG`, `TOLL`         |
| `shopping`  | Amazon, Flipkart, Myntra, Ajio, Croma, Reliance Digital                                              | `STORE`, `RETAIL`, `FASHION`, `ELECTRONICS`                 |
| `bills`     | Airtel, Jio, Vi, BESCOM, Tata Power, ACT Fibernet                                                    | `ELECTRICITY`, `RECHARGE`, `BROADBAND`, `GAS`, `WATER`      |
| `health`    | Apollo Pharmacy, MedPlus, PharmEasy, 1mg, Practo                                                     | `PHARMACY`, `MEDICAL`, `CHEMIST`, `HOSPITAL`, `CLINIC`, `LAB` |
| `entertainment` | BookMyShow, PVR, INOX, Netflix, Spotify, Hotstar                                                 | `CINEMA`, `MOVIES`, `GAMING`                                |
| `travel`    | MakeMyTrip, Goibibo, IndiGo, Air India, IRCTC, OYO                                                   | `AIRLINES`, `RAIL`, `HOTEL BOOKING`, `TRAVELS`              |
| `transfers` | —                                                                                                    | UPI to a person's name or a phone number VPA                |

Card SMS sometimes include a merchant category code. When present it overrides
keywords: `5411` → `groceries`, `5541`/`5542` → `fuel`, `5812`/`5814` → `food`,
`5912` → `health`.

Ambiguous words are only used together with a second signal. For example
`FRESH` alone is too weak (it could be a juice bar), so it counts towards
`groceries` only when `MART`, `SUPERMARKET` or a known brand is also present.

## 4. Confidence

`confidence` (0–1) tells the app whether to ask the user to confirm:

| Signal                                   | Score |
| ---------------------------------------- | ----- |
| Category from a user merchant rule       | 1.00  |
| Known merchant from the alias table      | 0.95  |
| Merchant category code in the SMS        | 0.90  |
| Two or more keywords agree               | 0.80  |
| One keyword                              | 0.60  |
| No merchant found, or category `other`   | 0.30  |

Below `0.7` the app shows the transaction as "Needs review". Manual entries are
always `1`.

## 5. Duplicates

The same spend often arrives twice (bank SMS and UPI notification). A
transaction is treated as a duplicate when another one for the same user has:

- the same `raw_text` hash, **or**
- the same `amount`, `type` and `account_last4`, a matching merchant, and
  `occurred_at` within 10 minutes.

Duplicates are not saved; `/transactions` returns the existing one with `200`.

## Analytics

All analytics are computed per user with SQL aggregates over `transactions`.
Default range is the current calendar month; `previous_period` is the range of
the same length just before it.

| Endpoint                         | What it answers                                       |
| -------------------------------- | ----------------------------------------------------- |
| `GET /api/v1/analytics/summary`    | How much did I spend, and is it more than last month? |
| `GET /api/v1/analytics/categories` | Where is the money going (supermarket vs petrol vs …)? |
| `GET /api/v1/analytics/merchants`  | Which shops / petrol pumps do I use most?             |
| `GET /api/v1/analytics/locations`  | Which cities or areas do I spend in?                  |
| `GET /api/v1/analytics/trend`      | How does spending change day by day or week by week?  |
| `GET /api/v1/analytics/insights`   | Plain-language observations to show on the home screen |

Rules shared by all of them:

- Only `debit` counts as spending. A `credit` (refund) is subtracted from the
  category of the original merchant.
- `transfers` are excluded from totals by default; pass
  `include_transfers=true` to count them.
- Soft-deleted transactions are ignored.

### Insights

| Type                | Rule                                                                 |
| ------------------- | -------------------------------------------------------------------- |
| `category_spike`    | Category up ≥ 20% vs previous period and at least ₹500 more           |
| `category_drop`     | Category down ≥ 20% vs previous period and at least ₹500 less         |
| `frequent_merchant` | Same merchant ≥ 4 times in the period                                |
| `large_transaction` | Single debit ≥ 3× the user's median transaction in the period        |
| `new_merchant`      | First transaction ever at a merchant, above ₹1,000                   |
| `weekend_spending`  | Weekend daily average ≥ 1.5× weekday daily average                   |

Examples for fuel and groceries:

- "Fuel spending is up 22% compared to last month."
- "You visited DMart 4 times this month, spending ₹4,100 in total."
- "Groceries are 32% of your spending this month."

## Data model

```sql
CREATE TABLE transactions (
    id              uuid PRIMARY KEY,
    user_id         uuid NOT NULL REFERENCES users(id),
    type            text NOT NULL CHECK (type IN ('debit','credit')),
    amount          bigint NOT NULL CHECK (amount > 0),   -- paise
    currency        char(3) NOT NULL DEFAULT 'INR',
    merchant        text,
    category        text NOT NULL DEFAULT 'other',
    location        text,
    payment_method  text NOT NULL DEFAULT 'unknown',
    account_last4   char(4),
    occurred_at     timestamptz NOT NULL,
    source          text NOT NULL,
    raw_text        text,
    raw_text_hash   char(64),
    confidence      real NOT NULL DEFAULT 1,
    note            text NOT NULL DEFAULT '',
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz
);
CREATE INDEX ON transactions (user_id, occurred_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX ON transactions (user_id, category, occurred_at) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX ON transactions (user_id, raw_text_hash) WHERE raw_text_hash IS NOT NULL;

CREATE TABLE merchant_rules (
    id          uuid PRIMARY KEY,
    user_id     uuid NOT NULL REFERENCES users(id),
    pattern     text NOT NULL,
    merchant    text,
    category    text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, pattern)
);
```

In the Go code these become GORM models in `internal/models`, alongside
`User` and `AuditLog`, and are added to `internal/db/migration.go`.

## Privacy

- Raw SMS never leave the device unless they look like a transaction. The app
  filters by sender ID (`VM-HDFCBK`, `AD-ICICIB`, …) and keywords before
  uploading.
- Only the last 4 digits of a card or account are stored.
- `raw_text` can be cleared per transaction, or for the whole account, without
  losing the detected fields.
- Every query is scoped to the `user_id` from the access token.

## Suggested Go layout

```
backend/internal/
  detect/        pure functions: Parse(text, source) -> Detected
    amount.go
    merchant.go
    location.go
    category.go  built-in keyword and alias tables
    detect_test.go  table tests with real SMS samples
  transactions/  service + repository interface
  analytics/     service + SQL queries
  handler/       HTTP handlers for /api/v1/transactions, /analytics, ...
  postgres/      repository implementations
```

Keeping `detect` free of HTTP and database code makes it easy to unit-test
with a growing list of real messages.
