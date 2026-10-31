package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Transaction struct {
	BaseModel

	AmountPaise int64  `gorm:"not null" json:"amount_paise"`
	Currency    string `gorm:"size:3;not null;default:INR" json:"currency"`

	BankName    string `gorm:"size:100" json:"bank_name"`
	AccountType string `gorm:"size:30;not null" json:"account_type"`

	Type string `gorm:"size:20;not null" json:"type"`

	Vendor    string `gorm:"size:255" json:"vendor"`
	VendorUPI string `gorm:"size:255" json:"vendor_upi"`

	CategoryID  uuid.UUID `gorm:"type:uuid;not null;index" json:"category_id"`
	CategoryRef *Category `gorm:"foreignKey:CategoryID;references:ID" json:"-"`
	// Category is the name of the category, e.g. "Food". It is not stored:
	// it is read from CategoryRef when that is preloaded, and the repository
	// looks up CategoryID from it when saving.
	Category string `gorm:"-" json:"category"`

	// When the payment happened; for SMS imports this is the SMS time.
	OccurredAt time.Time `gorm:"not null;default:CURRENT_TIMESTAMP;index" json:"occurred_at"`
	// manual, sms or notification.
	Source string `gorm:"size:20;not null;default:manual" json:"source"`
	// Client-side identifier of the imported message. Unique per user so the
	// same SMS is never saved twice; NULL for manual entries.
	SourceRef *string `gorm:"size:100;uniqueIndex:idx_transaction_user_source_ref" json:"source_ref,omitempty"`

	UserID uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:idx_transaction_user_source_ref" json:"user_id"`
	User   User      `gorm:"foreignKey:UserID;references:ID" json:"-"`
}

func (Transaction) TableName() string {
	return "transaction"
}

func (t *Transaction) AfterFind(*gorm.DB) error {
	if t.CategoryRef != nil {
		t.Category = t.CategoryRef.Name
	}
	return nil
}
