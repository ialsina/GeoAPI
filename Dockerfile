# =========================
# Build stage
# =========================
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Install build deps
RUN apk add --no-cache git ca-certificates
ENV GOPROXY=https://proxy.golang.org,direct

# Copy go mod files first (better caching)
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY . .

# Build static binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -o city-api ./cmd/server

# =========================
# Runtime stage
# =========================
FROM gcr.io/distroless/base-debian12

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/city-api /app/city-api

# Expose HTTP port
EXPOSE 8080

# Run binary
USER nonroot:nonroot
ENTRYPOINT ["/app/city-api"]

