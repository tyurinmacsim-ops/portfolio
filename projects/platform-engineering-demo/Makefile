SHELL := /bin/bash

CLUSTER_NAME ?= platform-demo
KIND_CONFIG ?= kind/kind-config.yaml
APP_IMAGE ?= demo-api:local
TF_DIR ?= terraform
K8S_DIR ?= k8s/demo-api
GRAFANA_PASSWORD ?= admin123
DEMO_KUBECONFIG ?= $(CURDIR)/.tmp/kubeconfig
HELM_REPO_CONFIG ?= $(CURDIR)/.tmp/helm/repositories.yaml
HELM_REPO_CACHE ?= $(CURDIR)/.tmp/helm/cache
HELM_ENV = HELM_REPOSITORY_CONFIG=$(HELM_REPO_CONFIG) HELM_REPOSITORY_CACHE=$(HELM_REPO_CACHE)

.PHONY: tool-check helm-bootstrap fmt validate kind-up kind-down tf-init tf-plan tf-apply app-image kind-load app-deploy smoke grafana prometheus

tool-check:
	@for tool in docker kind kubectl helm terraform; do \
		command -v $$tool >/dev/null 2>&1 || { echo "$$tool is required"; exit 1; }; \
	done

helm-bootstrap:
	mkdir -p .tmp/helm/cache
	$(HELM_ENV) helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
	$(HELM_ENV) helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
	$(HELM_ENV) helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
	$(HELM_ENV) helm repo update

fmt:
	terraform fmt -recursive

validate:
	terraform -chdir=$(TF_DIR) init -backend=false
	terraform -chdir=$(TF_DIR) validate
	kubectl kustomize $(K8S_DIR) >/dev/null

kind-up: tool-check
	mkdir -p .tmp
	kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)
	kind export kubeconfig --name $(CLUSTER_NAME) --kubeconfig $(DEMO_KUBECONFIG)

kind-down:
	kind delete cluster --name $(CLUSTER_NAME)

tf-init: helm-bootstrap
	$(HELM_ENV) terraform -chdir=$(TF_DIR) init

tf-plan: tf-init
	$(HELM_ENV) terraform -chdir=$(TF_DIR) plan \
		-var="kubeconfig_path=$(DEMO_KUBECONFIG)" \
		-var="kube_context=kind-$(CLUSTER_NAME)" \
		-var="grafana_admin_password=$(GRAFANA_PASSWORD)"

tf-apply: tf-init
	$(HELM_ENV) terraform -chdir=$(TF_DIR) apply -auto-approve \
		-var="kubeconfig_path=$(DEMO_KUBECONFIG)" \
		-var="kube_context=kind-$(CLUSTER_NAME)" \
		-var="grafana_admin_password=$(GRAFANA_PASSWORD)"

app-image:
	docker build -t $(APP_IMAGE) app

kind-load:
	kind load docker-image $(APP_IMAGE) --name $(CLUSTER_NAME)

app-deploy: app-image kind-load
	KUBECONFIG=$(DEMO_KUBECONFIG) ./scripts/deploy_demo_app.sh $(APP_IMAGE)

smoke:
	KUBECONFIG=$(DEMO_KUBECONFIG) ./scripts/smoke_test.sh

grafana:
	KUBECONFIG=$(DEMO_KUBECONFIG) kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80

prometheus:
	KUBECONFIG=$(DEMO_KUBECONFIG) kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090
