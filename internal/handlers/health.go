package handlers

import (
	"context"
	"net/http"

	"github.com/go-chi/render"
	"github.com/jackc/pgx/v5/pgxpool"
)

type HealthHandler struct {
	DB *pgxpool.Pool
}

// Health godoc
// @Summary      Health check endpoint
// @Description  Returns the health status of the API and database connection
// @Tags         health
// @Accept       json
// @Produce      json
// @Success      200  {object}  map[string]string  "Service is healthy"
// @Failure      503  {object}  map[string]string  "Service is unhealthy"
// @Router       /health [get]
func (h *HealthHandler) Health(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	// Check database connection
	err := h.DB.Ping(ctx)
	if err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		render.JSON(w, r, map[string]string{
			"status": "unhealthy",
			"error":  "Database connection failed",
		})
		return
	}

	render.JSON(w, r, map[string]string{
		"status": "healthy",
	})
}

