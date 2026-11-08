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
// @Description  Retrieve a single city by geonameid, or by name (optionally with country)
// @Tags         cities
// @Accept       json
// @Produce      json
// @Param        geonameid   query     int     false  "Geoname ID of the city"
// @Param        name        query     string  false  "Name of the city"
// @Param        country      query    string  false  "Country code (ISO 2-letter), required if searching by name"
// @Success      200         {object}  models.City
// @Failure      400         {string}  string  "Bad Request - Invalid parameters"
// @Failure      404         {string}  string  "Not Found - City not found"
// @Router       /city [get]
func (h *CityHandler) GetCity(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	geonameid := r.URL.Query().Get("geonameid")
	name := r.URL.Query().Get("name")
	countryCode := r.URL.Query().Get("country")
	if countryCode == "" {
		// Legacy param name for backward compatibility
		countryCode = r.URL.Query().Get("country_code")
	}

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
			SELECT geonameid, name, asciiname, country, population,
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
			// Search by name (or alternate name) and country_code
			err = h.DB.QueryRow(ctx, `
				(
					SELECT geonameid, name, asciiname, country, population,
					       ST_Y(geom), ST_X(geom)
					FROM cities_1000
					WHERE name = $1 AND country = $2
					ORDER BY population DESC
					LIMIT 1
				)
				UNION ALL
				(
					SELECT c.geonameid, c.name, c.asciiname, c.country, c.population,
					       ST_Y(c.geom), ST_X(c.geom)
					FROM cities_1000_alternate_names an
					JOIN cities_1000 c ON c.geonameid = an.geonameid
					WHERE an.name = $1 AND c.country = $2
					ORDER BY c.population DESC
					LIMIT 1
				)
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
			// Search by name (or alternate name) only
			err = h.DB.QueryRow(ctx, `
				(
					SELECT geonameid, name, asciiname, country, population,
					       ST_Y(geom), ST_X(geom)
					FROM cities_1000
					WHERE name = $1
					ORDER BY population DESC
					LIMIT 1
				)
				UNION ALL
				(
					SELECT c.geonameid, c.name, c.asciiname, c.country, c.population,
					       ST_Y(c.geom), ST_X(c.geom)
					FROM cities_1000_alternate_names an
					JOIN cities_1000 c ON c.geonameid = an.geonameid
					WHERE an.name = $1
					ORDER BY c.population DESC
					LIMIT 1
				)
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

	if err = h.loadCityDetails(ctx, &city); err != nil {
		http.Error(w, "Error retrieving city details", http.StatusInternalServerError)
		return
	}

	render.JSON(w, r, city)
}

func (h *CityHandler) loadCityDetails(ctx context.Context, city *models.City) error {
	return h.DB.QueryRow(ctx, `
		SELECT c.elevation,
		       COALESCE(
		           array_agg(an.name ORDER BY an.name)
		               FILTER (WHERE an.name IS NOT NULL),
		           '{}'::text[]
		       )
		FROM cities_1000 c
		LEFT JOIN cities_1000_alternate_names an
		       ON an.geonameid = c.geonameid
		WHERE c.geonameid = $1
		GROUP BY c.geonameid, c.elevation
	`, city.GeonameID).Scan(&city.Elevation, &city.AlternateNames)
}

// SearchCities godoc
// @Summary      Search cities by name
// @Description  Search for cities by name using fuzzy matching (trigram similarity). Returns a list of matching cities ordered by similarity and population.
// @Tags         cities
// @Accept       json
// @Produce      json
// @Param        name          query     string  true   "City name to search for (fuzzy match)"
// @Param        country       query     string  false  "Filter by country code (ISO 2-letter)"
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

	countryCode := query.Get("country")
	if countryCode == "" {
		// Legacy param name for backward compatibility
		countryCode = query.Get("country_code")
	}
	thresholdStr := query.Get("threshold")

	limit, err := parseLimitQuery(query)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
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

	// Build query using fuzzy matching with trigram similarity.
	// Searches name, asciiname, and alternate names.  Results are deduplicated
	// by geonameid (keeping the highest similarity score per city), then
	// ordered by similarity descending, population descending.
	if countryCode != "" {
		rows, err = h.DB.Query(ctx, `
			SELECT geonameid, name, asciiname, country, population,
			       lat, lon, best_sim
			FROM (
				SELECT DISTINCT ON (geonameid)
				       geonameid, name, asciiname, country, population,
				       lat, lon, best_sim
				FROM (
					SELECT geonameid, name, asciiname, country, population,
					       ST_Y(geom) AS lat, ST_X(geom) AS lon,
					       GREATEST(
					           similarity(name, $1),
					           similarity(asciiname, $1)
					       ) AS best_sim
					FROM cities_1000
					WHERE country = $2
					  AND (
					       similarity(name, $1) >= $3
					    OR similarity(asciiname, $1) >= $3
					  )
					UNION ALL
					SELECT c.geonameid, c.name, c.asciiname, c.country, c.population,
					       ST_Y(c.geom) AS lat, ST_X(c.geom) AS lon,
					       similarity(an.name, $1) AS best_sim
					FROM cities_1000_alternate_names an
					JOIN cities_1000 c ON c.geonameid = an.geonameid
					WHERE c.country = $2
					  AND similarity(an.name, $1) >= $3
				) sub
				ORDER BY geonameid, best_sim DESC
			) deduped
			ORDER BY best_sim DESC, population DESC
			LIMIT $4
		`, name, countryCode, threshold, limit)
	} else {
		rows, err = h.DB.Query(ctx, `
			SELECT geonameid, name, asciiname, country, population,
			       lat, lon, best_sim
			FROM (
				SELECT DISTINCT ON (geonameid)
				       geonameid, name, asciiname, country, population,
				       lat, lon, best_sim
				FROM (
					SELECT geonameid, name, asciiname, country, population,
					       ST_Y(geom) AS lat, ST_X(geom) AS lon,
					       GREATEST(
					           similarity(name, $1),
					           similarity(asciiname, $1)
					       ) AS best_sim
					FROM cities_1000
					WHERE similarity(name, $1) >= $2
					   OR similarity(asciiname, $1) >= $2
					UNION ALL
					SELECT c.geonameid, c.name, c.asciiname, c.country, c.population,
					       ST_Y(c.geom) AS lat, ST_X(c.geom) AS lon,
					       similarity(an.name, $1) AS best_sim
					FROM cities_1000_alternate_names an
					JOIN cities_1000 c ON c.geonameid = an.geonameid
					WHERE similarity(an.name, $1) >= $2
				) sub
				ORDER BY geonameid, best_sim DESC
			) deduped
			ORDER BY best_sim DESC, population DESC
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

// NearbyCities godoc
// @Summary      List cities in a region by population
// @Description  Return cities within a bounding box or radius, ordered by population (descending)
// @Tags         cities
// @Accept       json
// @Produce      json
// @Param        min_lat   query     number  false  "Bounding box minimum latitude"
// @Param        min_lon   query     number  false  "Bounding box minimum longitude"
// @Param        max_lat   query     number  false  "Bounding box maximum latitude"
// @Param        max_lon   query     number  false  "Bounding box maximum longitude"
// @Param        lat       query     number  false  "Center latitude (with lon, radius)"
// @Param        lon       query     number  false  "Center longitude (with lat, radius)"
// @Param        radius    query     number  false  "Search radius in metres (with lat, lon)"
// @Param        country   query     string  false  "Filter by country code (ISO 2-letter)"
// @Param        limit     query     int     false  "Maximum number of results (default: 50, max: 200)"
// @Success      200       {object}  map[string]interface{}  "Response with cities array and count"
// @Failure      400       {string}  string  "Bad Request - Invalid parameters"
// @Failure      500       {string}  string  "Internal Server Error"
// @Router       /cities/nearby [get]
func (h *CityHandler) NearbyCities(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	sq, err := parseSpatialQuery(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var rows pgx.Rows
	if sq.Mode == spatialModeBBox {
		rows, err = h.DB.Query(ctx, `
			SELECT geonameid, name, asciiname, country, population,
			       ST_Y(geom) AS lat, ST_X(geom) AS lon
			FROM cities_1000
			WHERE geom && ST_MakeEnvelope($1, $2, $3, $4, 4326)
			  AND ST_Within(geom, ST_MakeEnvelope($1, $2, $3, $4, 4326))
			  AND ($5 = '' OR country = $5)
			ORDER BY population DESC
			LIMIT $6
		`, sq.MinLon, sq.MinLat, sq.MaxLon, sq.MaxLat, sq.Country, sq.Limit)
	} else {
		rows, err = h.DB.Query(ctx, `
			SELECT geonameid, name, asciiname, country, population,
			       ST_Y(geom) AS lat, ST_X(geom) AS lon
			FROM cities_1000
			WHERE ST_DWithin(
			          geom::geography,
			          ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
			          $3
			      )
			  AND ($4 = '' OR country = $4)
			ORDER BY population DESC
			LIMIT $5
		`, sq.Lon, sq.Lat, sq.Radius, sq.Country, sq.Limit)
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
