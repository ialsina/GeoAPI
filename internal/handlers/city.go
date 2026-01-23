package handlers

import (
	"context"
	"net/http"
	"strconv"

	"github.com/go-chi/render"
	"github.com/jackc/pgx/v5"
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
	countryCode := r.URL.Query().Get("country_code")

	var city models.City
	var err error

	switch {
	case geonameid != "":
		id, parseErr := strconv.ParseInt(geonameid, 10, 64)
		if parseErr != nil {
			http.Error(w, "Invalid 'geonameid' parameter", http.StatusBadRequest)
			return
		}
		err = h.DB.QueryRow(ctx, `
			SELECT geonameid, name, asciiname, country_code, population,
			       ST_Y(geom), ST_X(geom)
			FROM cities_1000
			WHERE geonameid = $1
		`, id).Scan(
			&city.GeonameID,
			&city.Name,
			&city.AsciiName,
			&city.Country,
			&city.Population,
			&city.Latitude,
			&city.Longitude,
		)

	case name != "":
		if countryCode != "" {
			// Search by name and country_code
			err = h.DB.QueryRow(ctx, `
				SELECT geonameid, name, asciiname, country_code, population,
				       ST_Y(geom), ST_X(geom)
				FROM cities_1000
				WHERE name = $1 AND country_code = $2
				ORDER BY population DESC
				LIMIT 1
			`, name, countryCode).Scan(
				&city.GeonameID,
				&city.Name,
				&city.AsciiName,
				&city.Country,
				&city.Population,
				&city.Latitude,
				&city.Longitude,
			)
		} else {
			// Search by name only
			err = h.DB.QueryRow(ctx, `
				SELECT geonameid, name, asciiname, country_code, population,
				       ST_Y(geom), ST_X(geom)
				FROM cities_1000
				WHERE name = $1
				ORDER BY population DESC
				LIMIT 1
			`, name).Scan(
				&city.GeonameID,
				&city.Name,
				&city.AsciiName,
				&city.Country,
				&city.Population,
				&city.Latitude,
				&city.Longitude,
			)
		}

	default:
		http.Error(w, "Either 'geonameid' or 'name' parameter is required", http.StatusBadRequest)
		return
	}

	if err != nil {
		http.Error(w, "City not found", http.StatusNotFound)
		return
	}

	render.JSON(w, r, city)
}

// SearchCities searches for cities by name (partial match, case-insensitive)
// Query parameters:
//   - name (required): partial city name to search for
//   - country_code (optional): filter by country code
//   - limit (optional): maximum number of results (default: 50, max: 200)
func (h *CityHandler) SearchCities(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()
	query := r.URL.Query()

	name := query.Get("name")
	if name == "" {
		http.Error(w, "'name' parameter is required", http.StatusBadRequest)
		return
	}

	countryCode := query.Get("country_code")
	limitStr := query.Get("limit")

	// Parse limit with defaults
	limit := 50
	if limitStr != "" {
		parsedLimit, err := strconv.Atoi(limitStr)
		if err != nil || parsedLimit < 1 {
			http.Error(w, "Invalid 'limit' parameter (must be a positive integer)", http.StatusBadRequest)
			return
		}
		if parsedLimit > 200 {
			parsedLimit = 200
		}
		limit = parsedLimit
	}

	var rows pgx.Rows
	var err error

	// Build query based on whether country_code is provided
	if countryCode != "" {
		rows, err = h.DB.Query(ctx, `
			SELECT geonameid, name, asciiname, country_code, population,
			       ST_Y(geom), ST_X(geom)
			FROM cities_1000
			WHERE name ILIKE $1 AND country_code = $2
			ORDER BY population DESC
			LIMIT $3
		`, "%"+name+"%", countryCode, limit)
	} else {
		rows, err = h.DB.Query(ctx, `
			SELECT geonameid, name, asciiname, country_code, population,
			       ST_Y(geom), ST_X(geom)
			FROM cities_1000
			WHERE name ILIKE $1
			ORDER BY population DESC
			LIMIT $2
		`, "%"+name+"%", limit)
	}

	if err != nil {
		http.Error(w, "Error searching cities", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var cities []models.City
	for rows.Next() {
		var city models.City
		err := rows.Scan(
			&city.GeonameID,
			&city.Name,
			&city.AsciiName,
			&city.Country,
			&city.Population,
			&city.Latitude,
			&city.Longitude,
		)
		if err != nil {
			http.Error(w, "Error reading city data", http.StatusInternalServerError)
			return
		}
		cities = append(cities, city)
	}

	if err = rows.Err(); err != nil {
		http.Error(w, "Error processing results", http.StatusInternalServerError)
		return
	}

	render.JSON(w, r, map[string]any{
		"cities": cities,
		"count":  len(cities),
	})
}

