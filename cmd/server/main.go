package main

import (
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	httpSwagger "github.com/swaggo/http-swagger"

	"city-api/internal/db"
	"city-api/internal/handlers"

	_ "city-api/docs" // Swagger docs
)

// @title           City API
// @version         1.0
// @description     API for querying cities and administrative boundaries
// @termsOfService  http://swagger.io/terms/

// @contact.name   API Support
// @contact.url    http://www.swagger.io/support
// @contact.email  support@swagger.io

// @license.name  Apache 2.0
// @license.url   http://www.apache.org/licenses/LICENSE-2.0.html

// @host      localhost:8080
// @BasePath  /

// @schemes   http

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL not set")
	}

	pool := db.NewPool(dsn)

	cityHandler := &handlers.CityHandler{DB: pool}
	airportHandler := &handlers.AirportHandler{DB: pool}
	boundaryHandler := &handlers.BoundaryHandler{DB: pool}
	countryHandler := &handlers.CountryHandler{DB: pool}
	healthHandler := &handlers.HealthHandler{DB: pool}

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/health", healthHandler.Health)
	r.Get("/city", cityHandler.GetCity)
	r.Get("/cities", cityHandler.SearchCities)
	r.Get("/airport", airportHandler.GetAirport)
	r.Get("/airports", airportHandler.SearchAirports)
	r.Get("/boundary", boundaryHandler.GetBoundary)
	r.Get("/country", countryHandler.GetCountry)
	r.Get("/countries", countryHandler.ListCountries)

	// Swagger documentation
	r.Get("/docs/*", httpSwagger.Handler())

	log.Println("Listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", r))
}
