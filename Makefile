ENV ?= 139

.PHONY: verify render preflight install upgrade uninstall status package \
	build-new-api build-broker build-ai-provider-adapter build-newapi-compat-gateway \
	build-edreamcrowd-backend build-edreamcrowd-frontend build-casdoor build-gateway \
	build-all sync-base-images harbor-check

verify:
	scripts/verify-standard-deployment.sh

render:
	scripts/platform/render.sh $(ENV)

preflight:
	scripts/platform/preflight.sh $(ENV)

install:
	scripts/platform/install.sh $(ENV)

upgrade:
	scripts/platform/upgrade.sh $(ENV)

uninstall:
	scripts/platform/uninstall.sh $(ENV)

status:
	scripts/platform/status.sh $(ENV)

package:
	scripts/platform/package.sh $(ENV)

build-new-api:
	scripts/images/build-new-api.sh $(ENV)

build-broker:
	scripts/images/build-broker.sh $(ENV)

build-ai-provider-adapter:
	scripts/images/build-ai-provider-adapter.sh $(ENV)

build-newapi-compat-gateway:
	scripts/images/build-newapi-compat-gateway.sh $(ENV)

build-edreamcrowd-backend:
	scripts/images/build-edreamcrowd-backend.sh $(ENV)

build-edreamcrowd-frontend:
	scripts/images/build-edreamcrowd-frontend.sh $(ENV)

build-casdoor:
	scripts/images/build-casdoor.sh $(ENV)

build-gateway:
	scripts/images/build-gateway.sh $(ENV)

build-all:
	scripts/images/build-all.sh $(ENV)

sync-base-images:
	scripts/images/sync-base-images.sh $(ENV)

harbor-check:
	scripts/harbor/check.sh $(ENV)
