# Include environment variables
ENV	:= $(PWD)/.env
include $(ENV)
OS := $(shell uname -s)

# Create a local Kubernetes cluster
cluster:
	@echo "Creating local Kubernetes cluster"
	kind create cluster --config ./kind/cluster-local.yaml

.ONESHELL:
initial-argocd-setup:
	helm repo add argo https://argoproj.github.io/argo-helm --force-update
	helm upgrade --install \
		argocd argo/argo-cd \
		--namespace argocd \
		--create-namespace \
		--wait
	kubectl apply -n argocd -f ./bootstrap/projects.yaml

grafana-alloy:
	kubectl apply -f ./applications/grafana-alloy.yaml

sealed-secrets:
	kubectl apply -f ./applications/sealed-secrets.yaml
	sleep 60

ingress-nginx:
	kubectl apply -f ./applications/ingress-nginx.yaml

cert-manager:
	kubectl create namespace cert-manager
	openssl genrsa -out ca.key 4096
	openssl req -new -x509 -sha256 -days 3650 \
		-key ca.key \
		-out ca.crt \
		-subj '/CN=$(CN)/emailAddress=$(GITHUB_EMAIL)/C=$(C)/ST=$(ST)/L=$(L)/O=$(O)/OU=$(OU)'
	kubectl --namespace cert-manager \
		create secret \
		generic devops-local-ca \
		--from-file=tls.key=ca.key \
		--from-file=tls.crt=ca.crt \
		--output json \
		--dry-run=client | \
		kubeseal --format yaml \
		--controller-name=sealed-secrets \
		--controller-namespace=sealed-secrets -oyaml - | \
		kubectl patch -f - \
		-p '{"spec": {"template": {"metadata": {"annotations": {"argocd.argoproj.io/sync-wave":"0"}}}}}' \
		--dry-run=client \
		--type=merge \
		--local -oyaml > ./configs/cert-manager/local/extras/ca-secret.yaml
	git add ./configs/cert-manager/local/extras/ca-secret.yaml
	git commit -m "Add CA cert secret"
	git push
	sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt
	kubectl apply -f ./applications/cert-manager.yaml

all: cluster initial-argocd-setup grafana-alloy sealed-secrets ingress-nginx cert-manager

# Teardown 
destroy:
	kind delete cluster --name devops-toys
