package routes

import (
	"context"
	"my_app/backend/cmd/middleware"
	"my_app/backend/internal/expense"
	"my_app/backend/internal/handler"
	"my_app/backend/internal/postgres"
	"my_app/backend/internal/register"
	"my_app/backend/internal/utils"
	"time"

	"github.com/Nerzal/gocloak/v13"
	"github.com/go-chi/chi/v5"
	"gorm.io/gorm"
)

func RegisterExpenseRoutes(
	r *chi.Mux,
	db *gorm.DB,
	cfg *utils.Config,
) {
	repo := postgres.NewUserRepo(db, cfg.Keycloak)
	expenseRepo := postgres.NewExpenseRepo(db)
	authService := register.NewAuthService(repo, cfg.Keycloak)
	authHandler := handler.NewAuthHandler(authService)
	expenseService := expense.NewService(expenseRepo, cfg.Classifier)
	expenseHandler := handler.NewExpenseHandler(expenseService)
	go expenseService.RunBackfill(context.Background(), time.Minute)

	kc := gocloak.NewClient(cfg.Keycloak.URL)

	r.Route("/api/v1", func(api chi.Router) {
		// Public routes
		api.Post("/register", authHandler.Register)
		api.Post("/login", authHandler.Login)
		api.Post("/auth/refresh", authHandler.RefreshToken)

		// Protected routes
		api.Group(func(p chi.Router) {
			p.Use(middleware.Auth(kc, cfg.Keycloak))
			p.Put("/profile", handler.UpdateProfile)
			p.Post("/expense", expenseHandler.Expense)
			p.Get("/expenses", expenseHandler.List)
		})
	})
}
