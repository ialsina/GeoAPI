package models

// Airport represents an airport with its geographic and identification information
type Airport struct {
	ID          int64   `json:"id" example:"6523"`                    // Unique OurAirports identifier
	Ident       string  `json:"ident" example:"00A"`                 // Airport identifier (ICAO code preferred)
	Type        string  `json:"type" example:"heliport"`             // Airport type (large_airport, medium_airport, small_airport, heliport, etc.)
	Name        string  `json:"name" example:"Total RF Heliport"`    // Official airport name
	Country     string  `json:"country" example:"US"`                // ISO 2-letter country code
	Municipality string `json:"municipality" example:"Bensalem"`    // Primary municipality served
	Latitude    float64 `json:"latitude" example:"40.070985"`        // Latitude coordinate
	Longitude   float64 `json:"longitude" example:"-74.933689"`      // Longitude coordinate
	Elevation   float64 `json:"elevation,omitempty" example:"3.35"`  // Elevation in meters
	IATA        string  `json:"iata,omitempty" example:"SFO"`        // IATA code (3-letter)
	ICAO        string  `json:"icao,omitempty" example:"KSFO"`       // ICAO code (4-letter)
}

