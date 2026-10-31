package models

import (
	"github.com/google/uuid"
)

const (
	NotificationPending = "pending"
	NotificationSent    = "sent"
	NotificationRead    = "read"
)

// Notification tells ReceiverID about a group expense. The text shown is the
// expense's Description, and the sender is the expense's CreatedBy.
type Notification struct {
	BaseModel
	ExpenseID  uuid.UUID `gorm:"type:uuid;not null;index" json:"expense_id"`
	Expense    Expense   `gorm:"foreignKey:ExpenseID;references:ID" json:"expense"`
	ReceiverID uuid.UUID `gorm:"type:uuid;not null;index:idx_notification_receiver_status" json:"receiver_id"`
	Receiver   User      `gorm:"foreignKey:ReceiverID;references:ID" json:"-"`
	Status     string    `gorm:"not null;default:pending;index:idx_notification_receiver_status" json:"status"`
}
