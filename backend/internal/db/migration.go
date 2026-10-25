package db

import (
	"my_app/backend/internal/models"

	"gorm.io/gorm"
)

func Migration(db *gorm.DB) error {
	return db.AutoMigrate(
		&models.AuditLog{},
		&models.User{},
		&models.Transaction{},
	)
}
