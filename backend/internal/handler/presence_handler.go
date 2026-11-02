package handler

import (
	"encoding/json"
	"log"
	"my_app/backend/internal/adapters/response"
	"my_app/backend/internal/dto"
	"my_app/backend/internal/models"
	"my_app/backend/internal/presence"
	"net/http"

	"github.com/google/uuid"
)

type presenceIDs interface {
	CurrentTemporaryID(userID uuid.UUID) (current, next models.Ephemeral, err error)
}

type sightingsResolver interface {
	Resolve(viewer uuid.UUID, in []dto.Sighting) (dto.NearbyUsers, error)
}

type PresenceHandler struct {
	ids    presenceIDs
	nearby sightingsResolver
}

func NewPresenceHandler(ids presenceIDs, nearby sightingsResolver) *PresenceHandler {
	return &PresenceHandler{ids: ids, nearby: nearby}
}

// TemporaryID handles GET /api/v1/presence/temporary-id for the signed-in user.
func (h *PresenceHandler) TemporaryID(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}
	current, next, err := h.ids.CurrentTemporaryID(userID)
	if err != nil {
		log.Printf("temporary id for %s: %v", userID, err)
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "could not load temporary id",
		})
		return
	}
	response.JSON(w, http.StatusOK, response.Response{
		Success: true,
		Message: "temporary id",
		Data: dto.TemporaryID{
			TemporaryID:     current.Key,
			ExpiresAt:       current.ExpiresAt,
			NextTemporaryID: next.Key,
			NextExpiresAt:   next.ExpiresAt,
		},
	})
}

// Sightings handles POST /api/v1/presence/sightings. The phone sends IDs it
// heard over BLE; the server returns eligible people, not secrets.
func (h *PresenceHandler) Sightings(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}
	var input dto.SightingsInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: "invalid JSON",
		})
		return
	}
	if len(input.Sightings) > presence.MaxSightings {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: "too many sightings",
		})
		return
	}
	out, err := h.nearby.Resolve(userID, input.Sightings)
	if err != nil {
		log.Printf("sightings for %s: %v", userID, err)
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "could not resolve nearby users",
		})
		return
	}
	response.JSON(w, http.StatusOK, response.Response{
		Success: true,
		Message: "nearby users",
		Data:    out,
	})
}
