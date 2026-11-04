package analytics

import (
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"
)

var india = time.FixedZone("IST", 5*60*60+30*60)

var weekdayLabels = []string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

type Service struct {
	repo Repo
}

func NewService(repo Repo) *Service {
	return &Service{repo: repo}
}

// DefaultPeriod is the current calendar month in India: [first day, first of next).
func DefaultPeriod(now time.Time) (from, to time.Time) {
	now = now.In(india)
	from = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, india)
	to = from.AddDate(0, 1, 0)
	return from, to
}

// ParsePeriod turns optional YYYY-MM-DD start/end (inclusive) into [from, to).
// Empty values use the current calendar month in India.
func ParsePeriod(start, end string, now time.Time) (from, to time.Time, err error) {
	from, to = DefaultPeriod(now)
	if start == "" && end == "" {
		return from, to, nil
	}
	const layout = "2006-01-02"
	if start != "" {
		from, err = time.ParseInLocation(layout, start, india)
		if err != nil {
			return from, to, fmt.Errorf("from must be a date like 2026-10-01")
		}
	}
	if end != "" {
		var day time.Time
		day, err = time.ParseInLocation(layout, end, india)
		if err != nil {
			return from, to, fmt.Errorf("to must be a date like 2026-10-31")
		}
		to = day.AddDate(0, 0, 1)
	} else if start != "" {
		// Single-bound start: through end of that month.
		to = from.AddDate(0, 1, 0)
	}
	if !from.Before(to) {
		return from, to, fmt.Errorf("from must be before to")
	}
	return from, to, nil
}

func (s *Service) Overview(userID uuid.UUID, from, to time.Time) (Overview, error) {
	prevFrom, prevTo := previousPeriod(from, to)

	cur, err := s.repo.PeriodTotals(userID, from, to)
	if err != nil {
		return Overview{}, err
	}
	prev, err := s.repo.PeriodTotals(userID, prevFrom, prevTo)
	if err != nil {
		return Overview{}, err
	}
	cats, err := s.repo.Categories(userID, from, to)
	if err != nil {
		return Overview{}, err
	}
	prevCats, err := s.repo.Categories(userID, prevFrom, prevTo)
	if err != nil {
		return Overview{}, err
	}
	merchants, err := s.repo.Merchants(userID, from, to, 5)
	if err != nil {
		return Overview{}, err
	}
	largest, err := s.repo.Largest(userID, from, to)
	if err != nil {
		return Overview{}, err
	}
	byDow, err := s.repo.ByWeekday(userID, from, to)
	if err != nil {
		return Overview{}, err
	}
	byHour, err := s.repo.ByHour(userID, from, to)
	if err != nil {
		return Overview{}, err
	}
	split, err := s.repo.SplitShare(userID, from, to)
	if err != nil {
		return Overview{}, err
	}
	balances, err := s.repo.Balances(userID)
	if err != nil {
		return Overview{}, err
	}

	days := periodDays(from, to)
	weekdayDays, weekendDays := countWeekParts(from, to)

	var weekdayTotal, weekendTotal int64
	byWeekday := make([]NamedAmount, 7)
	for i := 0; i < 7; i++ {
		byWeekday[i] = NamedAmount{Label: weekdayLabels[i]}
	}
	for _, row := range byDow {
		if row.Dow < 0 || row.Dow > 6 {
			continue
		}
		byWeekday[row.Dow].Amount = row.Amount
		if row.Dow == 0 || row.Dow == 6 {
			weekendTotal += row.Amount
		} else {
			weekdayTotal += row.Amount
		}
	}

	hours := make([]HourAmount, 24)
	for h := 0; h < 24; h++ {
		hours[h] = HourAmount{Hour: h}
	}
	for _, row := range byHour {
		if row.Hour >= 0 && row.Hour < 24 {
			hours[row.Hour].Amount = row.Amount
		}
	}

	prevByName := map[string]int64{}
	for _, c := range prevCats {
		prevByName[c.Name] = c.Amount
	}
	categories := make([]CategorySpend, 0, len(cats))
	for _, c := range cats {
		var pct, change float64
		if cur.TotalSpent > 0 {
			pct = round1(100 * float64(c.Amount) / float64(cur.TotalSpent))
		}
		if prevAmt := prevByName[c.Name]; prevAmt > 0 {
			change = round1(100 * (float64(c.Amount)-float64(prevAmt)) / float64(prevAmt))
		} else if c.Amount > 0 {
			change = 100
		}
		categories = append(categories, CategorySpend{
			Name:          c.Name,
			Amount:        c.Amount,
			Percent:       pct,
			Count:         c.Count,
			ChangePercent: change,
		})
	}

	merchantOut := make([]MerchantSpend, 0, len(merchants))
	for _, m := range merchants {
		merchantOut = append(merchantOut, MerchantSpend{
			Merchant:  m.Merchant,
			Category:  m.Category,
			Amount:    m.Amount,
			Count:     m.Count,
			LastVisit: m.LastVisit,
		})
	}

	var avgTx, dailyAvg int64
	if cur.Count > 0 {
		avgTx = cur.TotalSpent / int64(cur.Count)
	}
	if days > 0 {
		dailyAvg = cur.TotalSpent / int64(days)
	}

	var weekdayAvg, weekendAvg int64
	if weekdayDays > 0 {
		weekdayAvg = weekdayTotal / int64(weekdayDays)
	}
	if weekendDays > 0 {
		weekendAvg = weekendTotal / int64(weekendDays)
	}
	var weekendRatio float64
	if weekdayAvg > 0 {
		weekendRatio = round1(float64(weekendAvg) / float64(weekdayAvg))
	}

	out := Overview{
		From:     from.In(india).Format("2006-01-02"),
		To:       to.In(india).AddDate(0, 0, -1).Format("2006-01-02"),
		Currency: "INR",
		Summary: Summary{
			TotalSpent:         cur.TotalSpent,
			TransactionCount:   cur.Count,
			AverageTransaction: avgTx,
			DailyAverage:       dailyAvg,
			Largest:            largest,
			PreviousPeriod: PreviousPeriod{
				TotalSpent:    prev.TotalSpent,
				ChangePercent: changePercent(cur.TotalSpent, prev.TotalSpent),
			},
		},
		Categories: categories,
		Merchants:  merchantOut,
		WeekdayWeekend: WeekdayWeekend{
			WeekdayTotal:    weekdayTotal,
			WeekendTotal:    weekendTotal,
			WeekdayDailyAvg: weekdayAvg,
			WeekendDailyAvg: weekendAvg,
			WeekendRatio:    weekendRatio,
		},
		ByWeekday: byWeekday,
		ByHour:    hours,
		PersonalVsSplit: PersonalVsSplit{
			PersonalPaise: cur.TotalSpent,
			SplitPaise:    split,
		},
		Balances: balances,
		Insights: buildInsights(cur, prev, categories, merchantOut, largest, weekendRatio, balances),
	}
	return out, nil
}

func previousPeriod(from, to time.Time) (time.Time, time.Time) {
	// Calendar months: Nov 1 → Dec 1 compares to Oct 1 → Nov 1 (not a
	// fixed-length shift, which lands on Oct 2 because months differ).
	if from.Day() == 1 && to.Day() == 1 &&
		from.Hour() == 0 && to.Hour() == 0 &&
		(to.Year() != from.Year() || to.Month() != from.Month()) {
		prev := from.AddDate(0, -1, 0)
		return prev, from
	}
	return from.Add(-to.Sub(from)), from
}

func periodDays(from, to time.Time) int {
	d := int(to.Sub(from).Hours() / 24)
	if d < 1 {
		return 1
	}
	// Cap at "today" for the current month so MTD daily avg is fair.
	now := time.Now().In(india)
	if to.After(now) && from.Before(now) {
		d = int(now.Sub(from).Hours()/24) + 1
	}
	if d < 1 {
		return 1
	}
	return d
}

func countWeekParts(from, to time.Time) (weekdays, weekends int) {
	for d := from; d.Before(to); d = d.AddDate(0, 0, 1) {
		if time.Now().In(india).Before(d) {
			break
		}
		switch d.Weekday() {
		case time.Saturday, time.Sunday:
			weekends++
		default:
			weekdays++
		}
	}
	if weekdays == 0 {
		weekdays = 1
	}
	if weekends == 0 {
		weekends = 1
	}
	return weekdays, weekends
}

func changePercent(cur, prev int64) float64 {
	if prev == 0 {
		if cur == 0 {
			return 0
		}
		return 100
	}
	return round1(100 * (float64(cur) - float64(prev)) / float64(prev))
}

func round1(v float64) float64 {
	return math.Round(v*10) / 10
}

func formatRupees(paise int64) string {
	rupees := float64(paise) / 100
	if rupees >= 100000 {
		return fmt.Sprintf("₹%.1fL", rupees/100000)
	}
	if rupees == math.Trunc(rupees) {
		return fmt.Sprintf("₹%s", indianInt(int64(rupees)))
	}
	return fmt.Sprintf("₹%s", indianInt(int64(rupees)))
}

func indianInt(n int64) string {
	if n < 0 {
		return "-" + indianInt(-n)
	}
	s := fmt.Sprintf("%d", n)
	if len(s) <= 3 {
		return s
	}
	last3 := s[len(s)-3:]
	rest := s[:len(s)-3]
	var parts []string
	for len(rest) > 2 {
		parts = append([]string{rest[len(rest)-2:]}, parts...)
		rest = rest[:len(rest)-2]
	}
	if rest != "" {
		parts = append([]string{rest}, parts...)
	}
	return strings.Join(parts, ",") + "," + last3
}

func buildInsights(
	cur, prev PeriodTotals,
	cats []CategorySpend,
	merchants []MerchantSpend,
	largest *LargestExpense,
	weekendRatio float64,
	balances Balances,
) []Insight {
	out := make([]Insight, 0, 8)

	if prev.TotalSpent > 0 {
		chg := changePercent(cur.TotalSpent, prev.TotalSpent)
		if chg >= 10 {
			out = append(out, Insight{
				Type:          "period_spike",
				Message:       fmt.Sprintf("Spending is up %.0f%% vs the previous period.", chg),
				ChangePercent: chg,
			})
		} else if chg <= -10 {
			out = append(out, Insight{
				Type:          "period_drop",
				Message:       fmt.Sprintf("Spending is down %.0f%% vs the previous period.", -chg),
				ChangePercent: chg,
			})
		}
	}

	for _, c := range cats {
		if c.ChangePercent >= 20 && c.Amount >= 50000 {
			out = append(out, Insight{
				Type:          "category_spike",
				Category:      c.Name,
				Message:       fmt.Sprintf("%s spending is up %.0f%% compared to last period.", c.Name, c.ChangePercent),
				ChangePercent: c.ChangePercent,
			})
			break
		}
	}
	for _, c := range cats {
		if c.ChangePercent <= -20 {
			out = append(out, Insight{
				Type:          "category_drop",
				Category:      c.Name,
				Message:       fmt.Sprintf("%s spending is down %.0f%% compared to last period.", c.Name, -c.ChangePercent),
				ChangePercent: c.ChangePercent,
			})
			break
		}
	}

	for _, m := range merchants {
		if m.Count >= 4 {
			out = append(out, Insight{
				Type:     "frequent_merchant",
				Merchant: m.Merchant,
				Message: fmt.Sprintf(
					"You visited %s %d times this period, spending %s in total.",
					m.Merchant, m.Count, formatRupees(m.Amount),
				),
			})
			break
		}
	}

	if largest != nil && cur.Count >= 3 {
		name := strings.TrimSpace(largest.Vendor)
		if name == "" {
			name = "a purchase"
		}
		out = append(out, Insight{
			Type:     "large_transaction",
			Merchant: name,
			Message: fmt.Sprintf(
				"%s at %s is your largest expense this period.",
				formatRupees(largest.AmountPaise), name,
			),
		})
	}

	if weekendRatio >= 1.5 {
		out = append(out, Insight{
			Type:    "weekend_spending",
			Message: fmt.Sprintf("Weekend daily spend is %.1f× your weekday average.", weekendRatio),
		})
	}

	if len(cats) > 0 && cats[0].Percent >= 30 {
		out = append(out, Insight{
			Type:     "top_category",
			Category: cats[0].Name,
			Message: fmt.Sprintf(
				"%s is %.0f%% of your spending this period.",
				cats[0].Name, cats[0].Percent,
			),
		})
	}

	if balances.YouAreOwedPaise > 0 {
		out = append(out, Insight{
			Type:    "you_are_owed",
			Message: fmt.Sprintf("Friends owe you %s from group expenses.", formatRupees(balances.YouAreOwedPaise)),
		})
	} else if balances.YouOwePaise > 0 {
		out = append(out, Insight{
			Type:    "you_owe",
			Message: fmt.Sprintf("You owe %s on group expenses.", formatRupees(balances.YouOwePaise)),
		})
	}

	if len(out) > 6 {
		out = out[:6]
	}
	return out
}
