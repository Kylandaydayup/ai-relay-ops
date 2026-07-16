ARG BUN_BASE_IMAGE=oven/bun:1

FROM ${BUN_BASE_IMAGE}

WORKDIR /build/web

COPY web/package.json web/bun.lock ./
COPY web/default/package.json ./default/package.json
COPY web/classic/package.json ./classic/package.json
RUN bun install --frozen-lockfile \
    && cd default && bun install --frozen-lockfile \
    && cd ../classic && bun install --frozen-lockfile \
    && cd .. \
    && mkdir -p node_modules/date-fns-tz/node_modules \
    && cp -R node_modules/@douyinfe/semi-ui/node_modules/date-fns node_modules/date-fns-tz/node_modules/date-fns
