VALUES_FILE ?= environments/139/edream-deployment.yaml

.PHONY: verify render preflight install upgrade uninstall status package package-all remote-package-all \
	build-new-api build-broker build-ai-provider-adapter build-newapi-compat-gateway \
	build-edreamcrowd-backend build-edreamcrowd-frontend build-casdoor build-gateway \
	build-all ensure-casdoor image-preflight sync-sources sync-base-images harbor-check cleanup-build-host

verify:
	scripts/verify-standard-deployment.sh

render:
	scripts/platform/render.sh -f $(VALUES_FILE)

preflight:
	scripts/platform/preflight.sh -f $(VALUES_FILE)

install:
	scripts/platform/install.sh -f $(VALUES_FILE)

upgrade:
	scripts/platform/upgrade.sh -f $(VALUES_FILE)

uninstall:
	scripts/platform/uninstall.sh -f $(VALUES_FILE)

status:
	scripts/platform/status.sh -f $(VALUES_FILE)

package:
	scripts/platform/package.sh

package-all:
	scripts/build/package-all.sh

remote-package-all:
	scripts/build/remote-package-all.sh

build-new-api:
	scripts/images/build-new-api.sh

build-broker:
	scripts/images/build-broker.sh

build-ai-provider-adapter:
	scripts/images/build-ai-provider-adapter.sh

build-newapi-compat-gateway:
	scripts/images/build-newapi-compat-gateway.sh

build-edreamcrowd-backend:
	scripts/images/build-edreamcrowd-backend.sh

build-edreamcrowd-frontend:
	scripts/images/build-edreamcrowd-frontend.sh

build-casdoor:
	scripts/images/build-casdoor.sh

ensure-casdoor:
	scripts/images/ensure-casdoor.sh

build-gateway:
	scripts/images/build-gateway.sh

build-all:
	scripts/images/build-all.sh

image-preflight:
	scripts/images/preflight.sh

sync-sources:
	scripts/sources/sync.sh

sync-base-images:
	scripts/images/sync-base-images.sh

harbor-check:
	scripts/harbor/check.sh

cleanup-build-host:
	scripts/maintenance/cleanup-build-host.sh
