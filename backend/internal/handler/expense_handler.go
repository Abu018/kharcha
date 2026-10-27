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
	dateLayout       = "2006-01-02"
)

// Dates in list filters are calendar days in India, so a payment at 1 AM on
// the 1st belongs to the 1st and not to the previous day in UTC.
var indiaTime = time.FixedZone("IST", 5*60*60+30*60)

// parseDateRange turns optional YYYY-MM-DD start and end dates (both
// inclusive) into a [from, to) range. Missing dates give zero times.
func parseDateRange(start, end string) (from, to time.Time, err error) {
	if start != "" {
		if from, err = time.ParseInLocation(dateLayout, start, indiaTime); err != nil {
			return from, to, errors.New("start_date must be a date like 2026-10-01")
		}
	}
	if end != "" {
		if to, err = time.ParseInLocation(dateLayout, end, indiaTime); err != nil {
			return from, to, errors.New("end_date must be a date like 2026-10-31")
		}
		to = to.AddDate(0, 0, 1)
	}
	if !from.IsZero() && !to.IsZero() && !from.Before(to) {
		return from, to, errors.New("start_date must be on or before end_date")
	}
	return from, to, nil
}

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

// List returns the user's transactions, newest first. Optional
// ?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD limit them to those days.
func (h *ExpenseHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}
	from, to, err := parseDateRange(r.URL.Query().Get("start_date"), r.URL.Query().Get("end_date"))
	if err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: err.Error(),
		})
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

	txs, err := h.expense.List(userID, limit, from, to)
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
