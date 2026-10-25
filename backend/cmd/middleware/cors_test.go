package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCORS(t *testing.T) {
	called := false
	h := CORS([]string{"https://app.example.com"})(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
	}))

	cases := []struct {
		name, method, origin string
		wantAllowed          bool
		wantNext             bool
	}{
		{"flutter web preflight", http.MethodOptions, "http://localhost:52564", true, false},
		{"loopback ip", http.MethodPost, "http://127.0.0.1:3000", true, true},
		{"configured origin", http.MethodPost, "https://app.example.com", true, true},
		{"unknown origin", http.MethodPost, "https://evil.example", false, true},
		{"no origin (mobile app)", http.MethodPost, "", false, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			called = false
			req := httptest.NewRequest(c.method, "/api/v1/login", nil)
			if c.origin != "" {
				req.Header.Set("Origin", c.origin)
			}
			if c.method == http.MethodOptions {
				req.Header.Set("Access-Control-Request-Method", "POST")
			}
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)

			got := rec.Header().Get("Access-Control-Allow-Origin")
			if c.wantAllowed && got != c.origin {
				t.Errorf("Allow-Origin = %q, want %q", got, c.origin)
			}
			if !c.wantAllowed && got != "" {
				t.Errorf("Allow-Origin = %q, want none", got)
			}
			if called != c.wantNext {
				t.Errorf("next called = %v, want %v", called, c.wantNext)
			}
		})
	}
}
