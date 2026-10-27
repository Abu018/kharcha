package models

type User struct {
	BaseModel
	FirstName string `gorm:"not null"`
	LastName  string `gorm:"not null;default:''"`
	Email     string `gorm:"not null;uniqueIndex"`
	// Optional profile details; NULL until the user fills them in.
	Age *int
	// Monthly salary in whole rupees.
	Salary *int64
}
