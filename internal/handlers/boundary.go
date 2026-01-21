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

func (h *BoundaryHandler) ByPoint(w http.ResponseWriter, r *http.Request) {
	lat, _ := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	lon, _ := strconv.ParseFloat(r.URL.Query().Get("lon"), 64)

	var name string
	var geojson string

	err := h.DB.QueryRow(context.Background(), `
		SELECT shape_name, ST_AsGeoJSON(geom)
		FROM adm2_boundaries
		WHERE ST_Contains(
			geom,
			ST_SetSRID(ST_Point($1, $2), 4326)
		)
		LIMIT 1
	`, lon, lat).Scan(&name, &geojson)

	if err != nil {
		http.Error(w, "Boundary not found", http.StatusNotFound)
		return
	}

	render.JSON(w, r, map[string]any{
		"name": name,
		"geometry": geojson,
	})
}

