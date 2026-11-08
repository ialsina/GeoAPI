package handlers

import (
	"database/sql"

	"github.com/jackc/pgx/v5"

	"city-api/internal/models"
)

type airportNullScalars struct {
	ident, typ, name, country, municipality, iata, icao sql.NullString
	elevation                                             sql.NullFloat64
}

func (n *airportNullScalars) scanDests(a *models.Airport) []any {
	return []any{
		&a.ID,
		&n.ident,
		&n.typ,
		&n.name,
		&n.country,
		&n.municipality,
		&a.Latitude,
		&a.Longitude,
		&n.elevation,
		&n.iata,
		&n.icao,
	}
}

func (n *airportNullScalars) apply(a *models.Airport) {
	a.Ident = n.ident.String
	a.Type = n.typ.String
	a.Name = n.name.String
	a.Country = n.country.String
	a.Municipality = n.municipality.String
	a.IATA = n.iata.String
	a.ICAO = n.icao.String
	if n.elevation.Valid {
		a.Elevation = n.elevation.Float64
	}
}

func scanAirportFromRow(row pgx.Row, extra ...any) (models.Airport, error) {
	var a models.Airport
	var n airportNullScalars
	dests := append(n.scanDests(&a), extra...)
	if err := row.Scan(dests...); err != nil {
		return models.Airport{}, err
	}
	n.apply(&a)
	return a, nil
}

func scanAirportFromRows(rows pgx.Rows, extra ...any) (models.Airport, error) {
	var a models.Airport
	var n airportNullScalars
	dests := append(n.scanDests(&a), extra...)
	if err := rows.Scan(dests...); err != nil {
		return models.Airport{}, err
	}
	n.apply(&a)
	return a, nil
}
