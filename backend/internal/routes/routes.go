package routes

import (
	"my_app/backend/cmd/middleware"
	"my_app/backend/internal/utils"

	"github.com/go-chi/chi/v5"
	"gorm.io/gorm"
)

func SetupRoutes(r *chi.Mux, db *gorm.DB, cfg *utils.Config) {
	r.Use(middleware.CORS(cfg.CORSOrigins))
	r.Use(middleware.Middleware)
	RegisterExpenseRoutes(r, db, cfg)
	RegisterNotificationRoutes(r, db, cfg)
}
