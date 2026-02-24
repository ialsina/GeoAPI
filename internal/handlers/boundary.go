package handlers

import (
	"context"
	"log"
	"net/http"
	"strconv"

	"github.com/go-chi/render"
	"github.com/jackc/pgx/v5/pgxpool"
)

type BoundaryHandler struct {
	DB *pgxpool.Pool
}

// findBoundaryByPoint is a helper function that finds a boundary given lat/lon coordinates
// boundaryType can be "adm0", "adm2" or "city" (default is "city")
func (h *BoundaryHandler) findBoundaryByPoint(ctx context.Context, lat, lon float64, boundaryType string) (string, string, error) {
	var name string
	var geojson string

	// Default to "city" if not specified
	if boundaryType == "" {
		boundaryType = "city"
	}

	var query string
	if boundaryType == "adm2" {
		query = `
			SELECT shape_name, ST_AsGeoJSON(geom)
			FROM adm2_boundaries
			WHERE ST_Contains(
				geom,
				ST_SetSRID(ST_Point($1, $2), 4326)
			)
			LIMIT 1
		`
	} else if boundaryType == "adm0" {
		query = `
			SELECT shape_name, ST_AsGeoJSON(geom)
			FROM adm0_boundaries
			WHERE ST_Contains(
				geom,
				ST_SetSRID(ST_Point($1, $2), 4326)
			)
			LIMIT 1
		`
	} else {
		// Default to "city"
		query = `
			SELECT name, ST_AsGeoJSON(geom)
			FROM city_boundaries
			WHERE ST_Contains(
				geom,
				ST_SetSRID(ST_Point($1, $2), 4326)
			)
			LIMIT 1
		`
	}

	err := h.DB.QueryRow(ctx, query, lon, lat).Scan(&name, &geojson)

	if err != nil {
		return "", "", err
	}

	return name, geojson, nil
}

func (h *BoundaryHandler) ByPoint(w http.ResponseWriter, r *http.Request) {
	lat, _ := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	lon, _ := strconv.ParseFloat(r.URL.Query().Get("lon"), 64)
	boundaryType := r.URL.Query().Get("type")
	if boundaryType == "" {
		boundaryType = "city"
	}

	name, geojson, err := h.findBoundaryByPoint(r.Context(), lat, lon, boundaryType)
	if err != nil {
		http.Error(w, "Boundary not found", http.StatusNotFound)
		return
	}

	render.JSON(w, r, map[string]any{
		"name":     name,
		"geometry": geojson,
	})
}

// ByCity finds a boundary given a city name and country code
// It looks up the city's coordinates and then finds the boundary containing that point
func (h *BoundaryHandler) ByCity(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	// r.URL.Query().Get() already decodes URL-encoded parameters automatically
	name := r.URL.Query().Get("name")
	country := r.URL.Query().Get("country")

	if name == "" || country == "" {
		http.Error(w, "Both 'name' and 'country' query parameters are required", http.StatusBadRequest)
		return
	}

	// First, find the city to get its coordinates
	var lat, lon float64
	err := h.DB.QueryRow(ctx, `
		SELECT ST_Y(geom), ST_X(geom)
		FROM cities_1000
		WHERE name = $1 AND country_code = $2
		ORDER BY population DESC
		LIMIT 1
	`, name, country).Scan(&lat, &lon)

	if err != nil {
		log.Printf("Error finding city '%s' in country '%s': %v", name, country, err)
		http.Error(w, "City not found", http.StatusNotFound)
		return
	}

	// Then, find the boundary using the city's coordinates
	boundaryType := r.URL.Query().Get("type")
	if boundaryType == "" {
		boundaryType = "city"
	}
	boundaryName, geojson, err := h.findBoundaryByPoint(ctx, lat, lon, boundaryType)
	if err != nil {
		log.Printf("Error finding boundary for point (%.6f, %.6f): %v", lat, lon, err)
		http.Error(w, "Boundary not found for this location", http.StatusNotFound)
		return
	}

	render.JSON(w, r, map[string]any{
		"name":     boundaryName,
		"geometry": geojson,
		"city": map[string]any{
			"name":    name,
			"country": country,
			"lat":     lat,
			"lon":     lon,
		},
	})
}

// GetBoundary godoc
// @Summary      Get administrative boundary
// @Description  Get an administrative boundary (ADM0, ADM2 or city) by geonameid, by city name and country code, or by coordinates. Returns the boundary name and GeoJSON geometry. If multiple parameter groups are provided, precedence is: geonameid > name+country_code > lat+lon.
// @Tags         boundaries
// @Accept       json
// @Produce      json
// @Param        geonameid    query     int     false  "Geoname ID of the city (highest priority)"
// @Param        name         query     string  false  "City name (required with country_code for city-based lookup)"
// @Param        country_code query     string  false  "Country code (ISO 2-letter, required with name for city-based lookup)"
// @Param        lat          query     number  false  "Latitude (required with lon for point-based lookup)"
// @Param        lon          query     number  false  "Longitude (required with lat for point-based lookup)"
// @Param        type         query     string  false  "Boundary type: 'adm0', 'adm2' or 'city' (default: 'city')"
// @Success      200          {object}  map[string]interface{}  "Response with boundary name and GeoJSON geometry"
// @Failure      400          {string}  string  "Bad Request - Invalid or missing parameters"
// @Failure      404          {string}  string  "Not Found - Boundary or city not found"
// @Router       /boundary [get]
func (h *BoundaryHandler) GetBoundary(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	query := r.URL.Query()

	geonameidStr := query.Get("geonameid")
	name := query.Get("name")
	countryCode := query.Get("country_code")
	latStr := query.Get("lat")
	lonStr := query.Get("lon")
	boundaryType := query.Get("type")
	if boundaryType == "" {
		boundaryType = "city"
	}
	// Validate boundary type
	if boundaryType != "adm0" && boundaryType != "adm2" && boundaryType != "city" {
		http.Error(w, "Invalid 'type' parameter. Must be 'adm0', 'adm2' or 'city'", http.StatusBadRequest)
		return
	}

	// Priority 1: Check if geonameid-based lookup is requested
	if geonameidStr != "" {
		geonameid, err := strconv.ParseInt(geonameidStr, 10, 64)
		if err != nil {
			http.Error(w, "Invalid 'geonameid' parameter", http.StatusBadRequest)
			return
		}

		// First, find the city by geonameid to get its full information
		var cityName string
		var countryCode string
		var lat, lon float64
		err = h.DB.QueryRow(ctx, `
			SELECT name, country_code, ST_Y(geom), ST_X(geom)
			FROM cities_1000
			WHERE geonameid = $1
		`, geonameid).Scan(&cityName, &countryCode, &lat, &lon)

		if err != nil {
			log.Printf("Error finding city with geonameid '%d': %v", geonameid, err)
			http.Error(w, "City not found", http.StatusNotFound)
			return
		}

		// Then, find the boundary using the city's coordinates
		boundaryName, geojson, err := h.findBoundaryByPoint(ctx, lat, lon, boundaryType)
		if err != nil {
			log.Printf("Error finding boundary for point (%.6f, %.6f): %v", lat, lon, err)
			http.Error(w, "Boundary not found for this location", http.StatusNotFound)
			return
		}

		render.JSON(w, r, map[string]any{
			"name":     boundaryName,
			"geometry": geojson,
			"city": map[string]any{
				"geonameid":   geonameid,
				"name":        cityName,
				"country_code": countryCode,
				"lat":         lat,
				"lon":         lon,
			},
		})
		return
	}

	// Priority 2: Check if name+country_code-based lookup is requested
	if name != "" && countryCode != "" {
		// First, find the city to get its full information
		var geonameid int64
		var lat, lon float64
		err := h.DB.QueryRow(ctx, `
			SELECT geonameid, ST_Y(geom), ST_X(geom)
			FROM cities_1000
			WHERE name = $1 AND country_code = $2
			ORDER BY population DESC
			LIMIT 1
		`, name, countryCode).Scan(&geonameid, &lat, &lon)

		if err != nil {
			log.Printf("Error finding city '%s' in country '%s': %v", name, countryCode, err)
			http.Error(w, "City not found", http.StatusNotFound)
			return
		}

		// Then, find the boundary using the city's coordinates
		boundaryName, geojson, err := h.findBoundaryByPoint(ctx, lat, lon, boundaryType)
		if err != nil {
			log.Printf("Error finding boundary for point (%.6f, %.6f): %v", lat, lon, err)
			http.Error(w, "Boundary not found for this location", http.StatusNotFound)
			return
		}

		render.JSON(w, r, map[string]any{
			"name":     boundaryName,
			"geometry": geojson,
			"city": map[string]any{
				"geonameid":   geonameid,
				"name":        name,
				"country_code": countryCode,
				"lat":         lat,
				"lon":         lon,
			},
		})
		return
	}

	// Priority 3: Check if point-based lookup is requested
	if latStr != "" && lonStr != "" {
		lat, err := strconv.ParseFloat(latStr, 64)
		if err != nil {
			http.Error(w, "Invalid 'lat' parameter", http.StatusBadRequest)
			return
		}

		lon, err := strconv.ParseFloat(lonStr, 64)
		if err != nil {
			http.Error(w, "Invalid 'lon' parameter", http.StatusBadRequest)
			return
		}

		// Find the boundary using the coordinates
		boundaryName, geojson, err := h.findBoundaryByPoint(ctx, lat, lon, boundaryType)
		if err != nil {
			http.Error(w, "Boundary not found", http.StatusNotFound)
			return
		}

		// Find the nearest city to the given coordinates
		var geonameid int64
		var cityName string
		var countryCode string
		var cityLat, cityLon float64
		err = h.DB.QueryRow(ctx, `
			SELECT geonameid, name, country_code, ST_Y(geom), ST_X(geom)
			FROM cities_1000
			ORDER BY geom <-> ST_SetSRID(ST_Point($1, $2), 4326)
			LIMIT 1
		`, lon, lat).Scan(&geonameid, &cityName, &countryCode, &cityLat, &cityLon)

		if err != nil {
			log.Printf("Error finding nearest city for point (%.6f, %.6f): %v", lat, lon, err)
			// Still return the boundary even if city lookup fails
			render.JSON(w, r, map[string]any{
				"name":     boundaryName,
				"geometry": geojson,
			})
			return
		}

		render.JSON(w, r, map[string]any{
			"name":     boundaryName,
			"geometry": geojson,
			"city": map[string]any{
				"geonameid":   geonameid,
				"name":        cityName,
				"country_code": countryCode,
				"lat":         cityLat,
				"lon":         cityLon,
			},
		})
		return
	}

	// No valid parameter group is provided
	http.Error(w, "Either 'geonameid', 'name' and 'country_code', or 'lat' and 'lon' parameters are required", http.StatusBadRequest)
}
