package handlers

import (
	"context"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/render"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"city-api/internal/models"
)

type AirportHandler struct {
	DB *pgxpool.Pool
}

// GetAirport godoc
// @Summary      Get an airport by ID, ident, IATA code, or name
// @Description  Retrieve a single airport by id, ident, iata, icao, or by name (optionally with country_code)
// @Tags         airports
// @Accept       json
// @Produce      json
// @Param        id           query     int     false  "ID of the airport"
// @Param        ident        query     string  false  "Ident of the airport"
// @Param        iata         query     string  false  "IATA code of the airport (case-insensitive)"
// @Param        icao         query     string  false  "ICAO code of the airport (case-insensitive)"
// @Param        name         query     string  false  "Name of the airport"
// @Param        country_code query     string  false  "Country code (ISO 2-letter), required if searching by name"
// @Success      200          {object}  models.Airport
// @Failure      400          {string}  string  "Bad Request - Invalid parameters"
// @Failure      404          {string}  string  "Not Found - Airport not found"
// @Router       /airport [get]
func (h *AirportHandler) GetAirport(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	id := r.URL.Query().Get("id")
	ident := r.URL.Query().Get("ident")
	name := r.URL.Query().Get("name")
	countryCode := r.URL.Query().Get("country_code")

	iata = strings.ToUpper(strings.TrimSpace(iata))
	icao = strings.ToUpper(strings.TrimSpace(icao))

	var airport models.Airport
	var err error

	switch {
	case id != "":
		parsedID, parseErr := strconv.ParseInt(id, 10, 64)
		if parseErr != nil {
			http.Error(w, "Invalid 'id' parameter", http.StatusBadRequest)
			return
		}
		err = h.DB.QueryRow(ctx, `
			SELECT id, ident, type, name, iso_country, municipality,
			       latitude, longitude, elevation, iata, icao
			FROM airports
			WHERE id = $1
		`, parsedID).Scan(
			&airport.ID,
			&airport.Ident,
			&airport.Type,
			&airport.Name,
			&airport.Country,
			&airport.Municipality,
			&airport.Latitude,
			&airport.Longitude,
			&airport.Elevation,
			&airport.IATA,
			&airport.ICAO,
		)

	case ident != "":
		err = h.DB.QueryRow(ctx, `
			SELECT id, ident, type, name, iso_country, municipality,
			       latitude, longitude, elevation, iata, icao
			FROM airports
			WHERE ident = $1
		`, ident).Scan(
			&airport.ID,
			&airport.Ident,
			&airport.Type,
			&airport.Name,
			&airport.Country,
			&airport.Municipality,
			&airport.Latitude,
			&airport.Longitude,
			&airport.Elevation,
			&airport.IATA,
			&airport.ICAO,
		)

	case iata != "":
		err = h.DB.QueryRow(ctx, `
			SELECT id, ident, type, name, iso_country, municipality,
			       latitude, longitude, elevation, iata, icao
			FROM airports
			WHERE iata = $1
		`, iata).Scan(
			&airport.ID,
			&airport.Ident,
			&airport.Type,
			&airport.Name,
			&airport.Country,
			&airport.Municipality,
			&airport.Latitude,
			&airport.Longitude,
			&airport.Elevation,
			&airport.IATA,
			&airport.ICAO,
		)

	case icao != "":
		err = h.DB.QueryRow(ctx, `
			SELECT id, ident, type, name, iso_country, municipality,
			       latitude, longitude, elevation, iata, icao
			FROM airports
			WHERE icao = $1
		`, icao).Scan(
			&airport.ID,
			&airport.Ident,
			&airport.Type,
			&airport.Name,
			&airport.Country,
			&airport.Municipality,
			&airport.Latitude,
			&airport.Longitude,
			&airport.Elevation,
			&airport.IATA,
			&airport.ICAO,
		)

	case name != "":
		if countryCode != "" {
			// Search by name and country_code
			err = h.DB.QueryRow(ctx, `
				SELECT id, ident, type, name, iso_country, municipality,
				       latitude, longitude, elevation, iata_code, icao_code
				FROM airports
				WHERE name = $1 AND iso_country = $2
				LIMIT 1
			`, name, countryCode).Scan(
				&airport.ID,
				&airport.Ident,
				&airport.Type,
				&airport.Name,
				&airport.Country,
				&airport.Municipality,
				&airport.Latitude,
				&airport.Longitude,
				&airport.Elevation,
				&airport.IATA,
				&airport.ICAO,
			)
		} else {
			// Search by name only
			err = h.DB.QueryRow(ctx, `
				SELECT id, ident, type, name, iso_country, municipality,
				       latitude, longitude, elevation, iata, icao
				FROM airports
				WHERE name = $1
				LIMIT 1
			`, name).Scan(
				&airport.ID,
				&airport.Ident,
				&airport.Type,
				&airport.Name,
				&airport.Country,
				&airport.Municipality,
				&airport.Latitude,
				&airport.Longitude,
				&airport.Elevation,
				&airport.IATA,
				&airport.ICAO,
			)
		}

	default:
		http.Error(w, "Either 'id', 'ident', 'iata', 'icao', or 'name' parameter is required", http.StatusBadRequest)
		return
	}

	if err != nil {
		http.Error(w, "Airport not found", http.StatusNotFound)
		return
	}

	render.JSON(w, r, airport)
}

// SearchAirports godoc
// @Summary      Search airports by name
// @Description  Search for airports by name using fuzzy matching (trigram similarity), or by exact IATA/ICAO code. Returns a list of matching airports.
// @Tags         airports
// @Accept       json
// @Produce      json
// @Param        name          query     string  false  "Airport name to search for (fuzzy match)"
// @Param        iata          query     string  false  "Exact IATA code (case-insensitive)"
// @Param        icao          query     string  false  "Exact ICAO code (case-insensitive)"
// @Param        country_code  query     string  false  "Filter by country code (ISO 2-letter)"
// @Param        limit         query     int     false  "Maximum number of results (default: 50, max: 200)"
// @Param        threshold     query     number  false  "Minimum similarity threshold (default: 0.2, range: 0.0-1.0)"
// @Success      200           {object}  map[string]interface{}  "Response with airports array and count"
// @Failure      400           {string}  string  "Bad Request - Invalid parameters"
// @Failure      500           {string}  string  "Internal Server Error"
// @Router       /airports [get]
func (h *AirportHandler) SearchAirports(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()
	query := r.URL.Query()

	name := query.Get("name")
	iata := query.Get("iata")
	if iata == "" {
		// Legacy param name for backward compatibility
		iata = query.Get("iata_code")
	}
	icao := query.Get("icao")
	if icao == "" {
		// Legacy param name for backward compatibility
		icao = query.Get("icao_code")
	}
	iata = strings.ToUpper(strings.TrimSpace(iata))
	icao = strings.ToUpper(strings.TrimSpace(icao))

	if name == "" && iata == "" && icao == "" {
		http.Error(w, "Either 'name', 'iata', or 'icao' parameter is required", http.StatusBadRequest)
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

	if name == "" {
		// Exact code search (IATA/ICAO)
		rows, err = h.DB.Query(ctx, `
			SELECT id, ident, type, name, iso_country, municipality,
			       latitude, longitude, elevation, iata, icao,
			       1.0 AS sim
			FROM airports
			WHERE ($1 = '' OR iata = $1)
			  AND ($2 = '' OR icao = $2)
			  AND ($3 = '' OR iso_country = $3)
			ORDER BY name ASC
			LIMIT $4
		`, iata, icao, countryCode, limit)
	} else {
		// Fuzzy name search using trigram similarity
		if countryCode != "" {
			rows, err = h.DB.Query(ctx, `
				SELECT id, ident, type, name, iso_country, municipality,
				       latitude, longitude, elevation, iata, icao,
				       similarity(name, $1) AS sim
				FROM airports
				WHERE iso_country = $2
				  AND similarity(name, $1) >= $3
				ORDER BY sim DESC
				LIMIT $4
			`, name, countryCode, threshold, limit)
		} else {
			rows, err = h.DB.Query(ctx, `
				SELECT id, ident, type, name, iso_country, municipality,
				       latitude, longitude, elevation, iata, icao,
				       similarity(name, $1) AS sim
				FROM airports
				WHERE similarity(name, $1) >= $2
				ORDER BY sim DESC
				LIMIT $3
			`, name, threshold, limit)
		}
	}

	if err != nil {
		http.Error(w, "Error searching airports", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var airports []models.Airport
	for rows.Next() {
		var airport models.Airport
		var similarity float64 // Temporary variable to hold similarity score
		err := rows.Scan(
			&airport.ID,
			&airport.Ident,
			&airport.Type,
			&airport.Name,
			&airport.Country,
			&airport.Municipality,
			&airport.Latitude,
			&airport.Longitude,
			&airport.Elevation,
			&airport.IATA,
			&airport.ICAO,
			&similarity, // Scan similarity score but don't use it
		)
		if err != nil {
			http.Error(w, "Error reading airport data", http.StatusInternalServerError)
			return
		}
		airports = append(airports, airport)
	}

	if err = rows.Err(); err != nil {
		http.Error(w, "Error processing results", http.StatusInternalServerError)
		return
	}

	render.JSON(w, r, map[string]any{
		"airports": airports,
		"count":    len(airports),
	})
}

