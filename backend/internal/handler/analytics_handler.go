package handler

import (
	"log"
	"my_app/backend/internal/adapters/response"
	"my_app/backend/internal/analytics"
	"net/http"
	"time"
)

type AnalyticsHandler struct {
	analytics *analytics.Service
}

func NewAnalyticsHandler(svc *analytics.Service) *AnalyticsHandler {
	return &AnalyticsHandler{analytics: svc}
}

// Overview returns spending insights for ?from=&to= (YYYY-MM-DD, inclusive).
// Defaults to the current calendar month in India.
func (h *AnalyticsHandler) Overview(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}

	from, to, err := analytics.ParsePeriod(
		r.URL.Query().Get("from"),
		r.URL.Query().Get("to"),
		time.Now(),
	)
	if err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	overview, err := h.analytics.Overview(userID, from, to)
	if err != nil {
		log.Printf("analytics overview: %v", err)
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "failed to load insights",
		})
		return
	}

	response.JSON(w, http.StatusOK, response.Response{
		Success: true,
		Message: "ok",
		Data:    overview,
	})
}
