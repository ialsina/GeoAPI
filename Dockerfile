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

# Copy mod files first for caching
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source
COPY . .

# Build static binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -v -o city-api ./cmd/server

# =========================
# Runtime stage
# =========================
FROM gcr.io/distroless/base-debian12

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/city-api /app/city-api

EXPOSE 8080

USER nonroot:nonroot
ENTRYPOINT ["/app/city-api"]

