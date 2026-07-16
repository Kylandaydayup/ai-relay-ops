ARG GO_BASE_IMAGE=golang:1.26.1-alpine

FROM ${GO_BASE_IMAGE}

ENV GO111MODULE=on CGO_ENABLED=0
ENV GOEXPERIMENT=greenteagc
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY}

WORKDIR /build

ADD go.mod go.sum ./
RUN go mod download
