package models

import "github.com/google/uuid"

type Group struct {
	BaseModel
	Name      string    `json:"name"`
	CreatedBy string    `json:"created_by"`
	UserID    uuid.UUID `gorm:"type:uuid;not null;index" json:"user_id"`
	User      User      `gorm:"foreignKey:UserID;references:ID" json:"-"`
	// Members are the users added to the group; the owner (UserID) is not
	// one of them.
	Members []GroupMembers `gorm:"foreignKey:GroupID" json:"-"`
}

type GroupMembers struct {
	BaseModel
	GroupID uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_group_member" json:"group_id"`
	UserID  uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_group_member;index" json:"user_id"`
	User    User      `gorm:"foreignKey:UserID;references:ID" json:"-"`
}
