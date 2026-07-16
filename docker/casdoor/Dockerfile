ARG NODE_BASE_IMAGE=node:20.20.1
ARG GO_BASE_IMAGE=golang:1.25.8
ARG RUNTIME_BASE_IMAGE=debian:latest

FROM ${NODE_BASE_IMAGE} AS FRONT
WORKDIR /web

COPY ./web .
RUN NODE_OPTIONS="--max-old-space-size=4096" yarn run build

FROM ${GO_BASE_IMAGE} AS BACK
WORKDIR /go/src/casdoor

COPY . .

RUN ./build.sh

FROM ${RUNTIME_BASE_IMAGE} AS ALLINONE
LABEL MAINTAINER="https://casdoor.org/"
ARG TARGETOS
ARG TARGETARCH
ENV BUILDX_ARCH="${TARGETOS:-linux}_${TARGETARCH:-amd64}"

WORKDIR /
COPY --from=BACK /go/src/casdoor/server_${BUILDX_ARCH} ./server
COPY --from=BACK /go/src/casdoor/swagger ./swagger
COPY --from=BACK /go/src/casdoor/docker-entrypoint.sh /docker-entrypoint.sh
COPY --from=BACK /go/src/casdoor/conf/app.conf ./conf/app.conf
COPY --from=FRONT /web/build ./web/build

ENTRYPOINT ["/bin/bash"]
CMD ["/docker-entrypoint.sh"]
