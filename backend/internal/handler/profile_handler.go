package handler

import (
	"encoding/json"
	"my_app/backend/cmd/middleware"
	"my_app/backend/internal/adapters/response"
	"net/http"
	"time"
)

type UpdateProfileInput struct {
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
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
	Source     string     `json:"source" validate:"omitempty,oneof=manual sms"`
	SourceRef  string     `json:"source_ref" validate:"max=100"`
}

// UpdateProfile is a placeholder: it echoes the input back and does not persist anything yet.
func UpdateProfile(w http.ResponseWriter, r *http.Request) {
	var input UpdateProfileInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "invalid JSON"})
		return
	}
	response.JSON(w, http.StatusOK, response.Response{
		Success: true,
		Message: "profile updated",
		Data: map[string]string{
			"user_id":    middleware.UserIDFromContext(r.Context()),
			"first_name": input.FirstName,
			"last_name":  input.LastName,
		},
	})
}
