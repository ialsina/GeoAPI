package models

type City struct {
	GeonameID   int64   `json:"geonameid"`
	Name        string  `json:"name"`
	AsciiName   string  `json:"asciiname"`
	Country     string  `json:"country"`
	Population  int64   `json:"population"`
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
}

