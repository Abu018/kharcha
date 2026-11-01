package models

import (
	"time"

	"github.com/google/uuid"
)

type UserPresenceKeys struct {
	BaseModel

	UserID    uuid.UUID `gorm:"type:uuid;not null;uniqueIndex" json:"user_id"`
	SecretKey string    `gorm:"type:text;not null" json:"-"`

	User User `gorm:"foreignKey:UserID;references:ID" json:"-"`
}

type Ephemeral struct {
	BaseModel

	UserID    uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:idx_ephemeral_user_slot" json:"user_id"`
	Key       string    `gorm:"type:varchar(16);not null;uniqueIndex" json:"-"`
	TimeSlot  int64     `gorm:"not null;uniqueIndex:idx_ephemeral_user_slot" json:"-"`
	ExpiresAt time.Time `gorm:"not null;index" json:"expires_at"`

	User User `gorm:"foreignKey:UserID;references:ID" json:"-"`
}
