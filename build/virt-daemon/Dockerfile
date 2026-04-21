FROM golang:1.25.1-alpine3.22 AS builder

WORKDIR /workspace

COPY go.mod go.mod
COPY go.sum go.sum
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY cmd/ cmd/
COPY pkg/ pkg/
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build cmd/virt-daemon/main.go

FROM alpine:3.22.1

COPY --from=builder /workspace/main /usr/bin/virt-daemon
ENTRYPOINT ["virt-daemon"]
