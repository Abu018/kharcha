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
		&models.Ephemeral{},
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
