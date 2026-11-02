package handler

import (
	"bytes"
	"encoding/json"
	"my_app/backend/cmd/middleware"
	"my_app/backend/internal/dto"
	"my_app/backend/internal/models"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
)

type stubIDs struct{}

func (stubIDs) CurrentTemporaryID(uuid.UUID) (models.Ephemeral, models.Ephemeral, error) {
	return models.Ephemeral{}, models.Ephemeral{}, nil
}

type stubSightings struct {
	viewer uuid.UUID
	in     []dto.Sighting
}

func (s *stubSightings) Resolve(viewer uuid.UUID, in []dto.Sighting) (dto.NearbyUsers, error) {
	s.viewer, s.in = viewer, in
	return dto.NearbyUsers{Users: []dto.NearbyUser{{
		UserID:      viewer,
		EphemeralID: in[0].EphemeralID,
		FirstName:   "Amit",
		RSSI:        in[0].RSSI,
		Seen:        in[0].Seen,
		InRange:     true,
	}}}, nil
}

func TestSightingsUsesTokenUserAndBody(t *testing.T) {
	userID := uuid.MustParse("11111111-1111-1111-1111-111111111111")
	nearby := &stubSightings{}
	h := NewPresenceHandler(stubIDs{}, nearby)

	body := []byte(`{"sightings":[{"ephemeral_id":"1122334455667788","rssi":-58,"seen":4}]}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/presence/sightings", bytes.NewReader(body))
	req = req.WithContext(middleware.WithUserID(req.Context(), userID.String()))
	rec := httptest.NewRecorder()
	h.Sightings(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status %d body %s", rec.Code, rec.Body.Bytes())
	}
	if nearby.viewer != userID {
		t.Errorf("viewer %s, want %s", nearby.viewer, userID)
	}
	if len(nearby.in) != 1 || nearby.in[0].EphemeralID != "1122334455667788" {
		t.Errorf("sightings %+v", nearby.in)
	}
	var env struct {
		Success bool `json:"success"`
		Data    struct {
			Users []dto.NearbyUser `json:"users"`
		} `json:"data"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &env); err != nil {
		t.Fatal(err)
	}
	if !env.Success || len(env.Data.Users) != 1 || env.Data.Users[0].FirstName != "Amit" {
		t.Errorf("envelope %+v", env)
	}
}

func TestSightingsRejectsTooMany(t *testing.T) {
	h := NewPresenceHandler(stubIDs{}, &stubSightings{})
	sightings := make([]map[string]any, 51)
	for i := range sightings {
		sightings[i] = map[string]any{"ephemeral_id": "1122334455667788", "rssi": -50, "seen": 1}
	}
	body, _ := json.Marshal(map[string]any{"sightings": sightings})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/presence/sightings", bytes.NewReader(body))
	req = req.WithContext(middleware.WithUserID(req.Context(), uuid.New().String()))
	rec := httptest.NewRecorder()
	h.Sightings(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status %d", rec.Code)
	}
}
