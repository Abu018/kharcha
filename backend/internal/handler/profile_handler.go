package handler

import (
	"encoding/json"
	"errors"
	"log"
	"my_app/backend/internal/adapters/response"
	"my_app/backend/internal/models"
	"my_app/backend/internal/profile"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
)

// UpdateProfileInput is a partial update: omitted fields keep their value.
type UpdateProfileInput struct {
	FirstName *string `json:"first_name" validate:"omitempty,min=1,max=50"`
	LastName  *string `json:"last_name" validate:"omitempty,max=50"`
	Age       *int    `json:"age" validate:"omitempty,min=1,max=120"`
	// Monthly salary in whole rupees.
	Salary *int64 `json:"salary" validate:"omitempty,min=0"`
}
type TransactionInput struct {
	AmountPaise int64  `json:"amount_paise" validate:"required,gt=0"`
	Currency    string `json:"currency" validate:"required,len=3"`

	BankName    string `json:"bank_name" validate:"required"`
	AccountType string `json:"account_type" validate:"required,oneof=savings current credit_card upi_wallet"`
	Type        string `json:"type" validate:"required,oneof=debit credit"`

	Vendor    string `json:"vendor"`
	VendorUPI string `json:"vendor_upi"`

	// Optional; defaults to now.
	OccurredAt *time.Time `json:"occurred_at"`
	Source     string     `json:"source" validate:"omitempty,oneof=manual sms notification"`
	SourceRef  string     `json:"source_ref" validate:"max=100"`
}
type ProfileHandler struct {
	profile *profile.Service
}

func NewProfileHandler(svc *profile.Service) *ProfileHandler {
	return &ProfileHandler{profile: svc}
}

// GetProfile handles GET /api/v1/profile for the signed-in user.
func (h *ProfileHandler) GetProfile(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}
	user, err := h.profile.GetProfile(r.Context(), userID)
	if err != nil {
		profileError(w, userID, "get", err)
		return
	}
	response.JSON(w, http.StatusOK, response.Response{Success: true, Message: "profile", Data: profileData(user)})
}

// UpdateProfile handles PUT /api/v1/profile for the signed-in user.
func (h *ProfileHandler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}
	var input UpdateProfileInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "invalid JSON"})
		return
	}
	if input.FirstName != nil && strings.TrimSpace(*input.FirstName) == "" {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "first_name cannot be empty"})
		return
	}
	if err := validate.Struct(input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: err.Error()})
		return
	}

	user, err := h.profile.UpdateProfile(r.Context(), userID, profile.Update{
		FirstName: input.FirstName,
		LastName:  input.LastName,
		Age:       input.Age,
		Salary:    input.Salary,
	})
	if err != nil {
		profileError(w, userID, "update", err)
		return
	}
	response.JSON(w, http.StatusOK, response.Response{Success: true, Message: "profile updated", Data: profileData(user)})
}

const maxUserResults = 50

// ListUsers handles GET /api/v1/users?q=, the people that can be added to a
// group. Only names and emails are returned.
func (h *ProfileHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}
	users, err := h.profile.ListUsers(r.Context(), userID, r.URL.Query().Get("q"), maxUserResults)
	if err != nil {
		log.Printf("list users for %s: %v", userID, err)
		response.JSON(w, http.StatusInternalServerError, response.Response{Success: false, Message: "could not load users"})
		return
	}
	data := make([]map[string]any, 0, len(users))
	for _, u := range users {
		data = append(data, map[string]any{
			"user_id":    u.ID,
			"email":      u.Email,
			"first_name": u.FirstName,
			"last_name":  u.LastName,
		})
	}
	response.JSON(w, http.StatusOK, response.Response{Success: true, Message: "users", Data: data})
}

func profileData(user models.User) map[string]any {
	return map[string]any{
		"user_id":    user.ID,
		"email":      user.Email,
		"first_name": user.FirstName,
		"last_name":  user.LastName,
		"age":        user.Age,
		"salary":     user.Salary,
	}
}

func profileError(w http.ResponseWriter, userID uuid.UUID, action string, err error) {
	if errors.Is(err, profile.ErrNotFound) {
		response.JSON(w, http.StatusNotFound, response.Response{Success: false, Message: "profile not found"})
		return
	}
	log.Printf("%s profile %s: %v", action, userID, err)
	response.JSON(w, http.StatusInternalServerError, response.Response{Success: false, Message: "could not " + action + " profile"})
}
