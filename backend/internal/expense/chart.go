package expense

import (
	"fmt"

	"github.com/google/uuid"
)

// Chart is a single-series chart for the dashboard.
type Chart struct {
	Title     string   `json:"title"`
	XAxis     Axis     `json:"xAxis"`
	YAxis     Axis     `json:"yAxis"`
	MaxAmount int64    `json:"max_amount"`
	Series    []Series `json:"series"`
}

type Axis struct {
	Label string `json:"label"`
}

// Series is one point: X is the label (e.g. "Jan"), Y the amount in paise.
type Series struct {
	X string `json:"x"`
	Y int64  `json:"y"`
}

// MonthlyChart returns how much the user spent in each month of year, Jan
// to Dec, with 0 for months without payments.
func (s *Service) MonthlyChart(userID uuid.UUID, year int) (Chart, error) {
	points, err := s.repo.MonthlySpent(userID, year)
	if err != nil {
		return Chart{}, err
	}
	if points == nil {
		points = []Series{}
	}
	amount, err := s.repo.HighestSpendingAmount(userID, year)
	if err != nil {
		return Chart{}, err
	}
	return Chart{
		Title:     fmt.Sprintf("Spent in %d", year),
		XAxis:     Axis{Label: "Month"},
		YAxis:     Axis{Label: "Spent (₹)"},
		Series:    points,
		MaxAmount: amount,
	}, nil
}
