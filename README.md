# kharcha

Open-source expense tracker that reads payment messages (bank SMS, UPI
notifications), detects the amount, merchant and category, and turns them
into spending analytics.

```
backend/    Go API (chi, GORM + Postgres, Keycloak auth)
frontend/   Flutter app (Android, web)
docs/       API reference and analytics design
Makefile    Task runner for both projects
```

## Features

- Register and sign in through Keycloak; the app stays signed in using an
  offline refresh token kept in the Android Keystore, never the password
- Automatic expense detection from bank and UPI SMS on Android: recent
  history on first run, then new messages as they arrive, never saving one
  twice
- Categories from keyword rules plus a local LLM (Gemma via Ollama), with a
  background job that classifies anything saved while the model was offline
- Manual expenses, profile editing, spending summary and category breakdown
- Request audit logging

## Requirements

- Go 1.25+
- PostgreSQL 16+ and Keycloak 26+ (run them however you like, e.g. Docker)
- Flutter 3.13+ with the Android SDK
- Optional: [Ollama](https://ollama.com) for automatic categories

## Getting started

### 1. Configure

```sh
cp backend/.env.example backend/.env
```

The code has no built-in defaults: the API refuses to start and names any
missing setting.

Open `backend/.env` and fill in every value for your own environment:
database connection, Keycloak address, realm, client and admin account, and
the category model endpoint. Each setting is described by a comment in
`backend/.env.example`.

> **Never commit `backend/.env`.** It is git-ignored. Use your own realm and
> client names and strong, unique passwords and secrets; do not reuse values
> from examples.

### 2. Start Postgres and Keycloak

Run a PostgreSQL database and a Keycloak server, then point the database and
Keycloak settings in `backend/.env` at them. Docker files are not part of the
repo; keep your own local setup (any `docker-compose*.yml` or `Dockerfile` is
git-ignored).

### 3. Set up Keycloak (once)

In the Keycloak admin console:

1. Create a realm for the app's users.
2. In that realm, create a client with **Client authentication** on and
   **Direct access grants** ticked (leave Authorization off).
3. Copy the client secret from its **Credentials** tab into `backend/.env`,
   along with the realm and client names you chose.

Sign-in requests the `offline_access` scope so the app can stay signed in.
New realms grant it to users and clients by default.

### 4. Start the category model (optional)

Without a model every expense is saved as `Unknown` and categorised once the
model is reachable.

```sh
brew install ollama
brew services start ollama
ollama pull gemma3:4b          # or gemma3:1b if disk space is tight
```

Point the classifier settings in `backend/.env` at Ollama's
OpenAI-compatible endpoint and the model you pulled.

Common merchants are matched by keyword in
`backend/internal/expense/category.go` before the model is asked; add words
there to fix a merchant that keeps landing in the wrong category.

### 5. Run

```sh
make api                              # start the API
make app API_BASE_URL=<your-api-url>  # run the Flutter app on a connected device
make test       # Go tests + Flutter tests
make lint       # gofmt/go vet + flutter analyze
```

Run `make help` to list every task.

## API

Full reference with request and response examples: [docs/API.md](docs/API.md).
Design for spending detection and analytics:
[docs/ANALYTICS.md](docs/ANALYTICS.md). Planned APIs:
[docs/ROADMAP.md](docs/ROADMAP.md).

All routes live under `/api/v1`. Routes marked 🔒 need
`Authorization: Bearer <access_token>`.

| Method | Path                    | Description                                         |
| ------ | ----------------------- | --------------------------------------------------- |
| POST   | `/api/v1/register`      | Create an account                                   |
| POST   | `/api/v1/login`         | Get an access token and an offline refresh token    |
| POST   | `/api/v1/auth/refresh`  | Swap a refresh token for new tokens                 |
| PUT    | `/api/v1/profile` 🔒    | Update first and last name                          |
| POST   | `/api/v1/expense` 🔒    | Save a transaction; categorised automatically. Returns 200 with no data if `source_ref` was already saved |
| GET    | `/api/v1/expenses` 🔒   | List your transactions, newest first (`?limit=`, max 500) |

Example:

```sh
curl -X POST "$API_URL/api/v1/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"<your-password>"}'
```

## Backend layout

```
cmd/api/                 entrypoint: loads .env, migrates, starts the server
cmd/server/              HTTP server with timeouts
cmd/middleware/          audit logging, CORS, bearer-token auth
internal/handler/        HTTP handlers
internal/register/       auth service and repository interface
internal/expense/        transactions: categorisation rules, LLM classifier, backfill
internal/postgres/       repositories: Keycloak + Postgres
internal/models/         GORM models (User, Transaction, AuditLog)
internal/db/             migrations
internal/utils/          config from environment variables
internal/adapters/response/  JSON response envelope
```

## Frontend

Screens: sign in, register, home (monthly summary, category breakdown,
activity list), add expense and profile. On Android, **Turn on auto-detect**
asks for SMS access, imports recent payment messages and then adds new ones
while the app is open (or the next time it is opened). Parsing lives in
`lib/services/payment_parser.dart`; OTPs, reminders, failed payments and
offers are ignored. Messages are processed on the device and only the parsed
payment details are sent to your own API.

The API address must be passed at build time; the app has no default and
shows an error on every request without it:

```sh
cd frontend
flutter run --dart-define=API_BASE_URL=<your-api-url>
```

To run on a phone over USB, enable USB debugging, then forward the API port
so the phone can reach the API on your computer:

```sh
adb reverse tcp:<api-port> tcp:<api-port>
flutter run -d <device-id> --dart-define=API_BASE_URL=http://127.0.0.1:<api-port>
```

`flutter run -d chrome` runs the web build (no SMS detection).

Adding native code or plugins (e.g. `MainActivity.kt`, secure storage) needs
a full `flutter run`; hot reload will not pick them up.

## Security

- Secrets live only in `backend/.env`, which is git-ignored.
- The app never stores the user's password, only a revocable refresh token in
  the platform keystore.
- Please report security issues privately rather than in public issues.

## Contributing

Issues and pull requests are welcome. Run `make test` and `make lint` before
opening a pull request.
