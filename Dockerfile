# GeoAPI – built image is tagged at build time (e.g. by Compose or CI).
# Convention: <registry>/<namespace>/<project>/geoapi:<tag> (GitLab Container Registry).
# =========================
# Build stage
# =========================
FROM golang:1.24-bullseye AS builder

WORKDIR /app

# Install git + CA certs (Debian syntax)
RUN apt-get update && \
    apt-get install -y git ca-certificates && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Go proxy for reliable module downloads
ENV GOPROXY=https://proxy.golang.org,direct

# Install swag for Swagger documentation generation (matching library version)
RUN go install github.com/swaggo/swag/cmd/swag@v1.8.1

# Copy mod files first for caching
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source
COPY . .

# Generate Swagger documentation
RUN swag init -g cmd/server/main.go -o internal/swagger

# Build static binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -v -o geoapi ./cmd/server

# =========================
# Runtime stage
# =========================
FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        docker.io \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/geoapi /app/geoapi
COPY --from=builder /app/scripts /app/scripts
COPY --from=builder /app/migrations /app/migrations
COPY --from=builder /app/.git /app/.git
COPY --from=builder /app/.gitmodules /app/.gitmodules
COPY docker-entrypoint.sh /app/docker-entrypoint.sh

RUN chmod +x /app/docker-entrypoint.sh /app/scripts/*.sh && \
    mkdir -p /app/data

ENV GEOAPI_DATA_DIR=/app/data

EXPOSE 8080

ENTRYPOINT ["/app/docker-entrypoint.sh"]
