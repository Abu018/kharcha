package models

import "github.com/google/uuid"

type Expense struct {
	BaseModel
	GroupID     uuid.UUID `gorm:"type:uuid;not null" json:"group_id"`
	Group       Group     `gorm:"foreignKey:GroupID;references:ID" json:"-"`
	CreatedBy   string    `json:"name" gorm:"not null"`
	Amount      int64     `json:"amount" gorm:"not null"`
	Description string    `json:"description" gorm:"not null"`
}
type ExepenseItems struct {
	BaseModel
	ExpenseID   uuid.UUID `gorm:"type:uuid;not null" json:"expense_id"`
	Expense     Expense   `gorm:"foreignKey:ExpenseID;references:ID" json:"-"`
	UserID      uuid.UUID `json:"user_id" gorm:"not null"`
	AmountToPay int       `json:"amount" gorm:"not null"`
}
