# Include environment variables
ENV	:= $(PWD)/.env
include $(ENV)
OS := $(shell uname -s)

# Create a local Kubernetes cluster
cluster:
	@if ! kind get clusters | grep -q '^devops-toys$$'; then \
		echo "Cluster 'devops-toys' not found. Creating..."; \
		kind create cluster --config ./kind/cluster-local.yaml; \
	else \
		echo "Cluster 'devops-toys' already exists."; \
	fi

initial-argocd-setup:
	@echo "Installing initial version of Argo CD ..."
	@helm repo add argo https://argoproj.github.io/argo-helm --force-update
	@helm upgrade --install \
		argocd argo/argo-cd \
			--namespace argocd \
			--create-namespace \
			--wait
	@kubectl apply -n argocd -f ./bootstrap/projects.yaml

# grafana-alloy:
# 	@echo "Installing Grafana Alloy ..."
# 	@kubectl apply -f ./applicationsets/grafana-alloy.yaml
# 	@sleep 60

sealed-secrets:
	@echo "Installing Sealed Secrets ..."
	@kubectl apply -f ./applicationsets/sealed-secrets.yaml
	@sleep 60

certmanager-ca:
	@if kubectl get namespace cert-manager >/dev/null 2>&1; then \
		echo "Namespace cert-manager already exists."; \
	else \
		echo "Namespace cert-manager does not exist. Creating..."; \
		kubectl create namespace cert-manager; \
		echo "Namespace cert-manager has been created."; \
	fi
	@echo "Creating Certificate Authority (CA)"
	openssl genrsa -out ca.key 4096
	openssl req -new -x509 -sha256 -days 3650 \
		-key ca.key \
		-out ca.crt \
		-subj '/CN=$(CN)/emailAddress=$(CERT_EMAIL)/C=$(C)/ST=$(ST)/L=$(L)/O=$(O)/OU=$(OU)'

certmanager-secret:
	@if kubectl get namespace cert-manager >/dev/null 2>&1; then \
		echo "Namespace cert-manager already exists."; \
	else \
		echo "Namespace cert-manager does not exist. Creating..."; \
		kubectl create namespace cert-manager; \
		echo "Namespace cert-manager has been created."; \
	fi
	@echo "Creating secrets for Cert Manager..."
	@kubectl --namespace cert-manager \
		create secret \
		generic devopslabolatory-org-ca \
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
			--local -oyaml > ./configs/cert-manager/dev/extras/ca-secret.yaml

ca-trusted:
	sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt

cert-manager: certmanager-ca certmanager-secret ca-trusted

cloudflare-tunnel:
	@if [ ! -f ~/.cloudflared/cert.pem ]; then \
		echo "The cert.pem file does not exist. Running cloudflared tunnel login ..."; \
		cloudflared tunnel login; \
		cloudflared tunnel create devopslabolatory; \
	else \
		echo "The cert.pem file already exists."; \
	fi

cloudflare-tunnel-credentials-secret:
	@if kubectl get namespace cloudflare >/dev/null 2>&1; then \
		echo "Namespace cloudflare already exists."; \
	else \
		echo "Namespace cloudflare does not exist. Creating..."; \
		kubectl create namespace cloudflare; \
		echo "Namespace cloudflare has been created."; \
	fi
	@echo "Creating cloudflare tunnel credentials secret ..."
	@kubectl --namespace cloudflare \
		create secret \
		generic tunnel-credentials \
			--from-file=credentials.json=$(HOME)/.cloudflared/$(CLOUDFLARE_TUNNEL_ID).json \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./configs/cloudflare-tunnel/dev/extras/secret-tunnel-credentials.yaml > /dev/null

cloudflare-api-key-secret:
	@if kubectl get namespace cloudflare >/dev/null 2>&1; then \
		echo "Namespace cloudflare already exists."; \
	else \
		echo "Namespace cloudflare does not exist. Creating..."; \
		kubectl create namespace cloudflare; \
		echo "Namespace cloudflare has been created."; \
	fi
	@echo "Creating cloudflare api key secret ..."
	@kubectl --namespace cloudflare \
		create secret \
		generic cloudflare-api-key \
			--from-literal=apiKey=$(CLOUDFLARE_API_KEY) \
			--from-literal=email=$(CLOUDFLARE_EMAIL) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./configs/cloudflare-tunnel/dev/extras/secret-api-key.yaml > /dev/null

cloudflare: cloudflare-tunnel cloudflare-tunnel-credentials-secret cloudflare-api-key-secret

external-dns:
	@if kubectl get namespace external-dns >/dev/null 2>&1; then \
		echo "Namespace external-dns already exists."; \
	else \
		echo "Namespace external-dns does not exist. Creating..."; \
		kubectl create namespace external-dns; \
		echo "Namespace external-dns has been created."; \
	fi
	echo "Creating external-dns cloudflare api key credentials secret ..."
	@kubectl --namespace external-dns \
		create secret \
		generic cloudflare-api-key \
			--from-literal=cloudflare_api_key=$(CLOUDFLARE_API_KEY) \
			--from-literal=email=$(CLOUDFLARE_EMAIL) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./configs/external-dns/dev/extras/secret-api-key.yaml > /dev/null

argocd-oauth-client-secret:
	@if kubectl get namespace argocd >/dev/null 2>&1; then \
		echo "Namespace argocd already exists."; \
	else \
		echo "Namespace argocd does not exist. Creating..."; \
		kubectl create namespace argocd; \
		echo "Namespace argocd has been created."; \
	fi
	echo "Creating argocd oauth client secret ..."
	@kubectl --namespace argocd \
		create secret \
		generic argocd-google-oauth-client \
			--from-literal=client_id=$(GOOGLE_CLIENT_ID) \
			--from-literal=client_secret=$(GOOGLE_CLIENT_SECRET) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		kubectl patch -f - \
			-p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
			--type=merge \
			--local -o yaml > ./configs/argo-cd/dev/extras/argocd-google-oauth-client.yaml

argocd-google-domain-wide-sa-json:
	@if kubectl get namespace argocd >/dev/null 2>&1; then \
		echo "Namespace argocd already exists."; \
	else \
		echo "Namespace argocd does not exist. Creating..."; \
		kubectl create namespace argocd; \
		echo "Namespace argocd has been created."; \
	fi
	echo "Creating argocd google domain wide sa json secret ..."
	@kubectl --namespace argocd \
		create secret \
		generic argocd-google-domain-wide-sa-json \
			--from-file=googleAuth.json=devopslaboratory-f90072620e7c.json \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets -oyaml - | \
		kubectl patch -f - \
			-p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
			--dry-run=client \
			--type=merge \
			--local -oyaml > ./configs/argo-cd/dev/extras/argocd-google-domain-wide-sa-json.yaml

argocd-argo-workflows-sso:
	@if kubectl get namespace argocd >/dev/null 2>&1; then \
		echo "Namespace argocd already exists."; \
	else \
		echo "Namespace argocd does not exist. Creating..."; \
		kubectl create namespace argocd; \
		echo "Namespace argocd has been created."; \
	fi
	echo "Creating argocd argo-workflows sso secret ..."
	@kubectl --namespace argocd \
		create secret \
		generic argo-workflows-sso \
			--from-literal=client-id=$(ARGO_WORKFLOWS_CLIENT_ID) \
			--from-literal=client-secret=$(ARGO_WORKFLOWS_CLIENT_SECRET) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		kubectl patch -f - \
			-p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
			--type=merge \
			--local -oyaml > ./configs/argo-cd/dev/extras/argo-workflows-sso.yaml

argocd-notifications-secret:
	@if kubectl get namespace argocd >/dev/null 2>&1; then \
		echo "Namespace argocd already exists."; \
	else \
		echo "Namespace argocd does not exist. Creating..."; \
		kubectl create namespace argocd; \
		echo "Namespace argocd has been created."; \
	fi
	echo "Creating argocd notifications secret ..."
	@kubectl --namespace argocd \
		create secret \
			generic argocd-notifications-secret \
				--from-file=github-privateKey=devops-toys.2024-10-04.private-key.pem \
				--output json \
				--dry-run=client | \
			kubeseal --format yaml \
				--controller-name=sealed-secrets \
				--controller-namespace=sealed-secrets -oyaml - | \
			kubectl patch -f - \
				-p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
				--dry-run=client \
				--type=merge \
				--local -oyaml > ./configs/argo-cd/dev/extras/secret-argocd-notifications.yaml

argo-cd: argocd-oauth-client-secret argocd-google-domain-wide-sa-json argocd-argo-workflows-sso argocd-notifications-secret


argo-workflows-sso-credentials:
	@if kubectl get namespace argo >/dev/null 2>&1; then \
		echo "Namespace argo already exists."; \
	else \
		echo "Namespace argo does not exist. Creating..."; \
		kubectl create namespace argo; \
		echo "Namespace argo has been created."; \
	fi
	echo "Creating argo argo-workflows sso secret ..."
	@kubectl --namespace argo \
		create secret \
		generic argo-workflows-sso \
			--from-literal=client-id=$(ARGO_WORKFLOWS_CLIENT_ID) \
			--from-literal=client-secret=$(ARGO_WORKFLOWS_CLIENT_SECRET) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./configs/argo-workflows/dev/extras/argo-workflows-sso.yaml > /dev/null

argo-workflows-git-credentials:
	@if kubectl get namespace argo >/dev/null 2>&1; then \
		echo "Namespace argo already exists."; \
	else \
		echo "Namespace argo does not exist. Creating..."; \
		kubectl create namespace argo; \
		echo "Namespace argo has been created."; \
	fi
	@kubectl --namespace argo \
		create secret \
		generic git-credentials \
			--from-literal=token=$(WOSTAL_GITHUB_TOKEN) \
			--from-literal=username=$(WOSTAL_GITHUB_USERNAME) \
			--from-literal=email=$(WOSTAL_GITHUB_EMAIL) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./configs/argo-workflows/dev/extras/secret-git-credentials.yaml > /dev/null

argo-workflows-storage-credentials:
	@if kubectl get namespace argo >/dev/null 2>&1; then \
		echo "Namespace argo already exists."; \
	else \
		echo "Namespace argo does not exist. Creating..."; \
		kubectl create namespace argo; \
		echo "Namespace argo has been created."; \
	fi
	echo "Creating argo argo-workflows storage secret ..."
	@kubectl --namespace argo \
		create secret \
		generic minio-creds \
			--from-literal=accesskey=${MINIO_USERNAME} \
			--from-literal=secretkey=${MINIO_PASSWORD} \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./configs/argo-workflows/dev/extras/secret-storage-credentials.yaml > /dev/null

argo-workflows: argo-workflows-sso-credentials argo-workflows-git-credentials argo-workflows-storage-credentials

argo-events-webhook-secret:
	@if kubectl get namespace argo-events >/dev/null 2>&1; then \
		echo "Namespace argo-events already exists."; \
	else \
		echo "Namespace argo-events does not exist. Creating..."; \
		kubectl create namespace argo-events; \
		echo "Namespace argo-events has been created."; \
	fi
	echo "Creating argo argo-events webhook secret ..."
	@kubectl --namespace argo-events \
		create secret generic webhook-secret-dt \
			--from-literal=secret=$(DT_WEBHOOK_SECRET) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./configs/argo-events/dev/extras/secret-webhook-dt.yaml > /dev/null

argo-events-github-token:
	@if kubectl get namespace argo-events >/dev/null 2>&1; then \
		echo "Namespace argo-events already exists."; \
	else \
		echo "Namespace argo-events does not exist. Creating..."; \
		kubectl create namespace argo-events; \
		echo "Namespace argo-events has been created."; \
	fi
	echo "Creating argo argo-events github token secret ..."
	@kubectl --namespace argo-events \
		create secret generic gh-token-dt \
			--from-literal=token=$(DT_GITHUB_TOKEN) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./configs/argo-events/dev/extras/secret-gh-token-dt.yaml > /dev/null

argo-events: argo-events-webhook-secret argo-events-github-token

minio-root:
	kubectl --namespace minio \
		create secret \
		generic minio-root \
			--from-literal=root-user=$(MINIO_ROOT_USER) \
			--from-literal=root-password=$(MINIO_ROOT_PASSWORD) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./configs/minio/dev/extras/secret-minio-root.yaml

minio-users:
	@./scripts/minio_users.sh "${MINIO_USERNAME}" "${MINIO_PASSWORD}"

minio: minio-root minio-users

commit-secrets:
	@echo "Committing newly created secrets..."
	git add configs
	git commit -m "Add valid secrets"
	git push

devops-app:
	@echo "Creating DevOps App..."
	kubectl apply -f devops-app.yaml

apply-configs:
	for dir in configs/*/dev/extras; do \
		echo "Applying config in $$dir"; \
		kubectl apply -f $$dir; \
	done

all: cluster initial-argocd-setup grafana-alloy sealed-secrets cert-manager cloudflare external-dns argo-cd argo-workflows argo-events minio commit-secrets devops-app
# Teardown 
destroy:
	kind delete cluster --name devops-toys
