package analytics

import (
	"time"

	"github.com/google/uuid"
)

// Repo loads spending aggregates for one user over [from, to).
type Repo interface {
	PeriodTotals(userID uuid.UUID, from, to time.Time) (PeriodTotals, error)
	Categories(userID uuid.UUID, from, to time.Time) ([]CategoryRow, error)
	Merchants(userID uuid.UUID, from, to time.Time, limit int) ([]MerchantRow, error)
	Largest(userID uuid.UUID, from, to time.Time) (*LargestExpense, error)
	ByWeekday(userID uuid.UUID, from, to time.Time) ([]DayAmountRow, error)
	ByHour(userID uuid.UUID, from, to time.Time) ([]HourAmountRow, error)
	SplitShare(userID uuid.UUID, from, to time.Time) (int64, error)
	Balances(userID uuid.UUID) (Balances, error)
}
