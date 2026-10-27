package handler

import (
	"testing"
	"time"
)

func TestParseDateRange(t *testing.T) {
	from, to, err := parseDateRange("2026-10-01", "2026-10-31")
	if err != nil {
		t.Fatal(err)
	}
	if want := time.Date(2026, 10, 1, 0, 0, 0, 0, indiaTime); !from.Equal(want) {
		t.Errorf("from = %v, want %v", from, want)
	}
	if want := time.Date(2026, 11, 1, 0, 0, 0, 0, indiaTime); !to.Equal(want) {
		t.Errorf("to = %v, want %v (end_date is inclusive)", to, want)
	}

	from, to, err = parseDateRange("", "")
	if err != nil || !from.IsZero() || !to.IsZero() {
		t.Errorf("empty dates = %v, %v, %v; want zero times and no error", from, to, err)
	}

	if _, _, err := parseDateRange("2026-10-01", "2026-10-01"); err != nil {
		t.Errorf("a single day should be allowed: %v", err)
	}

	for _, bad := range [][2]string{
		{"01-10-2026", ""},
		{"", "2026-13-01"},
		{"2026-10-31", "2026-10-01"},
	} {
		if _, _, err := parseDateRange(bad[0], bad[1]); err == nil {
			t.Errorf("parseDateRange(%q, %q) should fail", bad[0], bad[1])
		}
	}
}
