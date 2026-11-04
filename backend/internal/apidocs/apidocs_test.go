package apidocs

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
)

func TestDocsAreServed(t *testing.T) {
	r := chi.NewRouter()
	Register(r)

	for path, want := range map[string]string{
		"/docs":              "text/html",
		"/docs/openapi.yaml": "application/yaml",
		"/docs/theme.css":    "text/css",
	} {
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != http.StatusOK {
			t.Errorf("GET %s: status %d", path, rec.Code)
		}
		if got := rec.Header().Get("Content-Type"); !strings.HasPrefix(got, want) {
			t.Errorf("GET %s: Content-Type %q, want %s", path, got, want)
		}
		if rec.Body.Len() == 0 {
			t.Errorf("GET %s: empty body", path)
		}
	}
}

// Every route the API serves must be in the spec, so the docs stay complete.
func TestSpecListsEveryRoute(t *testing.T) {
	routes := []string{
		"/api/v1/register", "/api/v1/login", "/api/v1/auth/refresh",
		"/api/v1/profile", "/api/v1/users",
		"/api/v1/expense", "/api/v1/expenses", "/api/v1/expenses/monthly",
		"/api/v1/analytics/overview",
		"/api/v1/expenses/{id}/category", "/api/v1/categories",
		"/api/v1/create-group", "/api/v1/groups", "/api/v1/groups/{groupID}/expenses",
		"/api/v1/presence/temporary-id",
		"/api/v1/presence/sightings",
	}
	for _, route := range routes {
		if !strings.Contains(string(spec), "\n  "+route+":\n") {
			t.Errorf("openapi.yaml has no path %s", route)
		}
	}
}
