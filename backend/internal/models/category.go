package models

type Category struct {
	BaseModel
	Name string `gorm:"size:30;not null;uniqueIndex" json:"name"`
}
