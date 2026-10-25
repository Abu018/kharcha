package utils

import (
	"strings"
	"testing"
)

var requiredKeys = []string{
	"HOST", "PORT",
	"DB_HOST", "DB_PORT", "DB_USER", "DB_PASSWORD", "DB_NAME", "DB_SSLMODE",
	"KEYCLOAK_URL", "KEYCLOAK_REALM", "KEYCLOAK_CLIENT_ID", "KEYCLOAK_CLIENT_SECRET",
	"KEYCLOAK_ADMIN_REALM", "KEYCLOAK_ADMIN_USER", "KEYCLOAK_ADMIN_PASSWORD",
	"CLASSIFIER_URL", "CLASSIFIER_MODEL",
}

func TestLoadReadsEveryRequiredSetting(t *testing.T) {
	for _, k := range requiredKeys {
		t.Setenv(k, "v-"+k)
	}
	t.Setenv("CORS_ALLOWED_ORIGINS", "https://a.example, https://b.example")

	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Keycloak.Realm != "v-KEYCLOAK_REALM" || cfg.Classifier.Model != "v-CLASSIFIER_MODEL" {
		t.Errorf("unexpected config: %+v", cfg)
	}
	if len(cfg.CORSOrigins) != 2 {
		t.Errorf("CORSOrigins = %v", cfg.CORSOrigins)
	}
}

func TestLoadListsMissingSettings(t *testing.T) {
	for _, k := range requiredKeys {
		t.Setenv(k, "x")
	}
	t.Setenv("KEYCLOAK_REALM", "")
	t.Setenv("DB_PASSWORD", "")

	_, err := Load()
	if err == nil {
		t.Fatal("expected an error for missing settings")
	}
	for _, k := range []string{"KEYCLOAK_REALM", "DB_PASSWORD"} {
		if !strings.Contains(err.Error(), k) {
			t.Errorf("error %q does not mention %s", err, k)
		}
	}
}
