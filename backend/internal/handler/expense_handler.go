package handler

import (
	"encoding/json"
	"errors"
	"log"
	"my_app/backend/cmd/middleware"
	"my_app/backend/internal/adapters/response"
	"my_app/backend/internal/dto"
	"my_app/backend/internal/expense"
	"my_app/backend/internal/models"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
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

type nearbyResolver interface {
	Resolve(viewer uuid.UUID, in []dto.Sighting) (dto.NearbyUsers, error)
}

type ExpenseHandler struct {
	expense *expense.Service
	nearby  nearbyResolver
}

func NewExpenseHandler(expense *expense.Service, nearby nearbyResolver) *ExpenseHandler {
	return &ExpenseHandler{expense: expense, nearby: nearby}
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

// Monthly returns a chart of how much the user spent in each month of
// ?year=YYYY (default: the current year in India), Jan to Dec.
func (h *ExpenseHandler) Monthly(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}

	year := time.Now().In(indiaTime).Year()
	if raw := r.URL.Query().Get("year"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 2000 || n > 2100 {
			response.JSON(w, http.StatusBadRequest, response.Response{
				Success: false,
				Message: "year must be a year like 2026",
			})
			return
		}
		year = n
	}

	chart, err := h.expense.MonthlyChart(userID, year)
	if err != nil {
		log.Printf("monthly chart: %v", err)
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "failed to load monthly spending",
		})
		return
	}

	response.JSON(w, http.StatusOK, response.Response{
		Success: true,
		Message: "ok",
		Data:    chart,
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

type UserID struct {
	UserID    []string `json:"userIDs"`
	GroupName string   `json:"name"`
}

func (h *ExpenseHandler) CreateGroup(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		response.JSON(w, http.StatusUnauthorized, response.Response{Success: false, Message: "StatusUnauthorized"})
		return
	}
	var input UserID
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "Unable to bind  the input"})
		return
	}
	input.GroupName = strings.TrimSpace(input.GroupName)
	if input.GroupName == "" || len(input.UserID) < 1 {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "At least one userID and GroupName is requred"})
		return
	}
	groupID, err := h.expense.CreateGroup(userID, input.UserID, input.GroupName)
	if err != nil {
		log.Printf("create group: %v", err)
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "Could not create the group. Check the member IDs."})
		return
	}
	response.JSON(w, http.StatusCreated, response.Response{
		Success: true,
		Message: "Group created",
		Data:    map[string]string{"id": groupID, "name": input.GroupName},
	})
}

func (h *ExpenseHandler) ListGroups(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}
	groups, err := h.expense.ListGroups(userID)
	if err != nil {
		log.Printf("list groups: %v", err)
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "failed to load groups",
		})
		return
	}
	response.JSON(w, http.StatusOK, response.Response{
		Success: true,
		Message: "groups",
		Data:    groups,
	})
}

func groupIDFrom(w http.ResponseWriter, r *http.Request) (uuid.UUID, bool) {
	groupID, err := uuid.Parse(chi.URLParam(r, "groupID"))
	if err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: "invalid group id",
		})
		return uuid.Nil, false
	}
	return groupID, true
}

func (h *ExpenseHandler) ListExpense(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}
	groupID, ok := groupIDFrom(w, r)
	if !ok {
		return
	}
	result, err := h.expense.ListExpense(userID, groupID)
	if err != nil {
		if errors.Is(err, expense.ErrNotGroupMember) {
			response.JSON(w, http.StatusNotFound, response.Response{
				Success: false,
				Message: "group not found",
			})
			return
		}
		log.Printf("list group expenses: %v", err)
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "failed to load expenses",
		})
		return
	}
	if result == nil {
		result = []expense.Expense{}
	}
	response.JSON(w, http.StatusOK, response.Response{
		Success: true,
		Message: "ok",
		Data:    result,
	})
}

type addGroupExpenseInput struct {
	Amount       int64    `json:"amount"`
	Description  string   `json:"description"`
	Name         string   `json:"name"`
	EphemeralIDs []string `json:"ephemeral_ids"`
}

func (h *ExpenseHandler) AddExpenses(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}
	groupID, ok := groupIDFrom(w, r)
	if !ok {
		return
	}
	var input addGroupExpenseInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: "invalid JSON",
		})
		return
	}
	description := strings.TrimSpace(input.Description)
	if description == "" {
		description = strings.TrimSpace(input.Name)
	}
	if input.Amount <= 0 || description == "" {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: "amount and description are required",
		})
		return
	}
	participants, err := h.participantsFromEphemeral(userID, groupID, input.EphemeralIDs)
	if err != nil {
		log.Printf("resolve nearby for group expense: %v", err)
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "failed to resolve nearby users",
		})
		return
	}
	result, err := h.expense.AddExpenses(userID, groupID, input.Amount, description, participants)
	if err != nil {
		if errors.Is(err, expense.ErrNotGroupMember) {
			response.JSON(w, http.StatusNotFound, response.Response{
				Success: false,
				Message: "group not found",
			})
			return
		}
		log.Printf("add group expense: %v", err)
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "failed to save expense",
		})
		return
	}
	response.JSON(w, http.StatusCreated, response.Response{
		Success: true,
		Message: "expense saved",
		Data:    result,
	})
}

// participantsFromEphemeral turns BLE IDs into group members who share
// groupID with the payer. Unknown or out-of-group IDs are skipped.
func (h *ExpenseHandler) participantsFromEphemeral(payer, groupID uuid.UUID, ids []string) ([]uuid.UUID, error) {
	if len(ids) == 0 || h.nearby == nil {
		return nil, nil
	}
	sightings := make([]dto.Sighting, 0, len(ids))
	for _, id := range ids {
		id = strings.ToLower(strings.TrimSpace(id))
		if id == "" {
			continue
		}
		sightings = append(sightings, dto.Sighting{EphemeralID: id, Seen: 1})
	}
	if len(sightings) == 0 {
		return nil, nil
	}
	out, err := h.nearby.Resolve(payer, sightings)
	if err != nil {
		return nil, err
	}
	participants := make([]uuid.UUID, 0, len(out.Users))
	for _, u := range out.Users {
		for _, g := range u.SharedGroups {
			if g.ID == groupID {
				participants = append(participants, u.UserID)
				break
			}
		}
	}
	return participants, nil
}

type updateCategoryInput struct {
	CategoryID uuid.UUID `json:"category_id"`
}

// UpdateCategory changes the category of one of the user's transactions:
// PUT /expenses/{id}/category with {"category_id": "<id from GET /categories>"}.
func (h *ExpenseHandler) UpdateCategory(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFrom(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: "invalid expense id",
		})
		return
	}
	var input updateCategoryInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil || input.CategoryID == uuid.Nil {
		response.JSON(w, http.StatusBadRequest, response.Response{
			Success: false,
			Message: "category_id must be an id from GET /categories",
		})
		return
	}

	tx, err := h.expense.UpdateCategory(userID, id, input.CategoryID)
	if err != nil {
		switch {
		case errors.Is(err, expense.ErrInvalidCategory):
			response.JSON(w, http.StatusBadRequest, response.Response{
				Success: false,
				Message: "category must be one of the known categories",
			})
		case errors.Is(err, expense.ErrNotFound):
			response.JSON(w, http.StatusNotFound, response.Response{
				Success: false,
				Message: "expense not found",
			})
		default:
			log.Printf("update category: %v", err)
			response.JSON(w, http.StatusInternalServerError, response.Response{
				Success: false,
				Message: "failed to update category",
			})
		}
		return
	}

	response.JSON(w, http.StatusOK, response.Response{
		Success: true,
		Message: "category updated",
		Data:    tx,
	})
}

// ListCategory returns the categories a payment can be moved to:
// GET /categories.
func (h *ExpenseHandler) ListCategory(w http.ResponseWriter, r *http.Request) {
	result, err := h.expense.ListCategory()
	if err != nil {
		response.JSON(w, http.StatusInternalServerError, response.Response{
			Success: false,
			Message: "failed to load categories",
		})
		return
	}
	response.JSON(w, http.StatusOK, response.Response{
		Success: true,
		Message: "ok",
		Data:    result,
	})
}
