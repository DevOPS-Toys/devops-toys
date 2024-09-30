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

check-cloudflare-cert:
	@if [ ! -f ~/.cloudflared/cert.pem ]; then \
		echo "The cert.pem file does not exist. Running cloudflared tunnel login..."; \
		cloudflared tunnel login; \
	else \
		echo "The cert.pem file already exists."; \
	fi

cloudflare-tunnel:
	cloudflared tunnel create devops-toys-demo
	kubectl create secret generic tunnel-credentials \
		--from-file=credentials.json=/Users/twostal/.cloudflared/f951b180-f316-400f-a34e-9a38aeff91ad.json \
		--namespace=cloudflare

cloudflare:
	#kubectl create namespace cloudflare
	kubectl --namespace cloudflare \
		create secret \
		generic cloudflare-api-key \
		--from-literal=apiKey=$(CLOUDFLARE_API_KEY) \
		--from-literal=email=$(CLOUDFLARE_EMAIL) \
		--output json \
		--dry-run=client | \
		kubeseal --format yaml \
		--controller-name=sealed-secrets \
		--controller-namespace=sealed-secrets | \
		tee ./configs/cloudflare/local/extras/secret-api-key.yaml

external-dns:
	kubectl create namespace external-dns
	kubectl --namespace external-dns \
		create secret \
		generic cloudflare-api-key \
		--from-literal=apiKey=$(CLOUDFLARE_API_KEY) \
		--from-literal=email=$(CLOUDFLARE_EMAIL) \
		--output json \
		--dry-run=client | \
		kubeseal --format yaml \
		--controller-name=sealed-secrets \
		--controller-namespace=sealed-secrets | \
		tee ./configs/external-dns/local/extras/secret-api-key.yaml
	kubectl apply -f ./applications/external-dns.yaml

configure-argocd:
	kubectl apply -f ./applications/argo-cd.yaml
	sleep 60
	ARGOCD_PASSWORD=$$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) && echo $$ARGOCD_PASSWORD
	kubectl port-forward -n argocd svc/argocd-server 8081:80 & echo $$! > /tmp/port-forward.pid & sleep 5
	argocd login localhost:8081 --insecure --grpc-web --username admin --password $$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
	argocd account update-password --current-password $$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) --new-password $(ARGOCD_PASSWORD)
	kill $$(cat /tmp/port-forward.pid) && rm -f /tmp/port-forward.pid

all: cluster initial-argocd-setup grafana-alloy sealed-secrets ingress-nginx cert-manager configure-argocd

# Teardown 
destroy:
	kind delete cluster --name devops-toys
