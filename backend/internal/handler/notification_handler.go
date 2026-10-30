package handler

import (
	"encoding/json"
	"errors"
	"my_app/backend/internal/adapters/response"
	notification "my_app/backend/internal/notificaition"
	"net/http"
)

type NotificationHandler struct {
	notification *notification.NotificationService
}

func NewNotificationHandler(svc *notification.NotificationService) *NotificationHandler {
	return &NotificationHandler{notification: svc}
}

type InputRegisterToken struct {
	Token string `json:"token"`
}

func (h *NotificationHandler) RegisterDeviceToken(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}

	var input InputRegisterToken
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: "invalid request body",
		})
		return
	}

	if err := h.notification.RegisterDeviceToken(userID, input.Token); err != nil {
		if errors.Is(err, notification.ErrEmptyToken) {
			response.JSON(w, http.StatusBadRequest, response.Response{
				Success: false,
				Message: err.Error(),
			})
			return
		}
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "internal server error",
		})
		return
	}

	response.JSON(w, http.StatusCreated, response.Response{
		Success: true,
		Message: "device token registered",
	})
}
