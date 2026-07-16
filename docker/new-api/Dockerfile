ARG BUN_BASE_IMAGE=oven/bun:1
ARG GO_BASE_IMAGE=golang:1.26.1-alpine
ARG RUNTIME_BASE_IMAGE=debian:bookworm-slim

FROM ${BUN_BASE_IMAGE} AS builder

WORKDIR /build/web
COPY ./web/default ./default
COPY ./VERSION /build/VERSION
RUN cd default && DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat /build/VERSION) bun run build

FROM ${BUN_BASE_IMAGE} AS builder-classic

WORKDIR /build/web
COPY ./web/classic ./classic
COPY ./VERSION /build/VERSION
RUN cd classic && VITE_REACT_APP_VERSION=$(cat /build/VERSION) bun run build

FROM ${GO_BASE_IMAGE} AS builder2
ENV GO111MODULE=on CGO_ENABLED=0

ARG TARGETOS
ARG TARGETARCH
ENV GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64}
ENV GOEXPERIMENT=greenteagc

WORKDIR /build

COPY . .
COPY --from=builder /build/web/default/dist ./web/default/dist
COPY --from=builder-classic /build/web/classic/dist ./web/classic/dist
RUN go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api

FROM ${RUNTIME_BASE_IMAGE}

COPY --from=builder2 /build/new-api /
COPY LICENSE NOTICE THIRD-PARTY-LICENSES.md /licenses/
EXPOSE 3000
WORKDIR /data
ENTRYPOINT ["/new-api"]
