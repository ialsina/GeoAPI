# API usage

GeoAPI exposes unauthenticated, read-only HTTP GET endpoints. The server listens
on port 8080 and does not currently use an API version prefix.

For the complete generated parameter and response reference, open the Swagger
UI at <http://localhost:8080/docs/> while the service is running.

## Endpoint index

| Endpoint | Purpose | Main query parameters |
| --- | --- | --- |
| `GET /health` | Check the API and database connection | none |
| `GET /city` | Retrieve one city | `geonameid`, or `name` with optional `country` |
| `GET /cities` | Fuzzy-search cities | `name`, optional `country`, `limit`, `threshold` |
| `GET /cities/nearby` | Cities in a region by population | bbox (`min_lat`, `min_lon`, `max_lat`, `max_lon`) **or** `lat`, `lon`, `radius` (metres); optional `country`, `limit` |
| `GET /airport` | Retrieve one airport | `id`, `ident`, `iata`, `icao`, or `name`; optional `country` |
| `GET /airports` | Search airport names or exact codes | `name`, `iata`, or `icao`; optional `country`, `limit`, `threshold` |
| `GET /airports/nearby` | Airports in a region by distance | same spatial params as `GET /cities/nearby`; optional `country`, `limit` |
| `GET /boundary` | Retrieve a city or administrative boundary | `geonameid`, `city`, `name`, `country`, or `lat` and `lon`; optional `type` |
| `GET /country` | Retrieve one country | `iso2` or `iso3` |
| `GET /countries` | List countries | optional `limit` and `offset` |

`country` is an ISO alpha-2 code for city and airport endpoints. The boundary
endpoint additionally accepts an ISO alpha-3 code or a case-insensitive English
country name.

## Examples

```bash
# Exact city lookup and fuzzy city search
curl "http://localhost:8080/city?geonameid=2988507"
curl "http://localhost:8080/cities?name=Pariss&country=FR&limit=10"

# Exact airport code and fuzzy airport name search
curl "http://localhost:8080/airport?iata=SFO"
curl "http://localhost:8080/airports?name=Heathrow&country=GB"

# Country lookup and paginated listing
curl "http://localhost:8080/country?iso3=FRA"
curl "http://localhost:8080/countries?limit=50&offset=0"
```

City and airport search `limit` defaults to 50 and is capped at 200.
`threshold` defaults to 0.2 and accepts values from 0.0 through 1.0. Country
listing defaults to 250 rows and is capped at 500.

## Nearby spatial search

`GET /cities/nearby` and `GET /airports/nearby` accept **either** a bounding box
**or** a center point with radius. Do not combine both modes in one request.

| Mode | Parameters | Notes |
| --- | --- | --- |
| Bounding box | `min_lat`, `min_lon`, `max_lat`, `max_lon` | Requires `min_lat` &lt; `max_lat` and `min_lon` &lt; `max_lon`. Each axis span is limited to 10°. Dateline-crossing boxes are not supported. |
| Center + radius | `lat`, `lon`, `radius` | `radius` is in **metres**, must be positive, and is capped at 500 km. |

Optional `country` (ISO alpha-2, or legacy `country_code`) filters results to one
country. `limit` defaults to 50 and is capped at 200.

- **Cities** are ordered by `population` descending.
- **Airports** are ordered by distance to the query anchor ascending. For a
  bounding box, the anchor is the box centroid; each airport includes
  `distance_m` (metres). All OurAirports types are included.

```bash
# Top cities by population in a box (Bay Area-ish)
curl "http://localhost:8080/cities/nearby?min_lat=37.0&min_lon=-123&max_lat=38.5&max_lon=-121.5&limit=20"

# Top cities within 50 km of Paris
curl "http://localhost:8080/cities/nearby?lat=48.8566&lon=2.3522&radius=50000&limit=20"

# Airports near SFO
curl "http://localhost:8080/airports/nearby?lat=37.6213&lon=-122.3790&radius=80000&limit=10"
```

## Boundary resolution

`GET /boundary` supports `city`, `adm2`, `adm1`, and `adm0` boundary types,
ordered here from narrowest to broadest. Lookup modes are evaluated in this
order:

1. `geonameid`, or a numeric `city`, resolves a GeoNames city.
2. A non-numeric `city` resolves the most populous city with that name; add
   `country` to disambiguate it.
3. `name` searches boundary shape names, case-insensitively, in this order:
   city, ADM0, ADM1, ADM2.
4. `country` by itself returns its ADM0 boundary.
5. `lat` and `lon` find a boundary containing the point.

When `type` is omitted for a city or coordinate lookup, containment is tried in
the current implementation order: city, ADM0, ADM1, ADM2. Specify `type` when a
particular administrative level is required.

For a `name` lookup, the natural matching boundary is returned by default. A
broader requested `type` upscales by finding the requested boundary around the
matched shape's centroid. A narrower requested type is rejected because there
is no unambiguous way to select one child boundary.

```bash
# Resolve a city, then return the ADM1 boundary containing it
curl "http://localhost:8080/boundary?city=Paris&country=FR&type=adm1"

# Find a named shape at its natural level
curl "http://localhost:8080/boundary?name=Colorado&country=US"

# Country boundary; country accepts alpha-2, alpha-3, or English name
curl "http://localhost:8080/boundary?country=France"

# Find an ADM2 boundary containing coordinates
curl "http://localhost:8080/boundary?lat=48.8566&lon=2.3522&type=adm2"
```

Boundary responses contain `type`, `name`, and a GeoJSON `geometry` object.
City-based lookups include the resolved city. Coordinate lookups include the
nearest city when that secondary query succeeds. Upscaled shape-name responses
include `matched_as`.

## Compatibility aliases

The handlers retain these legacy query parameter aliases:

- `country_code` for `country` on city, airport, and boundary endpoints;
- `iata_code` for `iata` on `GET /airports`;
- `icao_code` for `icao` on `GET /airports`.

Prefer the current names in new integrations.

## Status and errors

Successful data endpoints return JSON. Validation and lookup failures generally
use plain-text bodies with HTTP `400`, `404`, or `500` statuses.

`GET /health` returns `200` and `{"status":"healthy"}` when the database ping
succeeds. It returns `503` with a JSON error when the database is unavailable.
