package models

// City represents a city with its geographic and demographic information
type City struct {
	GeonameID   int64   `json:"geonameid" example:"5391959"`   // Unique GeoNames identifier
	Name        string  `json:"name" example:"San Francisco"`   // Official city name
	AsciiName   string  `json:"asciiname" example:"San Francisco"` // ASCII version of the name
	Country     string  `json:"country" example:"US"`           // ISO 2-letter country code
	Population  int64   `json:"population" example:"873965"`   // City population
	Latitude    float64 `json:"latitude" example:"37.7749"`    // Latitude coordinate
	Longitude   float64 `json:"longitude" example:"-122.4194"` // Longitude coordinate
}

