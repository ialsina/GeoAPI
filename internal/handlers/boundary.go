package handlers

import (
	"context"
	"net/http"
	"strconv"

	"github.com/go-chi/render"
	"github.com/jackc/pgx/v5/pgxpool"
)

type BoundaryHandler struct {
	DB *pgxpool.Pool
}

// findBoundaryByPoint is a helper function that finds a boundary given lat/lon coordinates
func (h *BoundaryHandler) findBoundaryByPoint(ctx context.Context, lat, lon float64) (string, string, error) {
	var name string
	var geojson string

	err := h.DB.QueryRow(ctx, `
		SELECT shape_name, ST_AsGeoJSON(geom)
		FROM adm2_boundaries
		WHERE ST_Contains(
			geom,
			ST_SetSRID(ST_Point($1, $2), 4326)
		)
		LIMIT 1
	`, lon, lat).Scan(&name, &geojson)

	if err != nil {
		return "", "", err
	}

	return name, geojson, nil
}

func (h *BoundaryHandler) ByPoint(w http.ResponseWriter, r *http.Request) {
	lat, _ := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	lon, _ := strconv.ParseFloat(r.URL.Query().Get("lon"), 64)

	name, geojson, err := h.findBoundaryByPoint(r.Context(), lat, lon)
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
		http.Error(w, "City not found", http.StatusNotFound)
		return
	}

	// Then, find the boundary using the city's coordinates
	boundaryName, geojson, err := h.findBoundaryByPoint(ctx, lat, lon)
	if err != nil {
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

