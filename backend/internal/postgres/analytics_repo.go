package postgres

import (
	"my_app/backend/internal/analytics"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AnalyticsRepo struct {
	db *gorm.DB
}

func NewAnalyticsRepo(db *gorm.DB) *AnalyticsRepo {
	return &AnalyticsRepo{db: db}
}

func (r *AnalyticsRepo) PeriodTotals(userID uuid.UUID, from, to time.Time) (analytics.PeriodTotals, error) {
	var row struct {
		Total int64
		Count int
	}
	err := r.db.Raw(`
		SELECT COALESCE(SUM(amount_paise), 0)::bigint AS total,
		       COUNT(*)::int AS count
		FROM "transaction"
		WHERE user_id = ?
		  AND type = 'debit'
		  AND deleted_at IS NULL
		  AND occurred_at >= ?
		  AND occurred_at < ?`,
		userID, from.UTC(), to.UTC(),
	).Scan(&row).Error
	return analytics.PeriodTotals{TotalSpent: row.Total, Count: row.Count}, err
}

func (r *AnalyticsRepo) Categories(userID uuid.UUID, from, to time.Time) ([]analytics.CategoryRow, error) {
	var rows []analytics.CategoryRow
	err := r.db.Raw(`
		SELECT c.name AS name,
		       COALESCE(SUM(t.amount_paise), 0)::bigint AS amount,
		       COUNT(*)::int AS count
		FROM "transaction" t
		JOIN categories c ON c.id = t.category_id
		WHERE t.user_id = ?
		  AND t.type = 'debit'
		  AND t.deleted_at IS NULL
		  AND t.occurred_at >= ?
		  AND t.occurred_at < ?
		GROUP BY c.name
		ORDER BY amount DESC`,
		userID, from.UTC(), to.UTC(),
	).Scan(&rows).Error
	return rows, err
}

func (r *AnalyticsRepo) Merchants(userID uuid.UUID, from, to time.Time, limit int) ([]analytics.MerchantRow, error) {
	if limit <= 0 {
		limit = 5
	}
	var rows []analytics.MerchantRow
	err := r.db.Raw(`
		SELECT COALESCE(NULLIF(TRIM(t.vendor), ''), 'Unknown') AS merchant,
		       COALESCE(c.name, 'Other') AS category,
		       COALESCE(SUM(t.amount_paise), 0)::bigint AS amount,
		       COUNT(*)::int AS count,
		       MAX(t.occurred_at) AS last_visit
		FROM "transaction" t
		LEFT JOIN categories c ON c.id = t.category_id
		WHERE t.user_id = ?
		  AND t.type = 'debit'
		  AND t.deleted_at IS NULL
		  AND t.occurred_at >= ?
		  AND t.occurred_at < ?
		GROUP BY 1, 2
		ORDER BY amount DESC
		LIMIT ?`,
		userID, from.UTC(), to.UTC(), limit,
	).Scan(&rows).Error
	return rows, err
}

func (r *AnalyticsRepo) Largest(userID uuid.UUID, from, to time.Time) (*analytics.LargestExpense, error) {
	var row analytics.LargestExpense
	err := r.db.Raw(`
		SELECT t.id,
		       COALESCE(t.vendor, '') AS vendor,
		       COALESCE(c.name, 'Other') AS category,
		       t.amount_paise,
		       t.occurred_at
		FROM "transaction" t
		LEFT JOIN categories c ON c.id = t.category_id
		WHERE t.user_id = ?
		  AND t.type = 'debit'
		  AND t.deleted_at IS NULL
		  AND t.occurred_at >= ?
		  AND t.occurred_at < ?
		ORDER BY t.amount_paise DESC
		LIMIT 1`,
		userID, from.UTC(), to.UTC(),
	).Scan(&row).Error
	if err != nil {
		return nil, err
	}
	if row.ID == uuid.Nil {
		return nil, nil
	}
	return &row, nil
}

func (r *AnalyticsRepo) ByWeekday(userID uuid.UUID, from, to time.Time) ([]analytics.DayAmountRow, error) {
	var rows []analytics.DayAmountRow
	err := r.db.Raw(`
		SELECT EXTRACT(DOW FROM occurred_at AT TIME ZONE 'Asia/Kolkata')::int AS dow,
		       COALESCE(SUM(amount_paise), 0)::bigint AS amount
		FROM "transaction"
		WHERE user_id = ?
		  AND type = 'debit'
		  AND deleted_at IS NULL
		  AND occurred_at >= ?
		  AND occurred_at < ?
		GROUP BY 1
		ORDER BY 1`,
		userID, from.UTC(), to.UTC(),
	).Scan(&rows).Error
	return rows, err
}

func (r *AnalyticsRepo) ByHour(userID uuid.UUID, from, to time.Time) ([]analytics.HourAmountRow, error) {
	var rows []analytics.HourAmountRow
	err := r.db.Raw(`
		SELECT EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'Asia/Kolkata')::int AS hour,
		       COALESCE(SUM(amount_paise), 0)::bigint AS amount
		FROM "transaction"
		WHERE user_id = ?
		  AND type = 'debit'
		  AND deleted_at IS NULL
		  AND occurred_at >= ?
		  AND occurred_at < ?
		GROUP BY 1
		ORDER BY 1`,
		userID, from.UTC(), to.UTC(),
	).Scan(&rows).Error
	return rows, err
}

func (r *AnalyticsRepo) SplitShare(userID uuid.UUID, from, to time.Time) (int64, error) {
	var total int64
	err := r.db.Raw(`
		SELECT COALESCE(SUM(ei.amount_to_pay), 0)::bigint
		FROM exepense_items ei
		JOIN expenses e ON e.id = ei.expense_id AND e.deleted_at IS NULL
		WHERE ei.user_id = ?
		  AND ei.deleted_at IS NULL
		  AND e.created_at >= ?
		  AND e.created_at < ?`,
		userID, from.UTC(), to.UTC(),
	).Scan(&total).Error
	return total, err
}

func (r *AnalyticsRepo) Balances(userID uuid.UUID) (analytics.Balances, error) {
	uid := userID.String()
	var owed int64
	err := r.db.Raw(`
		SELECT COALESCE(SUM(ei.amount_to_pay), 0)::bigint
		FROM exepense_items ei
		JOIN expenses e ON e.id = ei.expense_id AND e.deleted_at IS NULL
		WHERE e.created_by = ?
		  AND ei.user_id <> ?
		  AND ei.deleted_at IS NULL`,
		uid, userID,
	).Scan(&owed).Error
	if err != nil {
		return analytics.Balances{}, err
	}
	var owe int64
	err = r.db.Raw(`
		SELECT COALESCE(SUM(ei.amount_to_pay), 0)::bigint
		FROM exepense_items ei
		JOIN expenses e ON e.id = ei.expense_id AND e.deleted_at IS NULL
		WHERE ei.user_id = ?
		  AND e.created_by <> ?
		  AND ei.deleted_at IS NULL`,
		userID, uid,
	).Scan(&owe).Error
	return analytics.Balances{YouOwePaise: owe, YouAreOwedPaise: owed}, err
}
