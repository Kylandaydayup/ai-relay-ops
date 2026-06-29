#@if API_SERVER_NAME
server {
    listen ${HTTP_LISTEN_PORT};
    listen [::]:${HTTP_LISTEN_PORT};
    server_name ${API_SERVER_NAME};

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    location / {
        proxy_pass ${ROOT_NEWAPI_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
#@endif

#@if AUTH_SERVER_NAME
server {
    listen ${HTTP_LISTEN_PORT};
    listen [::]:${HTTP_LISTEN_PORT};
    server_name ${AUTH_SERVER_NAME};

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    location / {
        proxy_pass ${CASDOOR_UPSTREAM}/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
#@endif

#@if ZHONGCHOU_SERVER_NAME
server {
    listen ${HTTP_LISTEN_PORT};
    listen [::]:${HTTP_LISTEN_PORT};
    server_name ${ZHONGCHOU_SERVER_NAME};

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    location ${ZHONGCHOU_API_PATH} {
        proxy_pass ${EDREAMCROWD_BACKEND_UPSTREAM}${ZHONGCHOU_API_PATH};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size ${CLIENT_MAX_BODY_SIZE};
    }

    location ${OAUTH_PATH} {
        proxy_pass ${EDREAMCROWD_BACKEND_UPSTREAM}${OAUTH_PATH};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location ${LOGIN_OAUTH_PATH} {
        proxy_pass ${EDREAMCROWD_BACKEND_UPSTREAM}${LOGIN_OAUTH_PATH};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = / {
        return 302 ${ZHONGCHOU_BASE_PATH_SLASH};
    }

    location ${ZHONGCHOU_BASE_PATH_SLASH} {
        proxy_pass ${EDREAMCROWD_FRONTEND_UPSTREAM}/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass ${EDREAMCROWD_FRONTEND_UPSTREAM}/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
#@endif

#@if ARCREEL_SERVER_NAME
server {
    listen ${HTTP_LISTEN_PORT};
    listen [::]:${HTTP_LISTEN_PORT};
    server_name ${ARCREEL_SERVER_NAME};

    default_type text/plain;
    return 404 "${ARCREEL_SERVER_NAME} is not configured yet\n";
}
#@endif

server {
    listen ${HTTP_LISTEN_PORT} default_server;
    listen [::]:${HTTP_LISTEN_PORT} default_server;
    server_name ${HTTP_SERVER_NAMES};

    if ($host = ${HTTPS_SERVER_NAME}) {
        return 301 https://$host$request_uri;
    }

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    location = ${DOWNLOAD_PATH} {
        return 302 ${DOWNLOAD_REDIRECT_URL};
    }

    location = ${CASDOOR_BASE_PATH} {
        return 302 http://${AUTH_SERVER_NAME}/$is_args$args;
    }

    location = ${CASDOOR_BASE_PATH_SLASH} {
        return 302 http://${AUTH_SERVER_NAME}/$is_args$args;
    }

    location ~ ^${CASDOOR_BASE_PATH_SLASH}(.*)$ {
        return 302 http://${AUTH_SERVER_NAME}/$1$is_args$args;
    }

    location ${BROKER_INTERNAL_PATH} {
        return 404;
    }

    location = ${NEWAPI_BASE_PATH} {
        return 301 /;
    }

    location ${NEWAPI_BASE_PATH_SLASH} {
        return 301 /;
    }

    location ${NEWAPI_OLD_BASE_PATH} {
        return 301 /;
    }

    location ${BROKER_BASE_PATH} {
        proxy_pass ${RELAY_BROKER_UPSTREAM}/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location ${ZHONGCHOU_API_PATH} {
        proxy_pass ${EDREAMCROWD_BACKEND_UPSTREAM}${ZHONGCHOU_API_PATH};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size ${CLIENT_MAX_BODY_SIZE};
    }

    location ${OAUTH_PATH} {
        proxy_pass ${EDREAMCROWD_BACKEND_UPSTREAM}${OAUTH_PATH};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location ${LOGIN_OAUTH_PATH} {
        proxy_pass ${EDREAMCROWD_BACKEND_UPSTREAM}${LOGIN_OAUTH_PATH};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = ${ZHONGCHOU_BASE_PATH} {
        return 301 ${ZHONGCHOU_BASE_PATH_SLASH};
    }

    location ${ZHONGCHOU_BASE_PATH_SLASH} {
        proxy_pass ${EDREAMCROWD_FRONTEND_UPSTREAM}/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass ${ROOT_NEWAPI_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}

server {
    listen ${COMPAT_LISTEN_PORT};
    server_name _;

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    location ${BROKER_INTERNAL_PATH} {
        return 404;
    }

    location = ${NEWAPI_BASE_PATH} {
        return 301 /;
    }

    location ${NEWAPI_BASE_PATH_SLASH} {
        return 301 /;
    }

    location ${NEWAPI_OLD_BASE_PATH} {
        return 301 /;
    }

    location ${BROKER_BASE_PATH} {
        proxy_pass ${RELAY_BROKER_UPSTREAM}/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location / {
        proxy_pass ${ROOT_NEWAPI_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}

server {
    listen ${HTTPS_LISTEN_PORT} ssl;
    listen [::]:${HTTPS_LISTEN_PORT} ssl;
    server_name ${HTTPS_SERVER_NAME};

    ssl_certificate ${HTTPS_CERTIFICATE};
    ssl_certificate_key ${HTTPS_CERTIFICATE_KEY};
    include ${HTTPS_OPTIONS};
    ssl_dhparam ${HTTPS_DH_PARAM};

    client_max_body_size ${HTTPS_CLIENT_MAX_BODY_SIZE};

    location ${BROKER_INTERNAL_PATH} {
        return 404;
    }

    location = ${NEWAPI_BASE_PATH} {
        return 301 /;
    }

    location ${NEWAPI_BASE_PATH_SLASH} {
        return 301 /;
    }

    location ${NEWAPI_OLD_BASE_PATH} {
        return 301 /;
    }

    location ${BROKER_BASE_PATH} {
        proxy_pass ${RELAY_BROKER_UPSTREAM}/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location / {
        proxy_pass ${ROOT_NEWAPI_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
