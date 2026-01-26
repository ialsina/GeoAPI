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
RUN swag init -g cmd/server/main.go -o docs

# Build static binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -v -o geoapi ./cmd/server

# =========================
# Runtime stage
# =========================
FROM gcr.io/distroless/base-debian12

WORKDIR /app

# Copy binary and Swagger docs from builder
COPY --from=builder /app/geoapi /app/geoapi
COPY --from=builder /app/docs /app/docs

EXPOSE 8080

USER nonroot:nonroot
ENTRYPOINT ["/app/geoapi"]

