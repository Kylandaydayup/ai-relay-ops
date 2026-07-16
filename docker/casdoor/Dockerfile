ARG NODE_BASE_IMAGE=node:20.20.1
ARG GO_BASE_IMAGE=golang:1.25.8
ARG ALPINE_BASE_IMAGE=alpine:latest
ARG DEBIAN_BASE_IMAGE=debian:latest

FROM --platform=$BUILDPLATFORM ${NODE_BASE_IMAGE} AS FRONT
WORKDIR /web

COPY ./web/package.json ./web/yarn.lock ./
RUN yarn install --frozen-lockfile --network-timeout 1000000

COPY ./web .
RUN NODE_OPTIONS="--max-old-space-size=4096" yarn run build

FROM --platform=$BUILDPLATFORM ${GO_BASE_IMAGE} AS BACK
WORKDIR /go/src/casdoor

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN go test -v -run TestGetVersionInfo ./util/system_test.go ./util/system.go ./util/variable.go
RUN ./build.sh

FROM ${ALPINE_BASE_IMAGE} AS STANDARD
LABEL MAINTAINER="https://casdoor.org/"
ARG USER=casdoor
ARG TARGETOS
ARG TARGETARCH
ENV BUILDX_ARCH="${TARGETOS:-linux}_${TARGETARCH:-amd64}"

RUN sed -i 's/https/http/' /etc/apk/repositories
RUN apk add --update sudo
RUN apk add tzdata
RUN apk add curl
RUN apk add ca-certificates && update-ca-certificates

RUN adduser -D $USER -u 1000 \
    && echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER \
    && chmod 0440 /etc/sudoers.d/$USER \
    && mkdir logs \
    && chown -R $USER:$USER logs

USER 1000
WORKDIR /
COPY --from=BACK --chown=$USER:$USER /go/src/casdoor/server_${BUILDX_ARCH} ./server
COPY --from=BACK --chown=$USER:$USER /go/src/casdoor/swagger ./swagger
COPY --from=BACK --chown=$USER:$USER /go/src/casdoor/conf/app.conf ./conf/app.conf
COPY --from=FRONT --chown=$USER:$USER /web/build ./web/build

ENTRYPOINT ["/server"]

FROM ${DEBIAN_BASE_IMAGE} AS ALLINONE
LABEL MAINTAINER="https://casdoor.org/"
ARG TARGETOS
ARG TARGETARCH
ENV BUILDX_ARCH="${TARGETOS:-linux}_${TARGETARCH:-amd64}"

RUN apt update
RUN apt install -y ca-certificates lsof && update-ca-certificates

WORKDIR /
COPY --from=BACK /go/src/casdoor/server_${BUILDX_ARCH} ./server
COPY --from=BACK /go/src/casdoor/swagger ./swagger
COPY --from=BACK /go/src/casdoor/docker-entrypoint.sh /docker-entrypoint.sh
COPY --from=BACK /go/src/casdoor/conf/app.conf ./conf/app.conf
COPY --from=FRONT /web/build ./web/build

ENTRYPOINT ["/bin/bash"]
CMD ["/docker-entrypoint.sh"]
