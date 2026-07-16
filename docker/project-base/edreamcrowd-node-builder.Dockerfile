ARG NODE_BASE_IMAGE=node:20-alpine

FROM ${NODE_BASE_IMAGE}

WORKDIR /app

COPY package*.json ./
RUN npm ci
