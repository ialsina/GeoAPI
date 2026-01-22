package main

import (
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"city-api/internal/db"
	"city-api/internal/handlers"
)

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL not set")
	}

	pool := db.NewPool(dsn)

	cityHandler := &handlers.CityHandler{DB: pool}
	boundaryHandler := &handlers.BoundaryHandler{DB: pool}

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/city", cityHandler.GetCity)
	r.Get("/boundary/by-point", boundaryHandler.ByPoint)
	r.Get("/boundary/by-city", boundaryHandler.ByCity)

	log.Println("Listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", r))
}

