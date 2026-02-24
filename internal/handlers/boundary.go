package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"github.com/go-chi/render"
	"github.com/jackc/pgx/v5/pgxpool"
)

// BoundaryHandler handles boundary-related API requests.
type BoundaryHandler struct {
	DB *pgxpool.Pool
}

// typeRank returns a numeric rank for boundary type comparison.
// Higher rank = larger/broader scope: city(0) < adm2(1) < adm1(2) < adm0(3).
func typeRank(t string) int {
	switch t {
	case "city":
		return 0
	case "adm2":
		return 1
	case "adm1":
		return 2
	case "adm0":
		return 3
	default:
		return -1
	}
}

// cityRecord holds essential data for a resolved city.
type cityRecord struct {
	GeonameID int64
	Name      string
	Country   string  // ISO-2
	Lat       float64
	Lon       float64
}

// shapeNameMatch represents a boundary shape located by name.
type shapeNameMatch struct {
	Name        string
	GeoJSON     string
	Type        string  // "city", "adm0", "adm1", or "adm2"
	CentroidLat float64 // centroid latitude  (for upscale lookups)
	CentroidLon float64 // centroid longitude
}

// ── DB helpers ────────────────────────────────────────────────────────────────

// findCityByID looks up a city in cities_1000 by GeoNames ID.
func (h *BoundaryHandler) findCityByID(ctx context.Context, geonameid int64) (*cityRecord, error) {
	c := &cityRecord{}
	err := h.DB.QueryRow(ctx, `
		SELECT geonameid, name, country, ST_Y(geom), ST_X(geom)
		FROM cities_1000
		WHERE geonameid = $1
	`, geonameid).Scan(&c.GeonameID, &c.Name, &c.Country, &c.Lat, &c.Lon)
	return c, err
}

// findCityByName looks up the most-populous city matching name (or one of its
// alternate names).  iso2 is optional; when non-empty it restricts results to
// that country.
func (h *BoundaryHandler) findCityByName(ctx context.Context, name, iso2 string) (*cityRecord, error) {
	c := &cityRecord{}
	var err error
	if iso2 != "" {
		err = h.DB.QueryRow(ctx, `
			(
				SELECT geonameid, name, country, ST_Y(geom), ST_X(geom), population
				FROM cities_1000
				WHERE name = $1 AND country = $2
				ORDER BY population DESC
				LIMIT 1
			)
			UNION ALL
			(
				SELECT c.geonameid, c.name, c.country, ST_Y(c.geom), ST_X(c.geom), c.population
				FROM cities_1000_alternate_names an
				JOIN cities_1000 c ON c.geonameid = an.geonameid
				WHERE an.name = $1 AND c.country = $2
				ORDER BY c.population DESC
				LIMIT 1
			)
			ORDER BY population DESC
			LIMIT 1
		`, name, iso2).Scan(&c.GeonameID, &c.Name, &c.Country, &c.Lat, &c.Lon, new(int64))
	} else {
		err = h.DB.QueryRow(ctx, `
			(
				SELECT geonameid, name, country, ST_Y(geom), ST_X(geom), population
				FROM cities_1000
				WHERE name = $1
				ORDER BY population DESC
				LIMIT 1
			)
			UNION ALL
			(
				SELECT c.geonameid, c.name, c.country, ST_Y(c.geom), ST_X(c.geom), c.population
				FROM cities_1000_alternate_names an
				JOIN cities_1000 c ON c.geonameid = an.geonameid
				WHERE an.name = $1
				ORDER BY c.population DESC
				LIMIT 1
			)
			ORDER BY population DESC
			LIMIT 1
		`, name).Scan(&c.GeonameID, &c.Name, &c.Country, &c.Lat, &c.Lon, new(int64))
	}
	return c, err
}

// findNearestCity returns the city in cities_1000 closest to the given coordinates.
func (h *BoundaryHandler) findNearestCity(ctx context.Context, lat, lon float64) (*cityRecord, error) {
	c := &cityRecord{}
	err := h.DB.QueryRow(ctx, `
		SELECT geonameid, name, country, ST_Y(geom), ST_X(geom)
		FROM cities_1000
		ORDER BY geom <-> ST_SetSRID(ST_Point($1, $2), 4326)
		LIMIT 1
	`, lon, lat).Scan(&c.GeonameID, &c.Name, &c.Country, &c.Lat, &c.Lon)
	return c, err
}

// resolveCountryCodes resolves a country identifier (ISO-2, ISO-3, or English name)
// into its canonical (iso2, iso3) pair.
func (h *BoundaryHandler) resolveCountryCodes(ctx context.Context, country string) (iso2, iso3 string, err error) {
	err = h.DB.QueryRow(ctx, `
		SELECT iso2, COALESCE(iso3, '')
		FROM countries
		WHERE iso2 = UPPER($1)
		   OR iso3 = UPPER($1)
		   OR LOWER(name) = LOWER($1)
		LIMIT 1
	`, country).Scan(&iso2, &iso3)
	return
}

// findBoundaryByPoint returns the boundary of the given type that contains (lat, lon).
func (h *BoundaryHandler) findBoundaryByPoint(ctx context.Context, lat, lon float64, boundaryType string) (name, geojson string, err error) {
	var query string
	switch boundaryType {
	case "adm0":
		query = `SELECT shape_name, ST_AsGeoJSON(geom)
		         FROM adm0_boundaries
		         WHERE ST_Contains(geom, ST_SetSRID(ST_Point($1, $2), 4326))
		         LIMIT 1`
	case "adm1":
		query = `SELECT shape_name, ST_AsGeoJSON(geom)
		         FROM adm1_boundaries
		         WHERE ST_Contains(geom, ST_SetSRID(ST_Point($1, $2), 4326))
		         LIMIT 1`
	case "adm2":
		query = `SELECT shape_name, ST_AsGeoJSON(geom)
		         FROM adm2_boundaries
		         WHERE ST_Contains(geom, ST_SetSRID(ST_Point($1, $2), 4326))
		         LIMIT 1`
	default: // "city"
		query = `SELECT name, ST_AsGeoJSON(geom)
		         FROM city_boundaries
		         WHERE ST_Contains(geom, ST_SetSRID(ST_Point($1, $2), 4326))
		         LIMIT 1`
	}
	err = h.DB.QueryRow(ctx, query, lon, lat).Scan(&name, &geojson)
	return
}

// findBoundaryByPointAuto tries boundary types in priority order
// (city → adm0 → adm1 → adm2) and returns the first match along with its type.
func (h *BoundaryHandler) findBoundaryByPointAuto(ctx context.Context, lat, lon float64) (name, geojson, matchedType string, err error) {
	for _, t := range []string{"city", "adm0", "adm1", "adm2"} {
		name, geojson, err = h.findBoundaryByPoint(ctx, lat, lon, t)
		if err == nil {
			return name, geojson, t, nil
		}
	}
	return "", "", "", err
}

// findShapeByName searches boundary tables by case-insensitive shape name.
// Priority order: city_boundaries → adm0 → adm1 → adm2.
// If iso3 is non-empty it is used to narrow adm table lookups.
//
// NOTE: Adding GIN trigram indexes on adm*_boundaries.shape_name (as already
// done on cities_1000) would speed up name searches on large datasets.
func (h *BoundaryHandler) findShapeByName(ctx context.Context, shapeName, iso3 string) (*shapeNameMatch, error) {
	var name, geojson string
	var centLon, centLat float64
	var err error

	// 1. city_boundaries (no country column – search without filter)
	err = h.DB.QueryRow(ctx, `
		SELECT name, ST_AsGeoJSON(geom),
		       ST_X(ST_Centroid(geom)), ST_Y(ST_Centroid(geom))
		FROM city_boundaries
		WHERE LOWER(name) = LOWER($1)
		LIMIT 1
	`, shapeName).Scan(&name, &geojson, &centLon, &centLat)
	if err == nil {
		return &shapeNameMatch{
			Name: name, GeoJSON: geojson, Type: "city",
			CentroidLat: centLat, CentroidLon: centLon,
		}, nil
	}

	// 2-4. adm0, adm1, adm2 – optionally filtered by country (iso3)
	type admEntry struct{ table, typ string }
	for _, e := range []admEntry{
		{"adm0_boundaries", "adm0"},
		{"adm1_boundaries", "adm1"},
		{"adm2_boundaries", "adm2"},
	} {
		var q string
		var args []any
		if iso3 != "" {
			q = `SELECT shape_name, ST_AsGeoJSON(geom),
			            ST_X(ST_Centroid(geom)), ST_Y(ST_Centroid(geom))
			     FROM ` + e.table + `
			     WHERE LOWER(shape_name) = LOWER($1) AND country = $2
			     LIMIT 1`
			args = []any{shapeName, iso3}
		} else {
			q = `SELECT shape_name, ST_AsGeoJSON(geom),
			            ST_X(ST_Centroid(geom)), ST_Y(ST_Centroid(geom))
			     FROM ` + e.table + `
			     WHERE LOWER(shape_name) = LOWER($1)
			     LIMIT 1`
			args = []any{shapeName}
		}
		err = h.DB.QueryRow(ctx, q, args...).Scan(&name, &geojson, &centLon, &centLat)
		if err == nil {
			return &shapeNameMatch{
				Name: name, GeoJSON: geojson, Type: e.typ,
				CentroidLat: centLat, CentroidLon: centLon,
			}, nil
		}
	}
	return nil, err
}

// findCountryBoundary returns the ADM0 boundary for a country identified by ISO-3.
func (h *BoundaryHandler) findCountryBoundary(ctx context.Context, iso3 string) (name, geojson string, err error) {
	err = h.DB.QueryRow(ctx, `
		SELECT shape_name, ST_AsGeoJSON(geom)
		FROM adm0_boundaries
		WHERE country = $1
		LIMIT 1
	`, iso3).Scan(&name, &geojson)
	return
}

// rawGeo wraps a PostGIS GeoJSON string so it is embedded as a JSON object
// in the response rather than being double-encoded as a quoted string.
func rawGeo(s string) json.RawMessage { return json.RawMessage(s) }

// cityJSON builds the standard city sub-object used in responses.
func cityJSON(c *cityRecord) map[string]any {
	return map[string]any{
		"geonameid": c.GeonameID,
		"name":      c.Name,
		"country":   c.Country,
		"lat":       c.Lat,
		"lon":       c.Lon,
	}
}

// ── Handler ───────────────────────────────────────────────────────────────────

// GetBoundary godoc
// @Summary      Get an administrative boundary
// @Description  Returns a boundary (city, ADM0/country, ADM1/state, or ADM2/district) for
// @Description  a variety of input combinations.
// @Description
// @Description  **Lookup priority:** geonameid / city > name > country (standalone) > lat+lon
// @Description
// @Description  **Parameters:**
// @Description  - `geonameid` – GeoNames city ID. Locates the city then returns the boundary at its coordinates.
// @Description  - `city` – City name **or** numeric GeoNames ID. Locates the city then returns the boundary at its coordinates. Disambiguate with `country`.
// @Description  - `name` – Case-insensitive shape-name search across city boundaries, ADM0, ADM1 and ADM2 (in that priority order). Combine with `country` to narrow results. Combine with `type` to upscale (e.g. city shape → enclosing ADM1). **Downscaling is rejected** (e.g. `name=Colorado&type=city` → 400).
// @Description  - `country` – ISO 3166-1 alpha-2 / alpha-3 **or** full English name. Disambiguates `city` and `name` lookups. When used **alone** (no `name`, `city`, `geonameid`, or `lat`+`lon`) returns the ADM0 boundary for that country.
// @Description  - `lat` / `lon` – Decimal-degree coordinates. Returns the boundary containing that point.
// @Description  - `type` – Force the return type (`city`, `adm0`, `adm1`, `adm2`). When omitted the endpoint auto-resolves in priority order **city > adm0 > adm1 > adm2**.
// @Tags         boundaries
// @Accept       json
// @Produce      json
// @Param        geonameid  query  int     false  "GeoNames city ID"
// @Param        city       query  string  false  "City name or numeric GeoNames ID"
// @Param        name       query  string  false  "Boundary shape name (city boundary, ADM0, ADM1, or ADM2)"
// @Param        country    query  string  false  "ISO-2, ISO-3, or country name (disambiguates; standalone → ADM0 boundary)"
// @Param        lat        query  number  false  "Latitude"
// @Param        lon        query  number  false  "Longitude"
// @Param        type       query  string  false  "Boundary type to return: city | adm0 | adm1 | adm2 (default: auto)"
// @Success      200  {object}  map[string]interface{}  "name, type, geometry (GeoJSON object), optional city sub-object"
// @Failure      400  {string}  string  "Bad Request – invalid or conflicting parameters"
// @Failure      404  {string}  string  "Not Found – boundary or city not found"
// @Router       /boundary [get]
func (h *BoundaryHandler) GetBoundary(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	q := r.URL.Query()

	// ── Parse parameters ──────────────────────────────────────────────────────
	geonameidStr := q.Get("geonameid")
	cityParam    := q.Get("city")
	nameParam    := q.Get("name")
	countryParam := q.Get("country")
	if countryParam == "" {
		countryParam = q.Get("country_code") // legacy alias
	}
	latStr    := q.Get("lat")
	lonStr    := q.Get("lon")
	typeParam := q.Get("type")

	// ── Validate type ─────────────────────────────────────────────────────────
	if typeParam != "" &&
		typeParam != "city" && typeParam != "adm0" &&
		typeParam != "adm1" && typeParam != "adm2" {
		http.Error(w, "Invalid 'type': must be city, adm0, adm1, or adm2", http.StatusBadRequest)
		return
	}

	// ── Resolve country ───────────────────────────────────────────────────────
	// iso2 is used for cities_1000 (alpha-2); iso3 is used for adm* tables (alpha-3).
	var iso2, iso3 string
	if countryParam != "" {
		var err error
		iso2, iso3, err = h.resolveCountryCodes(ctx, countryParam)
		if err != nil {
			http.Error(w, "Country not found: "+countryParam, http.StatusNotFound)
			return
		}
	}

	// ── Inline helper: derive boundary for a city record ──────────────────────
	// If typeParam is set use it; otherwise auto-detect.
	cityBoundary := func(c *cityRecord) (bName, bGeo, bType string, err error) {
		if typeParam == "" {
			bName, bGeo, bType, err = h.findBoundaryByPointAuto(ctx, c.Lat, c.Lon)
		} else {
			bName, bGeo, err = h.findBoundaryByPoint(ctx, c.Lat, c.Lon, typeParam)
			bType = typeParam
		}
		return
	}

	// ── MODE 1: geonameid  OR  city=<numeric ID> ──────────────────────────────
	effectiveID := geonameidStr
	if effectiveID == "" && cityParam != "" {
		if _, parseErr := strconv.ParseInt(cityParam, 10, 64); parseErr == nil {
			effectiveID = cityParam
		}
	}
	if effectiveID != "" {
		geonameid, err := strconv.ParseInt(effectiveID, 10, 64)
		if err != nil {
			http.Error(w, "Invalid geonameid: must be a positive integer", http.StatusBadRequest)
			return
		}
		city, err := h.findCityByID(ctx, geonameid)
		if err != nil {
			log.Printf("boundary: city not found geonameid=%d: %v", geonameid, err)
			http.Error(w, "City not found", http.StatusNotFound)
			return
		}
		bName, bGeo, bType, err := cityBoundary(city)
		if err != nil {
			log.Printf("boundary: no boundary at (%.6f,%.6f): %v", city.Lat, city.Lon, err)
			http.Error(w, "Boundary not found for this city", http.StatusNotFound)
			return
		}
		render.JSON(w, r, map[string]any{
			"type":     bType,
			"name":     bName,
			"geometry": rawGeo(bGeo),
			"city":     cityJSON(city),
		})
		return
	}

	// ── MODE 2: city=<name>  (+ optional country) ─────────────────────────────
	if cityParam != "" {
		city, err := h.findCityByName(ctx, cityParam, iso2)
		if err != nil {
			log.Printf("boundary: city '%s' (country=%s) not found: %v", cityParam, iso2, err)
			http.Error(w, "City not found: "+cityParam, http.StatusNotFound)
			return
		}
		bName, bGeo, bType, err := cityBoundary(city)
		if err != nil {
			log.Printf("boundary: no boundary at (%.6f,%.6f): %v", city.Lat, city.Lon, err)
			http.Error(w, "Boundary not found for this city", http.StatusNotFound)
			return
		}
		render.JSON(w, r, map[string]any{
			"type":     bType,
			"name":     bName,
			"geometry": rawGeo(bGeo),
			"city":     cityJSON(city),
		})
		return
	}

	// ── MODE 3: name=<shape name>  (+ optional country, optional type) ─────────
	//
	// Searches city_boundaries → adm0 → adm1 → adm2 in priority order.
	// The resolved "natural type" is the first table that contains a matching shape.
	//
	// Type interaction:
	//   • no type given        → return the natural match as-is
	//   • type == natural type → return the natural match as-is
	//   • type rank >  natural → upscale: find the enclosing boundary of that type
	//                            using the centroid of the matched shape
	//   • type rank <  natural → downscale: rejected with 400
	if nameParam != "" {
		match, err := h.findShapeByName(ctx, nameParam, iso3)
		if err != nil {
			log.Printf("boundary: shape '%s' (iso3=%s) not found: %v", nameParam, iso3, err)
			http.Error(w, "No boundary found with name: "+nameParam, http.StatusNotFound)
			return
		}

		if typeParam != "" {
			matchRank    := typeRank(match.Type)
			requestedRank := typeRank(typeParam)
			switch {
			case requestedRank < matchRank:
				// Downscale rejected
				http.Error(w,
					"'"+nameParam+"' matched as "+match.Type+
						"; cannot downscale to requested type '"+typeParam+"'",
					http.StatusBadRequest)
				return
			case requestedRank == matchRank:
				// Same level – return the shape as found
				render.JSON(w, r, map[string]any{
					"type":     match.Type,
					"name":     match.Name,
					"geometry": rawGeo(match.GeoJSON),
				})
				return
			default:
				// Upscale – use centroid of matched shape to locate containing boundary
				bName, bGeo, upErr := h.findBoundaryByPoint(ctx, match.CentroidLat, match.CentroidLon, typeParam)
				if upErr != nil {
					log.Printf("boundary: upscale %s→%s for '%s' failed: %v",
						match.Type, typeParam, nameParam, upErr)
					http.Error(w, "No "+typeParam+" boundary found containing '"+nameParam+"'", http.StatusNotFound)
					return
				}
				render.JSON(w, r, map[string]any{
					"type":     typeParam,
					"name":     bName,
					"geometry": rawGeo(bGeo),
					"matched_as": map[string]any{
						"type": match.Type,
						"name": match.Name,
					},
				})
				return
			}
		}

		// No type requested – return natural match
		render.JSON(w, r, map[string]any{
			"type":     match.Type,
			"name":     match.Name,
			"geometry": rawGeo(match.GeoJSON),
		})
		return
	}

	// ── MODE 4: country alone → ADM0 boundary ────────────────────────────────
	//
	// Valid when no city/name/geonameid/lat+lon are given.
	// type must be "adm0" or omitted.
	if countryParam != "" && latStr == "" && lonStr == "" {
		if typeParam != "" && typeParam != "adm0" {
			http.Error(w,
				"When 'country' is the only lookup parameter, 'type' must be 'adm0' or omitted",
				http.StatusBadRequest)
			return
		}
		bName, bGeo, err := h.findCountryBoundary(ctx, iso3)
		if err != nil {
			log.Printf("boundary: no adm0 boundary for iso3=%s: %v", iso3, err)
			http.Error(w, "Country boundary not found for: "+countryParam, http.StatusNotFound)
			return
		}
		render.JSON(w, r, map[string]any{
			"type":     "adm0",
			"name":     bName,
			"geometry": rawGeo(bGeo),
		})
		return
	}

	// ── MODE 5: lat + lon  (+ optional type) ─────────────────────────────────
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

		var bName, bGeo, bType string
		if typeParam == "" {
			bName, bGeo, bType, err = h.findBoundaryByPointAuto(ctx, lat, lon)
		} else {
			bName, bGeo, err = h.findBoundaryByPoint(ctx, lat, lon, typeParam)
			bType = typeParam
		}
		if err != nil {
			http.Error(w, "Boundary not found for this location", http.StatusNotFound)
			return
		}

		resp := map[string]any{
			"type":     bType,
			"name":     bName,
			"geometry": rawGeo(bGeo),
		}
		// Enrich with nearest city
		if city, cityErr := h.findNearestCity(ctx, lat, lon); cityErr == nil {
			resp["city"] = cityJSON(city)
		} else {
			log.Printf("boundary: nearest city lookup failed for (%.6f,%.6f): %v", lat, lon, cityErr)
		}
		render.JSON(w, r, resp)
		return
	}

	// ── No valid combination provided ────────────────────────────────────────
	http.Error(w,
		"Provide one of: geonameid, city, name, country (type=adm0), or lat+lon",
		http.StatusBadRequest)
}
