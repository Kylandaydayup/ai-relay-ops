ENV ?= prod
SERVICE ?= broker
RELEASE ?= $(SERVICE)
NAMESPACE ?= platform
IMAGE_TAG ?=
REVISION ?=
HELM_ARGS ?=
BUNDLE_ENV ?= template
BUNDLE_DIR ?=
BUILD_ENV_FILE ?= build/images.env

CHART := charts/$(SERVICE)
VALUES := environments/$(ENV)/$(SERVICE).values.yaml

.PHONY: template lint install upgrade rollback uninstall status namespace verify-nginx-staging verify-platform-chart build-images package-bundle build-bundle install-bundle deploy-bundle

namespace:
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

template:
	helm template $(RELEASE) $(CHART) -n $(NAMESPACE) -f $(VALUES) $(HELM_ARGS)

lint:
	helm lint $(CHART) -f $(VALUES)

install: namespace
	helm upgrade --install $(RELEASE) $(CHART) -n $(NAMESPACE) -f $(VALUES) $(HELM_ARGS)

upgrade: namespace
	@if [ -n "$(IMAGE_TAG)" ]; then \
		helm upgrade --install $(RELEASE) $(CHART) -n $(NAMESPACE) -f $(VALUES) --set image.tag=$(IMAGE_TAG) $(HELM_ARGS); \
	else \
		helm upgrade --install $(RELEASE) $(CHART) -n $(NAMESPACE) -f $(VALUES) $(HELM_ARGS); \
	fi

rollback:
	@if [ -z "$(REVISION)" ]; then echo "REVISION is required"; exit 1; fi
	helm rollback $(RELEASE) $(REVISION) -n $(NAMESPACE)

uninstall:
	helm uninstall $(RELEASE) -n $(NAMESPACE)

status:
	kubectl get pods,svc,ingress -n $(NAMESPACE)
	helm list -n $(NAMESPACE)

verify-nginx-staging:
	scripts/verify-nginx-staging.sh

verify-platform-chart:
	scripts/verify-platform-chart.sh

build-images:
	scripts/build-platform-images.sh $(BUILD_ENV_FILE)

package-bundle:
	ENV_NAME=$(BUNDLE_ENV) BUNDLE_DIR="$(BUNDLE_DIR)" scripts/package-platform-bundle.sh

build-bundle:
	ENV_NAME=$(BUNDLE_ENV) BUILD_ENV_FILE=$(BUILD_ENV_FILE) BUNDLE_DIR="$(BUNDLE_DIR)" scripts/build-platform-bundle.sh

install-bundle:
	scripts/install-platform-bundle.sh

deploy-bundle:
	scripts/deploy-platform-bundle.sh
