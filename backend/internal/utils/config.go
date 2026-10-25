package utils

import (
	"fmt"
	"os"
	"strings"
)

type ServerConfig struct {
	Host string
	Port string
}
type DBConfig struct {
	ServerConfig                  ServerConfig
	User, Password, Name, SSLMode string
}
type KeycloakConfig struct {
	URL, Realm, ClientID, ClientSecret   string
	AdminRealm, AdminUser, AdminPassword string
}

// ClassifierConfig points at an OpenAI-compatible chat completions endpoint
// (llama.cpp server, Ollama, LM Studio) serving the categorisation model.
type ClassifierConfig struct {
	URL, Model string
}
type Config struct {
	Server     ServerConfig
	DB         DBConfig
	Keycloak   KeycloakConfig
	Classifier ClassifierConfig
	// Browser origins allowed in addition to localhost, from the
	// comma-separated CORS_ALLOWED_ORIGINS.
	CORSOrigins []string
}

func GetEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

// Load reads the configuration from the environment. Every setting except
// CORS_ALLOWED_ORIGINS is required; there are no built-in defaults, so a
// deployment never silently runs with example values.
func Load() (*Config, error) {
	var missing []string
	need := func(key string) string {
		value := os.Getenv(key)
		if value == "" {
			missing = append(missing, key)
		}
		return value
	}

	cfg := &Config{
		Server: ServerConfig{
			Host: need("HOST"),
			Port: need("PORT"),
		},
		DB: DBConfig{
			ServerConfig: ServerConfig{
				Host: need("DB_HOST"),
				Port: need("DB_PORT"),
			},
			User:     need("DB_USER"),
			Password: need("DB_PASSWORD"),
			Name:     need("DB_NAME"),
			SSLMode:  need("DB_SSLMODE"),
		},
		Keycloak: KeycloakConfig{
			URL:           need("KEYCLOAK_URL"),
			Realm:         need("KEYCLOAK_REALM"),
			ClientID:      need("KEYCLOAK_CLIENT_ID"),
			ClientSecret:  need("KEYCLOAK_CLIENT_SECRET"),
			AdminRealm:    need("KEYCLOAK_ADMIN_REALM"),
			AdminUser:     need("KEYCLOAK_ADMIN_USER"),
			AdminPassword: need("KEYCLOAK_ADMIN_PASSWORD"),
		},
		Classifier: ClassifierConfig{
			URL:   need("CLASSIFIER_URL"),
			Model: need("CLASSIFIER_MODEL"),
		},
		CORSOrigins: splitList(GetEnv("CORS_ALLOWED_ORIGINS", "")),
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("missing required settings (see backend/.env.example): %s", strings.Join(missing, ", "))
	}
	return cfg, nil
}

func splitList(s string) []string {
	var out []string
	for _, part := range strings.Split(s, ",") {
		if part = strings.TrimSpace(part); part != "" {
			out = append(out, part)
		}
	}
	return out
}

func (s *ServerConfig) Addr() string {
	return s.Host + ":" + s.Port
}
