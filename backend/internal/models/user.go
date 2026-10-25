package models

type User struct {
	BaseModel
	FirstName string `gorm:"not null"`
	LastName  string `gorm:"not null;default:''"`
	Email     string `gorm:"not null;uniqueIndex"`
}
