package postgres

import (
	"my_app/backend/internal/expense"
	"my_app/backend/internal/models"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type ExpenseRepo struct {
	db *gorm.DB
}

func NewExpenseRepo(db *gorm.DB) *ExpenseRepo {
	return &ExpenseRepo{db: db}
}

func (r *ExpenseRepo) Create(tx *models.Transaction) error {
	res := r.db.Clauses(clause.OnConflict{DoNothing: true}).Create(tx)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return expense.ErrDuplicate
	}
	return nil
}

func (r *ExpenseRepo) List(userID uuid.UUID, limit int, from, to time.Time) ([]models.Transaction, error) {
	q := r.db.Where("user_id = ?", userID)
	if !from.IsZero() {
		q = q.Where("occurred_at >= ?", from)
	}
	if !to.IsZero() {
		q = q.Where("occurred_at < ?", to)
	}
	var txs []models.Transaction
	err := q.
		Order("occurred_at DESC, created_at DESC").
		Limit(limit).
		Find(&txs).Error
	return txs, err
}

func (r *ExpenseRepo) Uncategorized(limit int) ([]models.Transaction, error) {
	var txs []models.Transaction
	err := r.db.
		Where("category = ?", expense.UnknownCategory).
		Order("created_at").
		Limit(limit).
		Find(&txs).Error
	return txs, err
}

func (r *ExpenseRepo) SetCategory(id uuid.UUID, category string) error {
	return r.db.Model(&models.Transaction{}).
		Where("id = ?", id).
		Update("category", category).Error
}
