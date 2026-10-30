package routes

import (
	"my_app/backend/cmd/middleware"
	"my_app/backend/internal/handler"
	notification "my_app/backend/internal/notificaition"
	"my_app/backend/internal/postgres"
	"my_app/backend/internal/utils"

	"github.com/Nerzal/gocloak/v13"
	"github.com/go-chi/chi/v5"
	"gorm.io/gorm"
)

func RegisterNotificationRoutes(r *chi.Mux, db *gorm.DB, cfg *utils.Config) {
	notificatonRepo := postgres.NewNotificatonRepo(db)
	notificationService := notification.NewNotificationService(notificatonRepo)
	notificationHandler := handler.NewNotificationHandler(notificationService)

	kc := gocloak.NewClient(cfg.Keycloak.URL)

	// "/api/v1" is already mounted by RegisterExpenseRoutes, and chi panics
	// if the same prefix is mounted twice, so these use full paths.
	r.Group(func(p chi.Router) {
		p.Use(middleware.Auth(kc, cfg.Keycloak))
		p.Post("/api/v1/token", notificationHandler.RegisterDeviceToken)
	})
}
