package main

import (
	"fmt"
	"log"
	"my_app/backend/cmd/middleware"
	"my_app/backend/cmd/server"
	"my_app/backend/internal/db"
	"my_app/backend/internal/models"
	"my_app/backend/internal/routes"
	"my_app/backend/internal/utils"

	"github.com/go-chi/chi/v5"
	"github.com/joho/godotenv"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func main() {
	_ = godotenv.Load()
	cfg, err := utils.Load()
	if err != nil {
		log.Fatal(err)
	}

	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		cfg.DB.ServerConfig.Host,
		cfg.DB.ServerConfig.Port,
		cfg.DB.User,
		cfg.DB.Password,
		cfg.DB.Name,
		cfg.DB.SSLMode,
	)
	conn, err := gorm.Open(postgres.Open(dsn), &gorm.Config{TranslateError: true})
	if err != nil {
		log.Fatal(err)
	}
	if conn.Migrator().HasColumn(&models.User{}, "password_hash") {
		if err := conn.Migrator().DropColumn(&models.User{}, "password_hash"); err != nil {
			log.Fatal(err)
		}
	}
	fmt.Println("migration is started")
	if err := db.Migration(conn); err != nil {
		log.Fatal(err)
	}
	middleware.Start(conn)
	router := chi.NewRouter()
	routes.SetupRoutes(router, conn, cfg)
	srv := server.NewServer(router, cfg.Server.Addr())
	if err := srv.Start(); err != nil {
		log.Println("server failed: ", err)
	}
}
