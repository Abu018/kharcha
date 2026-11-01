package postgres

import (
	"errors"
	"fmt"
	"my_app/backend/internal/expense"
	"my_app/backend/internal/models"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const batchSize = 100

type ExpenseRepo struct {
	db *gorm.DB
}

func NewExpenseRepo(db *gorm.DB) *ExpenseRepo {
	return &ExpenseRepo{db: db}
}

// categoryID returns the id of the category called name.
func (r *ExpenseRepo) categoryID(name string) (uuid.UUID, error) {
	var c models.Category
	if err := r.db.Select("id").Where("name = ?", name).First(&c).Error; err != nil {
		return uuid.Nil, fmt.Errorf("category %q: %w", name, err)
	}
	return c.ID, nil
}

func (r *ExpenseRepo) Create(tx *models.Transaction) error {
	id, err := r.categoryID(tx.Category)
	if err != nil {
		return err
	}
	tx.CategoryID = id
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
		Preload("CategoryRef").
		Order("occurred_at DESC, created_at DESC").
		Limit(limit).
		Find(&txs).Error
	return txs, err
}

func (r *ExpenseRepo) HasMatch(userID uuid.UUID, amountPaise int64, txType, source string, from, to time.Time) (bool, error) {
	var count int64
	err := r.db.Model(&models.Transaction{}).
		Where("user_id = ? AND amount_paise = ? AND type = ? AND source NOT IN (?, 'manual')", userID, amountPaise, txType, source).
		Where("occurred_at BETWEEN ? AND ?", from, to).
		Limit(1).
		Count(&count).Error
	return count > 0, err
}

func (r *ExpenseRepo) Uncategorized(limit int) ([]models.Transaction, error) {
	var txs []models.Transaction
	err := r.db.
		Where("category_id = (SELECT id FROM categories WHERE name = ?)", expense.UnknownCategory).
		Order("created_at").
		Limit(limit).
		Find(&txs).Error
	return txs, err
}

func (r *ExpenseRepo) SetCategory(id uuid.UUID, category string) error {
	categoryID, err := r.categoryID(category)
	if err != nil {
		return err
	}
	return r.db.Model(&models.Transaction{}).
		Where("id = ?", id).
		Update("category_id", categoryID).Error
}

func (r *ExpenseRepo) UpdateCategory(userID, id, categoryID uuid.UUID) (models.Transaction, error) {
	res := r.db.Model(&models.Transaction{}).
		Where("id = ? AND user_id = ?", id, userID).
		Update("category_id", categoryID)
	if res.Error != nil {
		return models.Transaction{}, res.Error
	}
	if res.RowsAffected == 0 {
		return models.Transaction{}, expense.ErrNotFound
	}
	var tx models.Transaction
	err := r.db.Preload("CategoryRef").First(&tx, "id = ?", id).Error
	return tx, err
}

func (r *ExpenseRepo) Category(id uuid.UUID) (models.Category, error) {
	var c models.Category
	err := r.db.First(&c, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return models.Category{}, expense.ErrInvalidCategory
	}
	return c, err
}

func (r *ExpenseRepo) ListCategory() ([]models.Category, error) {
	var categories []models.Category
	err := r.db.Order("name").Find(&categories).Error
	return categories, err
}

func (r *ExpenseRepo) MonthlySpent(userID uuid.UUID, year int) ([]expense.Series, error) {

	var points []expense.Series
	err := r.db.Raw(`
		SELECT to_char(m.month, 'Mon') AS x,
		       COALESCE(SUM(t.amount_paise), 0)::bigint AS y
		FROM generate_series(make_date(?, 1, 1)::timestamp,
		                     make_date(?, 12, 1)::timestamp,
		                     interval '1 month') AS m(month)
		LEFT JOIN "transaction" t
		       ON t.user_id = ?
		      AND t.type = 'debit'
		      AND t.deleted_at IS NULL
		      AND date_trunc('month', t.occurred_at AT TIME ZONE 'Asia/Kolkata') = m.month
		GROUP BY m.month
		ORDER BY m.month`,
		year, year, userID,
	).Scan(&points).Error
	return points, err
}

func (r *ExpenseRepo) HighestSpendingAmount(userID uuid.UUID, year int) (int64, error) {
	var highest int64
	err := r.db.Raw(`
		SELECT COALESCE(MAX(monthly), 0)::bigint
		FROM (
			SELECT SUM(amount_paise) AS monthly
			FROM "transaction"
			WHERE user_id = ?
			  AND type = 'debit'
			  AND deleted_at IS NULL
			  AND EXTRACT(YEAR FROM occurred_at AT TIME ZONE 'Asia/Kolkata') = ?
			GROUP BY date_trunc('month', occurred_at AT TIME ZONE 'Asia/Kolkata')
		) AS months`,
		userID, year,
	).Scan(&highest).Error
	return highest, err
}

func (r *ExpenseRepo) CreateGroup(userID uuid.UUID, GroupMembers []string, GroupName string) (string, error) {
	groupID := models.Group{Name: GroupName,
		UserID:    userID,
		CreatedBy: userID.String(),
	}

	members := make([]models.GroupMembers, len(GroupMembers))
	err := r.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&groupID).Error; err != nil {
			return err
		}
		if len(members) == 0 {
			return nil
		}
		for index, val := range GroupMembers {
			id, err := uuid.Parse(val)
			if err != nil {
				return err
			}
			members[index].UserID = id
			members[index].GroupID = groupID.ID
		}
		return tx.CreateInBatches(members, batchSize).Error
	})
	if err != nil {
		return "", err
	}
	return groupID.ID.String(), nil
}

func (r *ExpenseRepo) ListGroups(userID uuid.UUID) ([]models.Group, error) {
	var groups []models.Group
	err := r.db.
		Preload("User").
		Preload("Members", func(db *gorm.DB) *gorm.DB { return db.Order("created_at") }).
		Preload("Members.User").
		Where("user_id = ? OR id IN (?)", userID,
			r.db.Model(&models.GroupMembers{}).Select("group_id").Where("user_id = ?", userID)).
		Order("created_at DESC").
		Find(&groups).Error
	return groups, err
}

func (r *ExpenseRepo) inGroup(userID, groupID uuid.UUID) (bool, error) {
	var n int64
	err := r.db.Raw(`
		SELECT COUNT(*) FROM (
			SELECT id FROM groups
			WHERE id = ? AND user_id = ? AND deleted_at IS NULL
			UNION
			SELECT group_id FROM group_members
			WHERE group_id = ? AND user_id = ? AND deleted_at IS NULL
		) AS g`,
		groupID, userID, groupID, userID,
	).Scan(&n).Error
	return n > 0, err
}

func (r *ExpenseRepo) ListExpense(userID, groupID uuid.UUID) ([]models.Expense, error) {
	ok, err := r.inGroup(userID, groupID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, expense.ErrNotGroupMember
	}
	var result []models.Expense
	err = r.db.
		Where("group_id = ?", groupID).
		Order("created_at DESC").
		Find(&result).Error
	return result, err
}

func (r *ExpenseRepo) AddExpenses(userID, groupID uuid.UUID, amount int64, description string) (models.Expense, error) {
	ok, err := r.inGroup(userID, groupID)
	if err != nil {
		return models.Expense{}, err
	}
	if !ok {
		return models.Expense{}, expense.ErrNotGroupMember
	}
	row := models.Expense{
		GroupID:     groupID,
		CreatedBy:   userID.String(),
		Amount:      amount,
		Description: description,
	}
	if err := r.db.Create(&row).Error; err != nil {
		return models.Expense{}, err
	}
	return row, nil
}
