package models

// Country represents a country with key metadata from the country-codes dataset
type Country struct {
	ISO2      string  `json:"iso2" example:"US"`              // ISO 3166-1 alpha-2 code
	ISO3      *string `json:"iso3,omitempty" example:"USA"`   // ISO 3166-1 alpha-3 code
	Name      string  `json:"name" example:"United States"`   // Official English short name
	M49Code   *int    `json:"m49_code,omitempty" example:"840"` // Numeric M49 / ISO 3166-1 code
	Region    *string `json:"region,omitempty" example:"Americas"`
	SubRegion *string `json:"sub_region,omitempty" example:"Northern America"`
	Capital   *string `json:"capital,omitempty" example:"Washington, D.C."`
	TLD       *string `json:"tld,omitempty" example:".us"`
	Continent *string `json:"continent,omitempty" example:"NA"`
}
