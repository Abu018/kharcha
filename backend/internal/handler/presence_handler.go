package handler

import (
	"log"
	"my_app/backend/internal/adapters/response"
	"my_app/backend/internal/dto"
	"my_app/backend/internal/models"
	"net/http"

	"github.com/google/uuid"
)

type presenceIDs interface {
	CurrentTemporaryID(userID uuid.UUID) (current, next models.Ephemeral, err error)
}

type PresenceHandler struct {
	ids presenceIDs
}

func NewPresenceHandler(ids presenceIDs) *PresenceHandler {
	return &PresenceHandler{ids: ids}
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
