ARG NGINX_IMAGE=nginx:alpine
FROM ${NGINX_IMAGE}

COPY dist /usr/share/nginx/html
