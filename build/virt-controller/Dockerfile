FROM golang:1.25.1-alpine3.22 AS builder

WORKDIR /workspace

COPY go.mod go.mod
COPY go.sum go.sum
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY cmd/ cmd/
COPY pkg/ pkg/
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build cmd/virt-controller/main.go

FROM alpine:3.22.1

ARG PRERUNNER_IMAGE
ENV PRERUNNER_IMAGE=$PRERUNNER_IMAGE

COPY --from=builder /workspace/main /usr/bin/virt-controller
ENTRYPOINT ["virt-controller"]
