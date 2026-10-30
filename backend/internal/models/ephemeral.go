package models

import (
	"time"

	"github.com/google/uuid"
)

type Ephemeral struct {
	BaseModel
	User     User      `gorm:"foreignKey:UserID;references:ID" json:"-"`
	UserID   uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_ephemeral_user_key" json:"user_id"`
	ExpireIn time.Time `gorm:"not null" json:"expire_in"`
	Key      string    `gorm:"not null;uniqueIndex:idx_ephemeral_user_key" json:"key"`
}
