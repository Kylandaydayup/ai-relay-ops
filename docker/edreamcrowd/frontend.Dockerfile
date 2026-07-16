ARG NODE_BASE_IMAGE=node:20-alpine
ARG NGINX_BASE_IMAGE=nginx:alpine
ARG VITE_PUBLIC_BASE=/

FROM ${NODE_BASE_IMAGE} AS build
WORKDIR /app
ARG VITE_PUBLIC_BASE
ENV VITE_PUBLIC_BASE=${VITE_PUBLIC_BASE}
COPY . .
RUN npm run build

FROM ${NGINX_BASE_IMAGE}

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
