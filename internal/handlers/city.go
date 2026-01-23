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

// GetCity godoc
// @Summary      Get a city by ID or name
// @Description  Retrieve a single city by geonameid, or by name (optionally with country_code)
// @Tags         cities
// @Accept       json
// @Produce      json
// @Param        geonameid   query     int     false  "Geoname ID of the city"
// @Param        name        query     string  false  "Name of the city"
// @Param        country_code query    string  false  "Country code (ISO 2-letter), required if searching by name"
// @Success      200         {object}  models.City
// @Failure      400         {string}  string  "Bad Request - Invalid parameters"
// @Failure      404         {string}  string  "Not Found - City not found"
// @Router       /city [get]
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

// SearchCities godoc
// @Summary      Search cities by name
// @Description  Search for cities by name using fuzzy matching (trigram similarity). Returns a list of matching cities ordered by similarity and population.
// @Tags         cities
// @Accept       json
// @Produce      json
// @Param        name          query     string  true   "City name to search for (fuzzy match)"
// @Param        country_code  query     string  false  "Filter by country code (ISO 2-letter)"
// @Param        limit         query     int     false  "Maximum number of results (default: 50, max: 200)"
// @Param        threshold     query     number  false  "Minimum similarity threshold (default: 0.2, range: 0.0-1.0)"
// @Success      200           {object}  map[string]interface{}  "Response with cities array and count"
// @Failure      400           {string}  string  "Bad Request - Invalid parameters"
// @Failure      500           {string}  string  "Internal Server Error"
// @Router       /cities [get]
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
	thresholdStr := query.Get("threshold")

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

	// Parse similarity threshold (default: 0.2)
	threshold := 0.2
	if thresholdStr != "" {
		parsedThreshold, err := strconv.ParseFloat(thresholdStr, 64)
		if err != nil || parsedThreshold < 0.0 || parsedThreshold > 1.0 {
			http.Error(w, "Invalid 'threshold' parameter (must be a float between 0.0 and 1.0)", http.StatusBadRequest)
			return
		}
		threshold = parsedThreshold
	}

	var rows pgx.Rows
	var err error

	// Build query using fuzzy matching with trigram similarity
	// Search both name and asciiname, order by best similarity match first, then by population
	if countryCode != "" {
		rows, err = h.DB.Query(ctx, `
			SELECT geonameid, name, asciiname, country_code, population,
			       ST_Y(geom), ST_X(geom),
			       GREATEST(
			           similarity(name, $1),
			           similarity(asciiname, $1)
			       ) AS sim
			FROM cities_1000
			WHERE country_code = $2
			  AND (
			       similarity(name, $1) >= $3
			    OR similarity(asciiname, $1) >= $3
			  )
			ORDER BY sim DESC, population DESC
			LIMIT $4
		`, name, countryCode, threshold, limit)
	} else {
		rows, err = h.DB.Query(ctx, `
			SELECT geonameid, name, asciiname, country_code, population,
			       ST_Y(geom), ST_X(geom),
			       GREATEST(
			           similarity(name, $1),
			           similarity(asciiname, $1)
			       ) AS sim
			FROM cities_1000
			WHERE similarity(name, $1) >= $2
			   OR similarity(asciiname, $1) >= $2
			ORDER BY sim DESC, population DESC
			LIMIT $3
		`, name, threshold, limit)
	}

	if err != nil {
		http.Error(w, "Error searching cities", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var cities []models.City
	for rows.Next() {
		var city models.City
		var similarity float64 // Temporary variable to hold similarity score
		err := rows.Scan(
			&city.GeonameID,
			&city.Name,
			&city.AsciiName,
			&city.Country,
			&city.Population,
			&city.Latitude,
			&city.Longitude,
			&similarity, // Scan similarity score but don't use it
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

