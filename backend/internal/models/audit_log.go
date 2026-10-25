package models

type AuditLog struct {
	BaseModel
	Ip     string `db:"ip"`
	Method string `db:"method"`
	Path   string `db:"path"`
	Status int    `db:"status"`
}

func (AuditLog) TableName() string {
	return "audit_log"
}
