package expense

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"my_app/backend/internal/models"
	"my_app/backend/internal/utils"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
)

// UnknownCategory marks a transaction the model has not classified yet,
// usually because the model server was unreachable when it was saved.
const UnknownCategory = unknownCategory

const backfillBatch = 50

// sameEventWindow is how far apart the SMS and the app notification for one
// payment can be timestamped.
const sameEventWindow = 3 * time.Minute

// modelCategories are the answers the model may give: every category except
// Income, which every credit gets by rule, and Unknown.
var modelCategories = func() []string {
	var out []string
	for _, c := range Categories {
		if c != incomeCategory && c != unknownCategory {
			out = append(out, c)
		}
	}
	return out
}()

var (
	trailingDate   = regexp.MustCompile(`\s+\d{1,2}/\d{1,2}/\d{2,4}$`)
	trailingNumber = regexp.MustCompile(`([\s-]*\d+)+$`)
	opaqueID       = regexp.MustCompile(`^[0-9a-f]{16,}$|^\d+$`)
)

// payeeName strips noise the SMS parser leaves on vendor names, such as
// "Spotify 20/10/26" or "Dakshin Cafe2", and drops IDs that are not names.
func payeeName(vendor string) string {
	v := strings.TrimSpace(vendor)
	v = trailingDate.ReplaceAllString(v, "")
	if opaqueID.MatchString(strings.ToLower(v)) {
		return ""
	}
	v = trailingNumber.ReplaceAllString(v, "")
	if strings.EqualFold(v, "rs") || strings.EqualFold(v, "inr") {
		return ""
	}
	return strings.TrimSpace(v)
}

// ruleCategory returns a category when one can be decided without the model.
func ruleCategory(tx *models.Transaction) (string, bool) {
	if tx.Type == "credit" {
		return incomeCategory, true
	}
	name := payeeName(tx.Vendor)
	if c := keywordCategory(&models.Transaction{Vendor: name, VendorUPI: tx.VendorUPI}); c != "" {
		return c, true
	}
	if name == "" {
		return "Other", true
	}
	return "", false
}

func (s *Service) categorize(ctx context.Context, tx *models.Transaction) (string, error) {
	if c, ok := ruleCategory(tx); ok {
		return c, nil
	}
	name := payeeName(tx.Vendor)
	person, err := s.isPerson(ctx, name)
	if err != nil {
		return "", err
	}
	if person {
		return "Transfers", nil
	}
	return s.Classify(ctx, name)
}

type Service struct {
	repo   Repo
	cfg    utils.ClassifierConfig
	client *http.Client
}

func NewService(repo Repo, cfg utils.ClassifierConfig) *Service {
	return &Service{
		repo:   repo,
		cfg:    cfg,
		client: &http.Client{Timeout: 10 * time.Second},
	}
}

// Classify asks the model which category a payment to payee belongs in.
func (s *Service) Classify(ctx context.Context, payee string) (string, error) {
	prompt := `You categorise UPI payments made in India. Given who was paid, answer with exactly one of:
` + strings.Join(modelCategories, ", ") + `.

Transfers: the payee is a person's name.
Food: restaurants, cafes, bakeries, juice shops.
Groceries: supermarkets, kirana and provision stores.
Transport: cabs, fuel, vehicle repair.
Health: pharmacies, hospitals, clinics, labs.
Shopping: clothes, electronics, online stores.
Bills: phone, electricity, internet, rent, software and IT services.
Entertainment: streaming, movies, games, sports.
Other: anything else.

Examples:
Payee: Annapoorna Tiffin Centre -> Food
Payee: Sri Lakshmi Stores -> Groceries
Payee: Infosys Technologies Pvt -> Bills

Reply with the category name only.

Payee: ` + payee

	answer, err := s.ask(ctx, prompt)
	if err != nil {
		return "", err
	}
	return normalizeCategory(answer), nil
}

// businessWord marks names the person check misjudges, e.g. "Sri Lakshmi
// Stores" or "Annapoorna Tiffin Centre".
var businessWord = regexp.MustCompile(`(?i)\b(pvt|private|ltd|limited|llp|technologies|tech|solutions|services|enterprises?|traders?|stores?|shop|centre|center|agency|agencies|company|co|industries|associates|works|hub|world|point|corner|house|bhavan|mandir|sow)\b`)

// isPerson asks the model whether payee is an individual. The small model
// is much more reliable at this yes/no question than at picking Transfers
// out of the full category list.
func (s *Service) isPerson(ctx context.Context, payee string) (bool, error) {
	if businessWord.MatchString(payee) {
		return false, nil
	}
	answer, err := s.ask(ctx, `Is "`+payee+`" the name of an individual person (not a shop, company or brand)? Answer yes or no.`)
	if err != nil {
		return false, err
	}
	return strings.HasPrefix(strings.ToLower(strings.TrimSpace(answer)), "yes"), nil
}

// ask sends a single-turn prompt to the model and returns its reply.
func (s *Service) ask(ctx context.Context, prompt string) (string, error) {
	body, err := json.Marshal(map[string]any{
		"model": s.cfg.Model,
		"messages": []map[string]string{
			{"role": "user", "content": prompt},
		},
		"temperature": 0,
		"max_tokens":  20,
	})
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.cfg.URL, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("model server returned status %d", resp.StatusCode)
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}
	if len(result.Choices) == 0 {
		return "", errors.New("model returned no choices")
	}
	return result.Choices[0].Message.Content, nil
}

// normalizeCategory maps free-form model output such as "food." or
// "Category: Food" onto one of the known categories. An answer that matches
// none is Other, so Unknown is kept for "not classified yet".
func normalizeCategory(answer string) string {
	answer = strings.ToLower(answer)
	for _, c := range modelCategories {
		if strings.Contains(answer, strings.ToLower(c)) {
			return c
		}
	}
	return "Other"
}

// Create saves the transaction. If the classifier is unreachable the
// transaction is still saved as Unknown and classified later by Backfill.
// An auto-detected payment already recorded from another source (the bank
// SMS and the UPI app notification for the same payment) returns
// ErrDuplicate.
func (s *Service) Create(ctx context.Context, tx *models.Transaction) error {
	if tx.Source != "" && tx.Source != "manual" {
		dup, err := s.repo.HasMatch(tx.UserID, tx.AmountPaise, tx.Type, tx.Source,
			tx.OccurredAt.Add(-sameEventWindow), tx.OccurredAt.Add(sameEventWindow))
		if err != nil {
			return err
		}
		if dup {
			return ErrDuplicate
		}
	}

	category, err := s.categorize(ctx, tx)
	if err != nil {
		log.Printf("classify transaction: %v", err)
		category = UnknownCategory
	}
	tx.Category = category
	return s.repo.Create(tx)
}

func (s *Service) List(userID uuid.UUID, limit int, from, to time.Time) ([]models.Transaction, error) {
	return s.repo.List(userID, limit, from, to)
}

// Backfill classifies Unknown transactions. It stops at the first model
// error so an offline model server costs one failed request per run.
func (s *Service) Backfill(ctx context.Context) (int, error) {
	txs, err := s.repo.Uncategorized(backfillBatch)
	if err != nil {
		return 0, err
	}
	done := 0
	for i := range txs {
		category, err := s.categorize(ctx, &txs[i])
		if err != nil {
			return done, err
		}
		if err := s.repo.SetCategory(txs[i].ID, category); err != nil {
			return done, err
		}
		done++
	}
	return done, nil
}

// RunBackfill calls Backfill every interval until ctx is cancelled, logging
// only when the model server goes up or down rather than on every attempt.
func (s *Service) RunBackfill(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	state := ""
	for {
		n, err := s.Backfill(ctx)
		if n > 0 {
			log.Printf("categorised %d transactions", n)
		}
		if err != nil && state != "down" {
			log.Printf("classifier unavailable, transactions stay Unknown until it is: %v", err)
			state = "down"
		} else if err == nil && state != "up" {
			log.Printf("classifier at %s is reachable", s.cfg.URL)
			state = "up"
		}
		if err == nil && n == backfillBatch && ctx.Err() == nil {
			continue
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (s *Service) CreateGroup(userID uuid.UUID, GroupMembers []string, name string) (string, error) {
	return s.repo.CreateGroup(userID, GroupMembers, name)
}

type Expense struct {
	ID          string    `json:"id"`
	GroupID     string    `json:"group_id"`
	Name        string    `json:"name"`
	Amount      int64     `json:"amount"`
	PaidBy      string    `json:"paid_by"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
}

func toGroupExpense(row models.Expense) Expense {
	name := strings.TrimSpace(row.Description)
	return Expense{
		ID:          row.ID.String(),
		GroupID:     row.GroupID.String(),
		Name:        name,
		Amount:      row.Amount,
		PaidBy:      row.CreatedBy,
		Description: row.Description,
		CreatedAt:   row.CreatedAt,
	}
}

func (s *Service) ListExpense(userID, groupID uuid.UUID) ([]Expense, error) {
	rows, err := s.repo.ListExpense(userID, groupID)
	if err != nil {
		return nil, err
	}
	expenses := make([]Expense, 0, len(rows))
	for _, row := range rows {
		expenses = append(expenses, toGroupExpense(row))
	}
	return expenses, nil
}

func (s *Service) AddExpenses(userID, groupID uuid.UUID, amount int64, description string) (Expense, error) {
	row, err := s.repo.AddExpenses(userID, groupID, amount, description)
	if err != nil {
		return Expense{}, err
	}
	return toGroupExpense(row), nil
}
