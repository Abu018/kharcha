package expense

import (
	"context"
	"encoding/json"
	"fmt"
	"my_app/backend/internal/models"
	"my_app/backend/internal/utils"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestNormalizeCategory(t *testing.T) {
	cases := map[string]string{
		"Food":                "Food",
		" food.\n":            "Food",
		"Category: Transport": "Transport",
		"BILLS":               "Bills",
		"groceries":           "Groceries",
		"travel":              "Other",
		"":                    "Other",
	}
	for in, want := range cases {
		if got := normalizeCategory(in); got != want {
			t.Errorf("normalizeCategory(%q) = %q, want %q", in, got, want)
		}
	}
}

type fakeRepo struct {
	created []models.Transaction
	pending []models.Transaction
	set     map[uuid.UUID]string
	monthly []Series
}

func (f *fakeRepo) Create(tx *models.Transaction) error {
	f.created = append(f.created, *tx)
	return nil
}

func (f *fakeRepo) List(uuid.UUID, int, time.Time, time.Time) ([]models.Transaction, error) {
	return nil, nil
}

// HasMatch looks through created the way the SQL query does.
func (f *fakeRepo) HasMatch(userID uuid.UUID, amount int64, txType, source string, from, to time.Time) (bool, error) {
	for _, tx := range f.created {
		if tx.UserID == userID && tx.AmountPaise == amount && tx.Type == txType &&
			tx.Source != source && tx.Source != "manual" &&
			!tx.OccurredAt.Before(from) && !tx.OccurredAt.After(to) {
			return true, nil
		}
	}
	return false, nil
}

func (f *fakeRepo) Uncategorized(int) ([]models.Transaction, error) { return f.pending, nil }

func (f *fakeRepo) MonthlySpent(uuid.UUID, int) ([]Series, error) { return f.monthly, nil }

func (f *fakeRepo) CreateGroup(uuid.UUID, []string, string) (string, error) { return "", nil }

func (f *fakeRepo) HighestSpendingAmount(uuid.UUID, int) (int64, error) {
	var highest int64
	for _, p := range f.monthly {
		highest = max(highest, p.Y)
	}
	return highest, nil
}

func (f *fakeRepo) SetCategory(id uuid.UUID, category string) error {
	if f.set == nil {
		f.set = map[uuid.UUID]string{}
	}
	f.set[id] = category
	return nil
}

// fakeModel says only "Sakkeer V" is a person, answers Food for a payee
// mentioning Tiffin and Other otherwise, and records the model it was asked for.
func fakeModel(t *testing.T, gotModel *string) *httptest.Server {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Model    string `json:"model"`
			Messages []struct {
				Content string `json:"content"`
			} `json:"messages"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatal(err)
		}
		*gotModel = req.Model
		answer := "Other"
		content := req.Messages[0].Content
		switch {
		case strings.Contains(content, "individual person"):
			answer = "No."
			if strings.Contains(content, `"Sakkeer V"`) {
				answer = "Yes."
			}
		case strings.Contains(content[strings.LastIndex(content, "Payee:"):], "Tiffin"):
			answer = " Food.\n"
		}
		json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{{"message": map[string]string{"content": answer}}},
		})
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestCreateStoresModelCategory(t *testing.T) {
	var model string
	srv := fakeModel(t, &model)
	repo := &fakeRepo{}
	s := NewService(repo, utils.ClassifierConfig{URL: srv.URL, Model: "gemma-test"})

	tx := &models.Transaction{AmountPaise: 45050, Currency: "INR", Type: "debit", Vendor: "Ganesh Tiffin Centre", BankName: "HDFC"}
	if err := s.Create(context.Background(), tx); err != nil {
		t.Fatal(err)
	}
	if got := repo.created[0].Category; got != "Food" {
		t.Errorf("category = %q, want Food", got)
	}
	if model != "gemma-test" {
		t.Errorf("model = %q, want gemma-test", model)
	}
}

func TestCreateFallsBackToUnknownWhenModelDown(t *testing.T) {
	repo := &fakeRepo{}
	s := NewService(repo, utils.ClassifierConfig{URL: "http://127.0.0.1:1/v1/chat/completions", Model: "x"})

	if err := s.Create(context.Background(), &models.Transaction{Type: "debit", Vendor: "Ganesh Tiffin Centre"}); err != nil {
		t.Fatal(err)
	}
	if got := repo.created[0].Category; got != UnknownCategory {
		t.Errorf("category = %q, want %q", got, UnknownCategory)
	}
}

func TestCreateSkipsPaymentSeenFromAnotherSource(t *testing.T) {
	repo := &fakeRepo{}
	s := NewService(repo, utils.ClassifierConfig{URL: "http://127.0.0.1:1/v1/chat/completions", Model: "x"})
	user := uuid.New()
	at := time.Date(2026, 10, 27, 14, 0, 0, 0, time.UTC)
	tx := func(source string, offset time.Duration, amount int64) *models.Transaction {
		return &models.Transaction{UserID: user, AmountPaise: amount, Type: "debit", Vendor: "Swiggy", Source: source, OccurredAt: at.Add(offset)}
	}

	if err := s.Create(context.Background(), tx("sms", 0, 25000)); err != nil {
		t.Fatal(err)
	}
	if err := s.Create(context.Background(), tx("notification", time.Minute, 25000)); err != ErrDuplicate {
		t.Errorf("same payment from notification: err = %v, want ErrDuplicate", err)
	}
	if err := s.Create(context.Background(), tx("notification", time.Minute, 9900)); err != nil {
		t.Errorf("different amount: %v", err)
	}
	if err := s.Create(context.Background(), tx("notification", 10*time.Minute, 25000)); err != nil {
		t.Errorf("ten minutes later: %v", err)
	}
	if err := s.Create(context.Background(), tx("manual", 0, 25000)); err != nil {
		t.Errorf("manual entry: %v", err)
	}
	if len(repo.created) != 4 {
		t.Errorf("saved %d transactions, want 4", len(repo.created))
	}
}

func TestMonthlyChart(t *testing.T) {
	repo := &fakeRepo{monthly: []Series{{X: "Jan", Y: 1000}, {X: "Feb", Y: 20000}}}
	s := NewService(repo, utils.ClassifierConfig{})

	chart, err := s.MonthlyChart(uuid.New(), 2026)
	if err != nil {
		t.Fatal(err)
	}
	if chart.Title != "Spent in 2026" || chart.XAxis.Label != "Month" || len(chart.Series) != 2 {
		t.Errorf("chart = %+v", chart)
	}
	if chart.MaxAmount != 20000 {
		t.Errorf("MaxAmount = %d, want 20000", chart.MaxAmount)
	}

	repo.monthly = nil
	if chart, _ := s.MonthlyChart(uuid.New(), 2026); chart.Series == nil {
		t.Error("Series is nil; it should be an empty list so the JSON has []")
	}
}

func TestBackfillClassifiesUnknown(t *testing.T) {
	var model string
	srv := fakeModel(t, &model)
	swiggy, friend, tiffin, shop := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	repo := &fakeRepo{pending: []models.Transaction{
		{BaseModel: models.BaseModel{ID: swiggy}, Type: "debit", Vendor: "Swiggy", Category: UnknownCategory},
		{BaseModel: models.BaseModel{ID: friend}, Type: "debit", Vendor: "Sakkeer V", Category: UnknownCategory},
		{BaseModel: models.BaseModel{ID: tiffin}, Type: "debit", Vendor: "Ganesh Tiffin Centre", Category: UnknownCategory},
		{BaseModel: models.BaseModel{ID: shop}, Type: "debit", Vendor: "Coco Bilekahalli", Category: UnknownCategory},
	}}
	s := NewService(repo, utils.ClassifierConfig{URL: srv.URL, Model: "m"})

	n, err := s.Backfill(context.Background())
	if err != nil || n != 4 {
		t.Fatalf("Backfill = %d, %v; want 4, nil", n, err)
	}
	want := map[uuid.UUID]string{swiggy: "Food", friend: "Transfers", tiffin: "Food", shop: "Other"}
	if fmt.Sprint(repo.set) != fmt.Sprint(want) {
		t.Errorf("categories = %v", repo.set)
	}
}

func TestRuleCategory(t *testing.T) {
	cases := []struct {
		tx   models.Transaction
		want string
	}{
		{models.Transaction{Type: "credit", Vendor: "Sakthivel"}, "Income"},
		{models.Transaction{Type: "debit", Vendor: "Dakshin Cafe2"}, "Food"},
		{models.Transaction{Type: "debit", Vendor: "Ayush Hyper Market 5"}, "Groceries"},
		{models.Transaction{Type: "debit", Vendor: "Jiohotstar 14/10/26"}, "Entertainment"},
		{models.Transaction{Type: "debit", Vendor: "6d10b33212eb49b9a49a767c6f28fe10"}, "Other"},
		{models.Transaction{Type: "debit", Vendor: ""}, "Other"},
		{models.Transaction{Type: "debit", Vendor: "Nidhi Kumari"}, ""},
	}
	for _, c := range cases {
		got, _ := ruleCategory(&c.tx)
		if got != c.want {
			t.Errorf("ruleCategory(%q, %s) = %q, want %q", c.tx.Vendor, c.tx.Type, got, c.want)
		}
	}
}

func TestPayeeName(t *testing.T) {
	cases := map[string]string{
		"Spotify 20/10/26":                 "Spotify",
		"Dakshin Cafe2":                    "Dakshin Cafe",
		"Senthilsenthil98832-1":            "Senthilsenthil",
		"7675040391-2":                     "",
		"6d10b33212eb49b9a49a767c6f28fe10": "",
		"Rs":                               "",
		"Sakkeer V":                        "Sakkeer V",
	}
	for in, want := range cases {
		if got := payeeName(in); got != want {
			t.Errorf("payeeName(%q) = %q, want %q", in, got, want)
		}
	}
}
