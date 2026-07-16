ARG NODE_BASE_IMAGE=node:20.20.1

FROM ${NODE_BASE_IMAGE}

WORKDIR /web

COPY ./web/package.json ./web/yarn.lock ./
RUN yarn install --frozen-lockfile --network-timeout 1000000
