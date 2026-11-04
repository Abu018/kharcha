package routes

import (
	"context"
	"my_app/backend/cmd/middleware"
	"my_app/backend/internal/analytics"
	"my_app/backend/internal/expense"
	"my_app/backend/internal/handler"
	"my_app/backend/internal/postgres"
	"my_app/backend/internal/presence"
	"my_app/backend/internal/profile"
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
	secretKeys := postgres.NewSecretKeyRepo(db)
	go secretKeys.RunTemporaryIDScheduler(context.Background())

	authService := register.NewAuthService(repo, cfg.Keycloak, secretKeys)
	authHandler := handler.NewAuthHandler(authService)
	expenseService := expense.NewService(expenseRepo, cfg.Classifier)
	presenceSvc := presence.NewService(secretKeys)
	expenseHandler := handler.NewExpenseHandler(expenseService, presenceSvc)
	analyticsHandler := handler.NewAnalyticsHandler(
		analytics.NewService(postgres.NewAnalyticsRepo(db)),
	)
	go expenseService.RunBackfill(context.Background(), time.Minute)
	profileHandler := handler.NewProfileHandler(profile.NewService(repo))
	presenceHandler := handler.NewPresenceHandler(secretKeys, presenceSvc)

	kc := gocloak.NewClient(cfg.Keycloak.URL)

	r.Route("/api/v1", func(api chi.Router) {
		// Public routes
		api.Post("/register", authHandler.Register)
		api.Post("/login", authHandler.Login)
		api.Post("/auth/refresh", authHandler.RefreshToken)

		// Protected routes
		api.Group(func(p chi.Router) {
			p.Use(middleware.Auth(kc, cfg.Keycloak))
			p.Get("/profile", profileHandler.GetProfile)
			p.Put("/profile", profileHandler.UpdateProfile)
			p.Get("/users", profileHandler.ListUsers)
			p.Get("/presence/temporary-id", presenceHandler.TemporaryID)
			p.Post("/presence/sightings", presenceHandler.Sightings)
			p.Post("/expense", expenseHandler.Expense)
			p.Get("/expenses", expenseHandler.List)
			p.Get("/expenses/monthly", expenseHandler.Monthly)
			p.Get("/analytics/overview", analyticsHandler.Overview)
			p.Post("/create-group", expenseHandler.CreateGroup)
			p.Get("/groups", expenseHandler.ListGroups)
			p.Get("/groups/{groupID}/expenses", expenseHandler.ListExpense)
			p.Post("/groups/{groupID}/expenses", expenseHandler.AddExpenses)
			p.Put("/expenses/{id}/category", expenseHandler.UpdateCategory)
			p.Get("/categories", expenseHandler.ListCategory)
		})

	})
}
