package handler

import (
	"encoding/json"
	"errors"
	"log"
	"my_app/backend/cmd/middleware"
	"my_app/backend/internal/adapters/response"
	"my_app/backend/internal/expense"
	"my_app/backend/internal/models"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

const (
	defaultListLimit = 100
	maxListLimit     = 500
)

type ExpenseHandler struct {
	expense *expense.Service
}

func NewExpenseHandler(expense *expense.Service) *ExpenseHandler {
	return &ExpenseHandler{expense: expense}
}

func userIDFrom(w http.ResponseWriter, r *http.Request) (uuid.UUID, bool) {
	userID, err := uuid.Parse(middleware.UserIDFromContext(r.Context()))
	if err != nil {
		response.JSON(w, http.StatusUnauthorized, response.Response{
			Success: false,
			Message: "invalid user",
		})
		return uuid.Nil, false
	}
	return userID, true
}

func (h *ExpenseHandler) Expense(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}

	var input TransactionInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: "invalid JSON",
		})
		return
	}

	if err := validate.Struct(input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	tx := models.Transaction{
		AmountPaise: input.AmountPaise,
		Currency:    input.Currency,
		BankName:    input.BankName,
		AccountType: input.AccountType,
		Type:        input.Type,
		Vendor:      input.Vendor,
		VendorUPI:   input.VendorUPI,
		OccurredAt:  time.Now().UTC(),
		Source:      "manual",
		UserID:      userID,
	}
	if input.OccurredAt != nil && !input.OccurredAt.IsZero() {
		tx.OccurredAt = input.OccurredAt.UTC()
	}
	if input.Source != "" {
		tx.Source = input.Source
	}
	if ref := strings.TrimSpace(input.SourceRef); ref != "" {
		tx.SourceRef = &ref
	}

	if err := h.expense.Create(r.Context(), &tx); err != nil {
		if errors.Is(err, expense.ErrDuplicate) {
			response.JSON(w, http.StatusOK, response.Response{
				Success: true,
				Message: "transaction already recorded",
			})
			return
		}
		log.Printf("save transaction: %v", err)
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "failed to save transaction",
		})
		return
	}

	response.JSON(w, http.StatusCreated, response.Response{
		Success: true,
		Message: "transaction saved successfully",
		Data:    tx,
	})
}

// List returns the user's transactions, newest first.
func (h *ExpenseHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}

	limit := defaultListLimit
	if raw := r.URL.Query().Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			response.JSON(w, http.StatusBadRequest, response.Response{
				Success: false,
				Message: "limit must be a positive number",
			})
			return
		}
		limit = min(n, maxListLimit)
	}

	txs, err := h.expense.List(userID, limit)
	if err != nil {
		log.Printf("list transactions: %v", err)
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "failed to load transactions",
		})
		return
	}
	if txs == nil {
		txs = []models.Transaction{}
	}

	response.JSON(w, http.StatusOK, response.Response{
		Success: true,
		Message: "ok",
		Data:    txs,
	})
}
