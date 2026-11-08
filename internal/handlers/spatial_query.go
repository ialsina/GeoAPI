package handlers

import (
	"fmt"
	"net/http"
	"net/url"
	"strconv"
)

const (
	maxNearbyRadiusM    = 500_000
	maxBBoxSpanDegrees  = 10
	defaultNearbyLimit  = 50
	maxNearbyLimit      = 200
)

type spatialMode int

const (
	spatialModeBBox spatialMode = iota
	spatialModeRadius
)

// SpatialQuery describes a bbox or center+radius spatial filter shared by nearby endpoints.
type SpatialQuery struct {
	Mode spatialMode

	MinLat float64
	MinLon float64
	MaxLat float64
	MaxLon float64

	Lat    float64
	Lon    float64
	Radius float64 // metres (radius mode only)

	// AnchorLat, AnchorLon are used for distance ordering (radius: center; bbox: centroid).
	AnchorLat float64
	AnchorLon float64

	Country string // ISO-2, optional
	Limit   int
}

func parseLimitQuery(query url.Values) (int, error) {
	limitStr := query.Get("limit")
	if limitStr == "" {
		return defaultNearbyLimit, nil
	}
	parsed, err := strconv.Atoi(limitStr)
	if err != nil || parsed < 1 {
		return 0, fmt.Errorf("Invalid 'limit' parameter (must be a positive integer)")
	}
	if parsed > maxNearbyLimit {
		parsed = maxNearbyLimit
	}
	return parsed, nil
}

func parseCountryQuery(query url.Values) string {
	country := query.Get("country")
	if country == "" {
		country = query.Get("country_code")
	}
	return country
}

func parseFloatParam(query url.Values, name string) (float64, bool, error) {
	s := query.Get(name)
	if s == "" {
		return 0, false, nil
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, true, fmt.Errorf("Invalid '%s' parameter", name)
	}
	return v, true, nil
}

func validateLatLon(lat, lon float64) error {
	if lat < -90 || lat > 90 {
		return fmt.Errorf("Latitude must be between -90 and 90")
	}
	if lon < -180 || lon > 180 {
		return fmt.Errorf("Longitude must be between -180 and 180")
	}
	return nil
}

// parseSpatialQuery parses bbox or radius parameters from the request query string.
func parseSpatialQuery(r *http.Request) (SpatialQuery, error) {
	q := r.URL.Query()

	limit, err := parseLimitQuery(q)
	if err != nil {
		return SpatialQuery{}, err
	}

	sq := SpatialQuery{
		Country: parseCountryQuery(q),
		Limit:   limit,
	}

	minLat, hasMinLat, err := parseFloatParam(q, "min_lat")
	if err != nil {
		return SpatialQuery{}, err
	}
	minLon, hasMinLon, err := parseFloatParam(q, "min_lon")
	if err != nil {
		return SpatialQuery{}, err
	}
	maxLat, hasMaxLat, err := parseFloatParam(q, "max_lat")
	if err != nil {
		return SpatialQuery{}, err
	}
	maxLon, hasMaxLon, err := parseFloatParam(q, "max_lon")
	if err != nil {
		return SpatialQuery{}, err
	}

	lat, hasLat, err := parseFloatParam(q, "lat")
	if err != nil {
		return SpatialQuery{}, err
	}
	lon, hasLon, err := parseFloatParam(q, "lon")
	if err != nil {
		return SpatialQuery{}, err
	}
	radius, hasRadius, err := parseFloatParam(q, "radius")
	if err != nil {
		return SpatialQuery{}, err
	}

	bboxCount := boolCount(hasMinLat, hasMinLon, hasMaxLat, hasMaxLon)
	radiusCount := boolCount(hasLat, hasLon, hasRadius)

	if bboxCount > 0 && radiusCount > 0 {
		return SpatialQuery{}, fmt.Errorf("Use either a bounding box (min_lat, min_lon, max_lat, max_lon) or center+radius (lat, lon, radius), not both")
	}
	if bboxCount == 0 && radiusCount == 0 {
		return SpatialQuery{}, fmt.Errorf("Either bounding box (min_lat, min_lon, max_lat, max_lon) or center+radius (lat, lon, radius) parameters are required")
	}

	if bboxCount > 0 {
		if bboxCount != 4 {
			return SpatialQuery{}, fmt.Errorf("Bounding box requires all of: min_lat, min_lon, max_lat, max_lon")
		}
		if minLat >= maxLat {
			return SpatialQuery{}, fmt.Errorf("min_lat must be less than max_lat")
		}
		if minLon >= maxLon {
			return SpatialQuery{}, fmt.Errorf("min_lon must be less than max_lon")
		}
		if err := validateLatLon(minLat, minLon); err != nil {
			return SpatialQuery{}, err
		}
		if err := validateLatLon(maxLat, maxLon); err != nil {
			return SpatialQuery{}, err
		}
		if maxLat-minLat > maxBBoxSpanDegrees {
			return SpatialQuery{}, fmt.Errorf("Bounding box latitude span must not exceed %g degrees", maxBBoxSpanDegrees)
		}
		if maxLon-minLon > maxBBoxSpanDegrees {
			return SpatialQuery{}, fmt.Errorf("Bounding box longitude span must not exceed %g degrees", maxBBoxSpanDegrees)
		}
		sq.Mode = spatialModeBBox
		sq.MinLat, sq.MinLon, sq.MaxLat, sq.MaxLon = minLat, minLon, maxLat, maxLon
		sq.AnchorLat = (minLat + maxLat) / 2
		sq.AnchorLon = (minLon + maxLon) / 2
		return sq, nil
	}

	if radiusCount != 3 {
		return SpatialQuery{}, fmt.Errorf("Center+radius requires all of: lat, lon, radius")
	}
	if err := validateLatLon(lat, lon); err != nil {
		return SpatialQuery{}, err
	}
	if radius <= 0 {
		return SpatialQuery{}, fmt.Errorf("'radius' must be a positive number (metres)")
	}
	if radius > maxNearbyRadiusM {
		return SpatialQuery{}, fmt.Errorf("'radius' must not exceed %g metres", maxNearbyRadiusM)
	}
	sq.Mode = spatialModeRadius
	sq.Lat, sq.Lon, sq.Radius = lat, lon, radius
	sq.AnchorLat, sq.AnchorLon = lat, lon
	return sq, nil
}

func boolCount(flags ...bool) int {
	n := 0
	for _, f := range flags {
		if f {
			n++
		}
	}
	return n
}
