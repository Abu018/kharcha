package models

import (
	"time"

	"github.com/google/uuid"
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
	Category  string `gorm:"size:30;not null;default:Unknown" json:"category"`

	// When the payment happened; for SMS imports this is the SMS time.
	OccurredAt time.Time `gorm:"not null;default:CURRENT_TIMESTAMP;index" json:"occurred_at"`
	// manual or sms.
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
