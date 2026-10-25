.DEFAULT_GOAL := help

BACKEND := backend
FRONTEND := frontend

.PHONY: help
help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# --- backend -----------------------------------------------------------------

.PHONY: api
api: ## Run the Go API (address from backend/.env)
	cd $(BACKEND) && go run ./cmd/api

.PHONY: api-build
api-build: ## Compile the API to backend/bin/api
	cd $(BACKEND) && go build -o bin/api ./cmd/api

.PHONY: api-test
api-test: ## Run Go tests
	cd $(BACKEND) && go test ./...

.PHONY: api-lint
api-lint: ## Format check and vet the Go code
	cd $(BACKEND) && gofmt -l . && go vet ./...

.PHONY: api-tidy
api-tidy: ## Sync go.mod and go.sum
	cd $(BACKEND) && go mod tidy

# --- frontend ----------------------------------------------------------------

.PHONY: app
app: ## Run the Flutter app; needs API_BASE_URL, e.g. make app API_BASE_URL=http://host:port
	@test -n "$(API_BASE_URL)" || (echo "Set API_BASE_URL, e.g. make app API_BASE_URL=http://host:port" && exit 1)
	cd $(FRONTEND) && flutter run --dart-define=API_BASE_URL=$(API_BASE_URL)

.PHONY: app-deps
app-deps: ## Fetch Dart packages
	cd $(FRONTEND) && flutter pub get

.PHONY: app-test
app-test: ## Run Flutter tests
	cd $(FRONTEND) && flutter test

.PHONY: app-lint
app-lint: ## Analyze the Dart code
	cd $(FRONTEND) && flutter analyze

.PHONY: app-build
app-build: ## Build a release APK
	@test -n "$(API_BASE_URL)" || (echo "Set API_BASE_URL, e.g. make app-build API_BASE_URL=https://api.example.com" && exit 1)
	cd $(FRONTEND) && flutter build apk --release --dart-define=API_BASE_URL=$(API_BASE_URL)

# --- combined ----------------------------------------------------------------

.PHONY: test
test: api-test app-test ## Run every test suite

.PHONY: lint
lint: api-lint app-lint ## Lint both projects

.PHONY: clean
clean: ## Remove build artifacts from both projects
	rm -rf $(BACKEND)/bin
	cd $(FRONTEND) && flutter clean
