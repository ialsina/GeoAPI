# GeoAPI

A high-performance REST API for querying cities and administrative boundaries with geospatial capabilities. Built with Go, PostgreSQL/PostGIS, and Docker.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Database Setup](#database-setup)
- [API Endpoints](#api-endpoints)
- [API Documentation](#api-documentation)
- [Development](#development)
- [Project Structure](#project-structure)
- [Data Sources](#data-sources)
- [Configuration](#configuration)
- [Docker Deployment](#docker-deployment)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

- **City Lookup**: Query cities by ID, name, or fuzzy search
- **Geospatial Queries**: Find administrative boundaries by coordinates, city name, or geoname ID
- **Fuzzy Matching**: Advanced trigram-based similarity search for city names
- **Multiple Boundary Types**: Support for ADM2 (administrative level 2) and city boundaries
- **PostGIS Integration**: Leverages PostgreSQL's PostGIS extension for efficient geospatial operations
- **RESTful API**: Clean, well-documented REST endpoints
- **Swagger Documentation**: Interactive API documentation
- **Docker Support**: Easy deployment with Docker Compose
- **Performance Optimized**: GIST indexes for spatial queries and GIN indexes for text search

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ HTTP/REST
       ▼
┌─────────────┐
│  Go API     │  (Chi Router, Swagger)
│  Server     │
└──────┬──────┘
       │ SQL
       ▼
┌─────────────┐
│ PostgreSQL  │  (PostGIS Extension)
│  Database   │
└─────────────┘
```

The API is built using:
- **Go 1.24+** for the HTTP server
- **Chi** router for HTTP routing
- **pgx/v5** for PostgreSQL connection pooling
- **PostGIS** for geospatial operations
- **Swagger/OpenAPI** for API documentation

## Prerequisites

- **Docker** and **Docker Compose** (recommended)
- **Go 1.24+** (for local development)
- **PostgreSQL 15+** with PostGIS extension (if running without Docker)
- **Git** (for cloning the repository)

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd geoapi
   ```

2. **Start the services**:
   ```bash
   docker-compose up -d
   ```

3. **Run database migrations**:
   ```bash
   ./scripts/run_migrations.sh
   ```

4. **Download and populate data**:
   ```bash
   # Download cities data
   ./scripts/download_cities1000.sh

   # Populate cities
   ./scripts/populate_cities.sh
   ```

5. **Access the API**:
   - API: http://localhost:8080
   - Swagger Docs: http://localhost:8080/docs/

## Installation

### Using Docker (Recommended)

The easiest way to run GeoAPI is using Docker Compose:

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f api

# Stop services
docker-compose down
```

### Local Development

1. **Install Go dependencies**:
   ```bash
   go mod download
   ```

2. **Set up PostgreSQL with PostGIS**:
   ```bash
   # Using Docker for database only
   docker run -d \
     --name geoapi-db \
     -e POSTGRES_DB=geodb \
     -e POSTGRES_USER=geouser \
     -e POSTGRES_PASSWORD=geopass \
     -p 5433:5432 \
     postgis/postgis:15-3.4
   ```

3. **Set environment variable**:
   ```bash
   export DATABASE_URL="postgres://geouser:geopass@localhost:5433/geodb"
   ```

4. **Run migrations**:
   ```bash
   ./scripts/run_migrations.sh
   ```

5. **Build and run**:
   ```bash
   go build -o geoapi ./cmd/server
   ./geoapi
   ```

## Database Setup

### Schema

The database consists of three main tables:

1. **`cities_1000`**: Cities with population ≥ 1000
   - Primary key: `geonameid`
   - Includes: name, coordinates, population, country code
   - Spatial index on `geom` (Point geometry)

2. **`adm2_boundaries`**: Administrative level 2 boundaries
   - Primary key: `shape_id`
   - Includes: shape name, country code
   - Spatial index on `geom` (MultiPolygon geometry)

3. **`city_boundaries`**: City boundary polygons
   - Primary key: `name`
   - Spatial index on `geom` (MultiPolygon geometry)

### Running Migrations

Migrations are located in the `migrations/` directory and are executed in alphabetical order:

```bash
./scripts/run_migrations.sh
```

This script:
- Connects to the PostgreSQL container
- Creates PostGIS and pg_trgm extensions
- Creates all tables with appropriate indexes
- Sets up spatial indexes for optimal query performance

## API Endpoints

### Get City

Retrieve a single city by geoname ID or name.

**Endpoint**: `GET /city`

**Query Parameters**:
- `geonameid` (optional): GeoNames ID
- `name` (optional): City name
- `country` (optional): ISO 2-letter country code (required when searching by name alone)

**Examples**:
```bash
# By geoname ID
curl "http://localhost:8080/city?geonameid=5391959"

# By name and country
curl "http://localhost:8080/city?name=San%20Francisco&country=US"

# By name only (returns most populous match)
curl "http://localhost:8080/city?name=Paris"
```

**Response**:
```json
{
  "geonameid": 5391959,
  "name": "San Francisco",
  "asciiname": "San Francisco",
  "country": "US",
  "population": 873965,
  "latitude": 37.7749,
  "longitude": -122.4194
}
```

### Search Cities

Fuzzy search for cities by name using trigram similarity.

**Endpoint**: `GET /cities`

**Query Parameters**:
- `name` (required): City name to search for
- `country` (optional): Filter by country code
- `limit` (optional): Maximum results (default: 50, max: 200)
- `threshold` (optional): Minimum similarity (default: 0.2, range: 0.0-1.0)

**Examples**:
```bash
# Basic search
curl "http://localhost:8080/cities?name=San%20Francisco"

# With country filter
curl "http://localhost:8080/cities?name=Paris&country=FR"

# With custom limit and threshold
curl "http://localhost:8080/cities?name=New%20York&limit=10&threshold=0.3"
```

**Response**:
```json
{
  "cities": [
    {
      "geonameid": 5391959,
      "name": "San Francisco",
      "asciiname": "San Francisco",
      "country": "US",
      "population": 873965,
      "latitude": 37.7749,
      "longitude": -122.4194
    }
  ],
  "count": 1
}
```

### Get Boundary

Retrieve administrative boundaries (ADM2 or city) by various methods.

**Endpoint**: `GET /boundary`

**Query Parameters** (priority order):
1. **By geoname ID**:
   - `geonameid` (required): GeoNames ID of the city

2. **By city name and country**:
   - `name` (required): City name
   - `country` (required): ISO 2-letter country code

3. **By coordinates**:
   - `lat` (required): Latitude
   - `lon` (required): Longitude

**Additional Parameters**:
- `type` (optional): Boundary type - `"adm2"` or `"city"` (default: `"city"`)

**Examples**:
```bash
# By geoname ID
curl "http://localhost:8080/boundary?geonameid=5391959"

# By city name and country
curl "http://localhost:8080/boundary?name=San%20Francisco&country=US"

# By coordinates (city boundary)
curl "http://localhost:8080/boundary?lat=37.7749&lon=-122.4194&type=city"

# By coordinates (ADM2 boundary)
curl "http://localhost:8080/boundary?lat=37.7749&lon=-122.4194&type=adm2"
```

**Response**:
```json
{
  "name": "San Francisco",
  "geometry": "{\"type\":\"MultiPolygon\",\"coordinates\":[[[...]]]}",
  "city": {
    "geonameid": 5391959,
    "name": "San Francisco",
    "country": "US",
    "lat": 37.7749,
    "lon": -122.4194
  }
}
```

## API Documentation

Interactive Swagger documentation is available at:

```
http://localhost:8080/docs/
```

The documentation includes:
- All available endpoints
- Request/response schemas
- Parameter descriptions
- Example requests and responses
- Try-it-out functionality

To regenerate Swagger documentation:

```bash
# Install swag
go install github.com/swaggo/swag/cmd/swag@latest

# Generate docs
swag init -g cmd/server/main.go -o docs
```

## Development

### Project Structure

```
geoapi/
├── cmd/
│   └── server/
│       └── main.go          # Application entry point
├── internal/
│   ├── db/
│   │   └── postgres.go      # Database connection pool
│   ├── handlers/
│   │   ├── city.go          # City endpoints
│   │   └── boundary.go      # Boundary endpoints
│   └── models/
│       └── city.go          # Data models
├── migrations/
│   └── 001_init.sql         # Database schema
├── scripts/
│   ├── download_*.sh        # Data download scripts
│   ├── populate_*.sh        # Data population scripts
│   └── run_migrations.sh   # Migration runner
├── data/                    # Data files (gitignored)
├── docs/                    # Swagger documentation
├── docker-compose.yml       # Docker Compose configuration
├── Dockerfile               # API container definition
├── go.mod                   # Go module definition
└── README.md               # This file
```

### Building

```bash
# Build binary
go build -o geoapi ./cmd/server

# Build Docker image
docker build -t geoapi:latest .
```

### Running Tests

```bash
# Run all tests
go test ./...

# Run with coverage
go test -cover ./...
```

### Code Style

The project follows standard Go conventions:
- Use `gofmt` for formatting
- Follow Go naming conventions
- Add comments for exported functions and types
- Use meaningful variable names

## Data Sources

### Cities Data

Cities data is sourced from **GeoNames**:
- **Source**: [GeoNames Cities with Population ≥ 1000](https://download.geonames.org/export/dump/cities1000.zip)
- **Format**: Tab-separated values
- **Fields**: geonameid, name, asciiname, coordinates, population, country code, etc.

**Download**:
```bash
./scripts/download_cities1000.sh
```

**Populate**:
```bash
./scripts/populate_cities.sh
```

### City Boundaries

City boundary polygons from the **geojson-world-cities** dataset:
- **Source**: [geojson-world-cities](https://github.com/geojson-world-cities)
- **Format**: GeoJSON
- **Coverage**: Global city boundaries

**Populate**:
```bash
./scripts/populate_city_boundaries.sh
```

### ADM2 Boundaries

Administrative level 2 boundaries from **geoBoundaries**:
- **Source**: [geoBoundaries CGAZ ADM2](https://www.geoboundaries.org/)
- **Format**: GeoJSON
- **Coverage**: Global administrative boundaries

**Download**:
```bash
./scripts/download_geoboundaries_adm2.sh
```

**Populate**:
```bash
./scripts/populate_geoboundaries_adm2.sh
```

## Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `DATABASE_URL` | PostgreSQL connection string | - | Yes |

**Example**:
```bash
DATABASE_URL="postgres://geouser:geopass@localhost:5433/geodb"
```

### Docker Compose Configuration

The `docker-compose.yml` file configures:

- **Database Service**:
  - Image: `postgis/postgis:15-3.4`
  - Port: `5433:5432`
  - Database: `geodb`
  - User: `geouser`
  - Password: `geopass`
  - Volume: Persistent PostgreSQL data

- **API Service**:
  - Build: From local Dockerfile
  - Port: `8080:8080`
  - Environment: `DATABASE_URL` set automatically
  - Depends on: Database service

### Database Connection Pool

The connection pool is configured in `internal/db/postgres.go`:
- Max connections: 10
- Min connections: 2
- Max connection lifetime: 1 hour

## Docker Deployment

### Production Deployment

For production, consider:

1. **Environment Variables**: Use secrets management
2. **Reverse Proxy**: Add nginx/traefik for SSL termination
3. **Monitoring**: Add health check endpoints
4. **Logging**: Configure structured logging
5. **Backups**: Set up regular database backups

### Health Checks

Add health check endpoint (example):

```go
r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
    // Check database connection
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    if err := pool.Ping(ctx); err != nil {
        http.Error(w, "Database unavailable", http.StatusServiceUnavailable)
        return
    }

    w.WriteHeader(http.StatusOK)
    w.Write([]byte("OK"))
})
```

## Troubleshooting

### Database Connection Issues

**Problem**: Cannot connect to database

**Solutions**:
- Verify `DATABASE_URL` is set correctly
- Check if PostgreSQL container is running: `docker ps`
- Verify network connectivity: `docker network ls`
- Check database logs: `docker logs geoapi-db`

### Migration Errors

**Problem**: Migrations fail

**Solutions**:
- Ensure PostGIS extension is available
- Check database user permissions
- Verify migration files are valid SQL
- Check migration logs for specific errors

### Data Population Issues

**Problem**: Scripts fail to populate data

**Solutions**:
- Verify data files exist in `data/` directory
- Check file permissions
- Ensure Docker volumes are mounted correctly
- Verify database container is accessible from scripts

### Performance Issues

**Problem**: Slow queries

**Solutions**:
- Verify spatial indexes are created: `\d+ cities_1000`
- Check if `pg_trgm` extension is enabled
- Analyze query plans: `EXPLAIN ANALYZE`
- Consider increasing connection pool size

### Port Conflicts

**Problem**: Port already in use

**Solutions**:
- Change port mapping in `docker-compose.yml`
- Find and stop conflicting service: `lsof -i :8080`
- Use different ports for development

## Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes**: Follow Go conventions and add tests
4. **Commit your changes**: Use clear, descriptive commit messages
5. **Push to the branch**: `git push origin feature/amazing-feature`
6. **Open a Pull Request**: Provide a clear description of changes

### Development Guidelines

- Write tests for new features
- Update documentation for API changes
- Follow existing code style
- Add comments for complex logic
- Update Swagger annotations for new endpoints

## License

[Add your license information here]

## Acknowledgments

- **GeoNames** for city data
- **geoBoundaries** for administrative boundaries
- **geojson-world-cities** for city boundary polygons
- **PostGIS** for geospatial capabilities
- **Go community** for excellent libraries

## Support

For issues, questions, or contributions:
- Open an issue on GitHub
- Check existing documentation
- Review Swagger API documentation at `/docs/`

---

**Built with ❤️ using Go, PostgreSQL, and PostGIS**
