ARG DEBIAN_BASE_IMAGE=debian:latest

FROM ${DEBIAN_BASE_IMAGE}

ARG DEBIAN_APT_MIRROR=http://mirrors.aliyun.com/debian
RUN sed -i "s#http://deb.debian.org/debian#${DEBIAN_APT_MIRROR}#g; s#http://security.debian.org/debian-security#${DEBIAN_APT_MIRROR}-security#g" /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates lsof \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates
