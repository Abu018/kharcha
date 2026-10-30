package expense

import (
	"errors"
	"my_app/backend/internal/models"
	"time"

	"github.com/google/uuid"
)

// ErrDuplicate is returned by Create when the user already has a transaction
// with the same SourceRef.
var ErrDuplicate = errors.New("transaction already recorded")

// ErrNotGroupMember is returned when the user is not the group's owner
// and is not in its member list.
var ErrNotGroupMember = errors.New("not a group member")

type Repo interface {
	Create(tx *models.Transaction) error
	// List returns transactions newest first, with occurred_at in
	// [from, to). A zero from or to leaves that side unbounded.
	List(userID uuid.UUID, limit int, from, to time.Time) ([]models.Transaction, error)
	// HasMatch reports whether the user has an auto-detected transaction
	// with this amount and type, occurred_at in [from, to], that came from a
	// source other than source. Manual entries never match.
	HasMatch(userID uuid.UUID, amountPaise int64, txType, source string, from, to time.Time) (bool, error)
	// Uncategorized returns transactions still waiting for a category.
	Uncategorized(limit int) ([]models.Transaction, error)
	SetCategory(id uuid.UUID, category string) error
	// MonthlySpent returns the user's debits per month of year, Jan to Dec,
	// with Y 0 for months without payments.
	MonthlySpent(userID uuid.UUID, year int) ([]Series, error)
	HighestSpendingAmount(userID uuid.UUID, year int) (int64, error)
	CreateGroup(userID uuid.UUID, GroupMembers []string, GroupName string) (string, error)
	ListExpense(userID, groupID uuid.UUID) ([]models.Expense, error)
	AddExpenses(userID, groupID uuid.UUID, amount int64, description string) (models.Expense, error)
}
