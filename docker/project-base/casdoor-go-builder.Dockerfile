ARG GO_BASE_IMAGE=golang:1.25.8

FROM ${GO_BASE_IMAGE}

ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY}

WORKDIR /go/src/casdoor

COPY go.mod go.sum ./
RUN go mod download
