package analytics

import (
	"testing"
	"time"
)

func TestParsePeriodDefaultMonth(t *testing.T) {
	now := time.Date(2026, 11, 5, 12, 0, 0, 0, india)
	from, to, err := ParsePeriod("", "", now)
	if err != nil {
		t.Fatal(err)
	}
	if from.Format("2006-01-02") != "2026-11-01" {
		t.Fatalf("from = %s", from)
	}
	if to.Format("2006-01-02") != "2026-12-01" {
		t.Fatalf("to = %s", to)
	}
}

func TestParsePeriodExplicit(t *testing.T) {
	from, to, err := ParsePeriod("2026-10-01", "2026-10-31", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if from.Format("2006-01-02") != "2026-10-01" || to.Format("2006-01-02") != "2026-11-01" {
		t.Fatalf("got [%s, %s)", from, to)
	}
}

func TestChangePercent(t *testing.T) {
	if got := changePercent(2845000, 2510000); got != 13.3 {
		t.Fatalf("got %v", got)
	}
	if got := changePercent(100, 0); got != 100 {
		t.Fatalf("got %v", got)
	}
}

func TestPreviousPeriod(t *testing.T) {
	from := time.Date(2026, 11, 1, 0, 0, 0, 0, india)
	to := time.Date(2026, 12, 1, 0, 0, 0, 0, india)
	pFrom, pTo := previousPeriod(from, to)
	if pFrom.Format("2006-01-02") != "2026-10-01" || pTo.Format("2006-01-02") != "2026-11-01" {
		t.Fatalf("got [%s, %s)", pFrom, pTo)
	}
}
