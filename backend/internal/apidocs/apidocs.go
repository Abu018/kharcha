// Package apidocs serves the OpenAPI spec and a Swagger UI page at /docs.
package apidocs

import (
	_ "embed"
	"net/http"

	"github.com/go-chi/chi/v5"
)

var (
	//go:embed openapi.yaml
	spec []byte
	//go:embed index.html
	page []byte
	//go:embed theme.css
	theme []byte
)

// Register adds GET /docs (Swagger UI), /docs/openapi.yaml and
// /docs/theme.css. They are public: the spec has no secrets.
func Register(r chi.Router) {
	serve := func(contentType string, body []byte) http.HandlerFunc {
		return func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", contentType)
			// Revalidate so a deploy shows the new spec and theme at once.
			w.Header().Set("Cache-Control", "no-cache")
			_, _ = w.Write(body)
		}
	}
	r.Get("/docs", serve("text/html; charset=utf-8", page))
	r.Get("/docs/", serve("text/html; charset=utf-8", page))
	r.Get("/docs/openapi.yaml", serve("application/yaml", spec))
	r.Get("/docs/theme.css", serve("text/css; charset=utf-8", theme))
}
