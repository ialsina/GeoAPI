package handlers

import (
	"context"
	"net/http"
	"strconv"

	"github.com/go-chi/render"
	"github.com/jackc/pgx/v5/pgxpool"

	"city-api/internal/models"
)

type CityHandler struct {
	DB *pgxpool.Pool
}

func (h *CityHandler) GetCity(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	geonameid := r.URL.Query().Get("geonameid")
	name := r.URL.Query().Get("name")
	country := r.URL.Query().Get("country")

	var city models.City
	var err error

	switch {
	case geonameid != "":
		id, _ := strconv.ParseInt(geonameid, 10, 64)
		err = h.DB.QueryRow(ctx, `
			SELECT geonameid, name, country_code, population,
			       ST_Y(geom), ST_X(geom)
			FROM cities_1000
			WHERE geonameid = $1
		`, id).Scan(
			&city.GeonameID,
			&city.Name,
			&city.Country,
			&city.Population,
			&city.Latitude,
			&city.Longitude,
		)

	case name != "" && country != "":
		err = h.DB.QueryRow(ctx, `
			SELECT geonameid, name, country_code, population,
			       ST_Y(geom), ST_X(geom)
			FROM cities_1000
			WHERE name = $1 AND country_code = $2
			ORDER BY population DESC
			LIMIT 1
		`, name, country).Scan(
			&city.GeonameID,
			&city.Name,
			&city.Country,
			&city.Population,
			&city.Latitude,
			&city.Longitude,
		)

	default:
		http.Error(w, "Invalid query", http.StatusBadRequest)
		return
	}

	if err != nil {
		http.Error(w, "City not found", http.StatusNotFound)
		return
	}

	render.JSON(w, r, city)
}

