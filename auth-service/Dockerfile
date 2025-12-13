FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go.mod and go.sum first for caching
COPY go.mod go.sum ./

# Install dependencies and cache them if they don't change
RUN go mod download

# Now copy the rest of the source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o auth-service .

# Final image
FROM alpine:latest

# Install necessary CA certificates
RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy the
