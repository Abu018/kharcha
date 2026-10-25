package middleware

import (
	"context"
	"log"
	"my_app/backend/internal/adapters/response"
	"my_app/backend/internal/utils"
	"net/http"
	"strings"

	"github.com/Nerzal/gocloak/v13"
	"github.com/golang-jwt/jwt/v5"
)

type ctxKey string

const userIDKey ctxKey = "user_id"

func Auth(client *gocloak.GoCloak, kc utils.KeycloakConfig) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			parts := strings.SplitN(r.Header.Get("Authorization"), " ", 2)
			if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || parts[1] == "" {
				w.Header().Set("WWW-Authenticate", "Bearer")
				response.JSON(w, http.StatusUnauthorized, response.Response{Success: false, Message: "missing token"})
				return
			}
			raws := parts[1]
			rpt, err := client.RetrospectToken(r.Context(), raws, kc.ClientID, kc.ClientSecret, kc.Realm)
			if err != nil {
				log.Printf("introspection failed: %v", err)
				response.JSON(w, http.StatusServiceUnavailable, response.Response{Success: false, Message: "auth service unavailable"})
				return
			}
			if rpt == nil || rpt.Active == nil || !*rpt.Active {
				w.Header().Set("WWW-Authenticate", `Bearer error="invalid_token"`)
				response.JSON(w, http.StatusUnauthorized, response.Response{Success: false, Message: "invalid token"})
				return
			}

			// Keycloak has already validated the token, so the claims can be read without re-verifying the signature.
			claims := jwt.MapClaims{}
			if _, _, err := jwt.NewParser().ParseUnverified(raws, claims); err != nil {
				response.JSON(w, http.StatusUnauthorized, response.Response{Success: false, Message: "invalid token"})
				return
			}
			sub, _ := claims["sub"].(string)
			ctx := context.WithValue(r.Context(), userIDKey, sub)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func UserIDFromContext(ctx context.Context) string {
	id, _ := ctx.Value(userIDKey).(string)
	return id
}
