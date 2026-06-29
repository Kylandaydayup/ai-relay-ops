ENV ?= prod
SERVICE ?= broker
RELEASE ?= $(SERVICE)
NAMESPACE ?= platform
IMAGE_TAG ?=
REVISION ?=
HELM_ARGS ?=

CHART := charts/$(SERVICE)
VALUES := environments/$(ENV)/$(SERVICE).values.yaml

.PHONY: template lint install upgrade rollback uninstall status namespace verify-nginx-staging

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
