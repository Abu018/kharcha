package db

import (
	"my_app/backend/internal/expense"
	"my_app/backend/internal/models"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func Migration(db *gorm.DB) error {
	if err := db.AutoMigrate(&models.Category{}); err != nil {
		return err
	}
	if err := seedCategories(db); err != nil {
		return err
	}
	if err := moveTransactionCategories(db); err != nil {
		return err
	}

	if err := db.AutoMigrate(
		&models.AuditLog{},
		&models.User{},
		&models.Transaction{},
		&models.
			Group{},
		&models.GroupMembers{},
		&models.Expense{},
		&models.ExepenseItems{},
		&models.Ephemeral{},
		&models.UserPresenceKeys{},
		&models.Notification{},
	); err != nil {
		return err
	}
	if db.Migrator().HasColumn(models.Expense{}, "name") {
		if err := db.Migrator().DropColumn(&models.Expense{}, "name"); err != nil {
			return err
		}
	}
	for _, column := range []string{
		"text", "created_by", "receiver",
		"sender_id", "title", "body", "type", "ref_id", "read_at",
	} {
		if db.Migrator().HasColumn(models.Notification{}, column) {
			if err := db.Migrator().DropColumn(&models.Notification{}, column); err != nil {
				return err
			}
		}
	}
	return nil
}

// seedCategories inserts every name in expense.Categories that is not in the
// table yet, so adding a category in code adds it here on the next start.
func seedCategories(db *gorm.DB) error {
	rows := make([]models.Category, 0, len(expense.Categories))
	for _, name := range expense.Categories {
		rows = append(rows, models.Category{Name: name})
	}
	return db.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "name"}},
		DoNothing: true,
	}).Create(&rows).Error
}

// moveTransactionCategories replaces the old category name column on
// transactions with category_id. Names that match no category become
// Unknown so the classifier picks them up again.
func moveTransactionCategories(db *gorm.DB) error {
	m := db.Migrator()
	if !m.HasTable(&models.Transaction{}) || !m.HasColumn(&models.Transaction{}, "category") {
		return nil
	}
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec(`ALTER TABLE "transaction" ADD COLUMN IF NOT EXISTS category_id uuid`).Error; err != nil {
			return err
		}
		err := tx.Exec(`
			UPDATE "transaction" t SET category_id = COALESCE(
				(SELECT id FROM categories c WHERE c.name = t.category),
				(SELECT id FROM categories c WHERE c.name = ?)
			)
			WHERE t.category_id IS NULL`, expense.UnknownCategory).Error
		if err != nil {
			return err
		}
		if err := tx.Exec(`ALTER TABLE "transaction" ALTER COLUMN category_id SET NOT NULL`).Error; err != nil {
			return err
		}
		return tx.Exec(`ALTER TABLE "transaction" DROP COLUMN category`).Error
	})
}
