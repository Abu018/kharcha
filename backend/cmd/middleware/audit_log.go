package middleware

import (
	"my_app/backend/internal/models"

	"gorm.io/gorm"
)

func Start(db *gorm.DB) {
	go func() {
		for e := range buffer {
			db.Create(&models.AuditLog{
				Ip:     e.Ip,
				Method: e.Method,
				Path:   e.Path,
				Status: e.Status,
			})
		}
	}()
}
