package db

import (
	"my_app/backend/internal/models"

	"gorm.io/gorm"
)

func Migration(db *gorm.DB) error {

	if err := db.AutoMigrate(
		&models.AuditLog{},
		&models.User{},
		&models.Transaction{},
		&models.
			Group{},
		&models.GroupMembers{},
		&models.Expense{},
		&models.ExepenseItems{},
	); err != nil {
		return err
	}
	if db.Migrator().HasColumn(models.Expense{}, "name") {
		if err := db.Migrator().DropColumn(&models.Expense{}, "name"); err != nil {
			return err
		}
	}
	return nil
}
