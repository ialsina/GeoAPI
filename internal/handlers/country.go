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

type CountryHandler struct {
	DB *pgxpool.Pool
}

// GetCountry godoc
// @Summary      Get a country by its ISO code
// @Description  Retrieve a single country by ISO 3166-1 alpha-2 or alpha-3 code
// @Tags         countries
// @Accept       json
// @Produce      json
// @Param        iso2  query     string  false  "ISO 3166-1 alpha-2 code (e.g. US)"
// @Param        iso3  query     string  false  "ISO 3166-1 alpha-3 code (e.g. USA)"
// @Success      200   {object}  models.Country
// @Failure      400   {string}  string  "Bad Request - Invalid parameters"
// @Failure      404   {string}  string  "Not Found - Country not found"
// @Router       /country [get]
func (h *CountryHandler) GetCountry(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	iso2 := r.URL.Query().Get("iso2")
	iso3 := r.URL.Query().Get("iso3")

	if iso2 == "" && iso3 == "" {
		http.Error(w, "Either 'iso2' or 'iso3' parameter is required", http.StatusBadRequest)
		return
	}

	var country models.Country
	var err error

	switch {
	case iso2 != "":
		err = h.DB.QueryRow(ctx, `
			SELECT iso2, iso3, name, m49_code, region, sub_region, capital, tld, continent
			FROM countries
			WHERE iso2 = UPPER($1)
		`, iso2).Scan(
			&country.ISO2,
			&country.ISO3,
			&country.Name,
			&country.M49Code,
			&country.Region,
			&country.SubRegion,
			&country.Capital,
			&country.TLD,
			&country.Continent,
		)
	case iso3 != "":
		err = h.DB.QueryRow(ctx, `
			SELECT iso2, iso3, name, m49_code, region, sub_region, capital, tld, continent
			FROM countries
			WHERE iso3 = UPPER($1)
		`, iso3).Scan(
			&country.ISO2,
			&country.ISO3,
			&country.Name,
			&country.M49Code,
			&country.Region,
			&country.SubRegion,
			&country.Capital,
			&country.TLD,
			&country.Continent,
		)
	}

	if err != nil {
		if err == pgx.ErrNoRows {
			http.Error(w, "Country not found", http.StatusNotFound)
			return
		}
		http.Error(w, "Error retrieving country", http.StatusInternalServerError)
		return
	}

	render.JSON(w, r, country)
}

// ListCountries godoc
// @Summary      List countries
// @Description  List countries with optional pagination
// @Tags         countries
// @Accept       json
// @Produce      json
// @Param        limit   query     int     false  "Maximum number of results (default: 250, max: 500)"
// @Param        offset  query     int     false  "Offset for pagination (default: 0)"
// @Success      200     {object}  map[string]interface{}  "Response with countries array and count"
// @Failure      400     {string}  string  "Bad Request - Invalid parameters"
// @Failure      500     {string}  string  "Internal Server Error"
// @Router       /countries [get]
func (h *CountryHandler) ListCountries(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()
	query := r.URL.Query()

	limitStr := query.Get("limit")
	offsetStr := query.Get("offset")

	// Parse limit with defaults
	limit := 250
	if limitStr != "" {
		parsedLimit, err := strconv.Atoi(limitStr)
		if err != nil || parsedLimit < 1 {
			http.Error(w, "Invalid 'limit' parameter (must be a positive integer)", http.StatusBadRequest)
			return
		}
		if parsedLimit > 500 {
			parsedLimit = 500
		}
		limit = parsedLimit
	}

	// Parse offset with defaults
	offset := 0
	if offsetStr != "" {
		parsedOffset, err := strconv.Atoi(offsetStr)
		if err != nil || parsedOffset < 0 {
			http.Error(w, "Invalid 'offset' parameter (must be a non-negative integer)", http.StatusBadRequest)
			return
		}
		offset = parsedOffset
	}

	rows, err := h.DB.Query(ctx, `
		SELECT iso2, iso3, name, m49_code, region, sub_region, capital, tld, continent
		FROM countries
		ORDER BY name
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		http.Error(w, "Error listing countries", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var countries []models.Country
	for rows.Next() {
		var country models.Country
		err := rows.Scan(
			&country.ISO2,
			&country.ISO3,
			&country.Name,
			&country.M49Code,
			&country.Region,
			&country.SubRegion,
			&country.Capital,
			&country.TLD,
			&country.Continent,
		)
		if err != nil {
			http.Error(w, "Error reading country data", http.StatusInternalServerError)
			return
		}
		countries = append(countries, country)
	}

	if err = rows.Err(); err != nil {
		http.Error(w, "Error processing results", http.StatusInternalServerError)
		return
	}

	render.JSON(w, r, map[string]any{
		"countries": countries,
		"count":     len(countries),
		"limit":     limit,
		"offset":    offset,
	})
}
