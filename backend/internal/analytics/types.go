package analytics

import (
	"time"

	"github.com/google/uuid"
)

// Overview is everything the Insights screen needs in one response.
type Overview struct {
	From             string           `json:"from"`
	To               string           `json:"to"`
	Currency         string           `json:"currency"`
	Summary          Summary          `json:"summary"`
	Categories       []CategorySpend  `json:"categories"`
	Merchants        []MerchantSpend  `json:"merchants"`
	WeekdayWeekend   WeekdayWeekend   `json:"weekday_weekend"`
	ByWeekday        []NamedAmount    `json:"by_weekday"`
	ByHour           []HourAmount     `json:"by_hour"`
	PersonalVsSplit  PersonalVsSplit  `json:"personal_vs_split"`
	Balances         Balances         `json:"balances"`
	Insights         []Insight        `json:"insights"`
}

type Summary struct {
	TotalSpent         int64           `json:"total_spent"`
	TransactionCount   int             `json:"transaction_count"`
	AverageTransaction int64           `json:"average_transaction"`
	DailyAverage       int64           `json:"daily_average"`
	Largest            *LargestExpense `json:"largest_expense,omitempty"`
	PreviousPeriod     PreviousPeriod  `json:"previous_period"`
}

type PreviousPeriod struct {
	TotalSpent    int64   `json:"total_spent"`
	ChangePercent float64 `json:"change_percent"`
}

type LargestExpense struct {
	ID         uuid.UUID `json:"id"`
	Vendor     string    `json:"vendor"`
	Category   string    `json:"category"`
	AmountPaise int64    `json:"amount_paise"`
	OccurredAt time.Time `json:"occurred_at"`
}

type CategorySpend struct {
	Name          string  `json:"name"`
	Amount        int64   `json:"amount"`
	Percent       float64 `json:"percent"`
	Count         int     `json:"count"`
	ChangePercent float64 `json:"change_percent"`
}

type MerchantSpend struct {
	Merchant  string    `json:"merchant"`
	Category  string    `json:"category"`
	Amount    int64     `json:"amount"`
	Count     int       `json:"count"`
	LastVisit time.Time `json:"last_visit"`
}

type WeekdayWeekend struct {
	WeekdayTotal     int64   `json:"weekday_total"`
	WeekendTotal     int64   `json:"weekend_total"`
	WeekdayDailyAvg  int64   `json:"weekday_daily_avg"`
	WeekendDailyAvg  int64   `json:"weekend_daily_avg"`
	WeekendRatio     float64 `json:"weekend_ratio"`
}

type NamedAmount struct {
	Label  string `json:"label"`
	Amount int64  `json:"amount"`
}

type HourAmount struct {
	Hour   int   `json:"hour"`
	Amount int64 `json:"amount"`
}

type PersonalVsSplit struct {
	PersonalPaise int64 `json:"personal_paise"`
	SplitPaise    int64 `json:"split_paise"`
}

type Balances struct {
	YouOwePaise     int64 `json:"you_owe_paise"`
	YouAreOwedPaise int64 `json:"you_are_owed_paise"`
}

type Insight struct {
	Type          string  `json:"type"`
	Message       string  `json:"message"`
	Category      string  `json:"category,omitempty"`
	Merchant      string  `json:"merchant,omitempty"`
	ChangePercent float64 `json:"change_percent,omitempty"`
}

// PeriodTotals is a raw aggregate used by the repository.
type PeriodTotals struct {
	TotalSpent int64
	Count      int
}

type CategoryRow struct {
	Name   string
	Amount int64
	Count  int
}

type MerchantRow struct {
	Merchant  string
	Category  string
	Amount    int64
	Count     int
	LastVisit time.Time
}

type DayAmountRow struct {
	Dow    int // 0=Sunday … 6=Saturday (Postgres EXTRACT DOW)
	Amount int64
}

type HourAmountRow struct {
	Hour   int
	Amount int64
}
