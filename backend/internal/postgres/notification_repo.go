package postgres

import (
	"my_app/backend/internal/models"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type NotificationRepo struct {
	db *gorm.DB
}

func NewNotificatonRepo(db *gorm.DB) *NotificationRepo {
	return &NotificationRepo{db: db}
}

func (r *NotificationRepo) SaveDeviceToken(userID uuid.UUID, token string, expireIn time.Time) error {
	e := models.Ephemeral{UserID: userID, Key: token, ExpireIn: expireIn}
	return r.db.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "user_id"}, {Name: "key"}},
		DoUpdates: clause.Assignments(map[string]any{"expire_in": expireIn, "updated_at": time.Now(), "deleted_at": nil}),
	}).Create(&e).Error
}
