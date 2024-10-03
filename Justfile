# Load environment variables from the .env file
set dotenv-load := true

# Variables
ENV := ".env"
OS := `uname -s`

# Create a local Kubernetes cluster
cluster:
    @echo "Creating local Kubernetes cluster"
    kind create cluster --config ./kind/cluster-local.yaml

initial-argocd-setup:
    @echo "Installing initial version of Argo CD ..."
    helm repo add argo https://argoproj.github.io/argo-helm --force-update
    helm upgrade --install \
        argocd argo/argo-cd \
        --namespace argocd \
        --create-namespace \
        --wait
    kubectl apply -n argocd -f ./bootstrap/projects.yaml

grafana-alloy:
    @echo "Installing Grafana Alloy ..."
    kubectl apply -f ./applicationsets/grafana-alloy.yaml
    sleep 60

sealed-secrets:
    @echo "Installing Sealed Secrets ..."
    kubectl apply -f ./applicationsets/sealed-secrets.yaml
    sleep 120

cert-manager:
    @if kubectl get namespace cert-manager > /dev/null 2>&1; then
        echo "Namespace cert-manager already exists."
    else
        echo "Namespace cert-manager does not exist. Creating..."
        kubectl create namespace cert-manager
        echo "Namespace cert-manager has been created."
    end
    echo "Creating Certificate Authority (CA)"
    openssl genrsa -out ca.key 4096
    openssl req -new -x509 -sha256 -days 3650 \
        -key ca.key \
        -out ca.crt \
        -subj "/CN={{CN}}/emailAddress={{CERT_EMAIL}}/C={{C}}/ST={{ST}}/L={{L}}/O={{O}}/OU={{OU}}"
    echo "Creating secrets for Cert Manager..."
    kubectl --namespace cert-manager \
        create secret generic devopslabolatory-org-ca \
        --from-file=tls.key=ca.key \
        --from-file=tls.crt=ca.crt \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets -oyaml | \
        kubectl patch -f - \
        -p '{"spec": {"template": {"metadata": {"annotations": {"argocd.argoproj.io/sync-wave":"0"}}}}}' \
        --dry-run=client \
        --type=merge \
        --local -oyaml > ./configs/cert-manager/local/extras/ca-secret.yaml
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt

cloudflare-tunnel:
    @if [ ! -f ~/.cloudflared/cert.pem ]; then
        echo "The cert.pem file does not exist. Running cloudflared tunnel login ..."
        cloudflared tunnel login
        cloudflared tunnel create devopslabolatory
    else
        echo "The cert.pem file already exists."
    end
    @if kubectl get namespace cloudflare > /dev/null 2>&1; then
        echo "Namespace cloudflare already exists."
    else
        echo "Namespace cloudflare does not exist. Creating..."
        kubectl create namespace cloudflare
        echo "Namespace cloudflare has been created."
    end
    echo "Creating secrets ..."
    kubectl --namespace cloudflare \
        create secret generic tunnel-credentials \
        --from-file=credentials.json={{HOME}}/.cloudflared/{{CLOUDFLARE_TUNNEL_ID}}.json \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets | \
        tee ./configs/cloudflare-tunnel/local/extras/secret-tunnel-credentials.yaml
    kubectl --namespace cloudflare \
        create secret generic cloudflare-api-key \
        --from-literal=apiKey={{CLOUDFLARE_API_KEY}} \
        --from-literal=email={{CLOUDFLARE_EMAIL}} \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets | \
        tee ./configs/cloudflare-tunnel/local/extras/secret-api-key.yaml

external-dns:
    @if kubectl get namespace external-dns > /dev/null 2>&1; then
        echo "Namespace external-dns already exists."
    else
        echo "Namespace external-dns does not exist. Creating..."
        kubectl create namespace external-dns
        echo "Namespace external-dns has been created."
    end
    echo "Creating secrets for External DNS..."
    kubectl --namespace external-dns \
        create secret generic cloudflare-api-key \
        --from-literal=cloudflare_api_key={{CLOUDFLARE_API_KEY}} \
        --from-literal=email={{CLOUDFLARE_EMAIL}} \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets | \
        tee ./configs/external-dns/local/extras/secret-api-key.yaml > /dev/null

argo-cd:
    echo "Creating secrets for Argo CD..."
    kubectl --namespace argocd \
        create secret generic argocd-google-oauth-client \
        --from-literal=client_id={{GOOGLE_CLIENT_ID}} \
        --from-literal=client_secret={{GOOGLE_CLIENT_SECRET}} \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets | \
        kubectl patch -f - \
        -p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
        --type=merge \
        --local -oyaml > ./configs/argo-cd/local/extras/argocd-google-oauth-client.yaml
    kubectl --namespace argocd \
        create secret generic argocd-google-domain-wide-sa-json \
        --from-file=googleAuth.json=devopslaboratory-f90072620e7c.json \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets -oyaml | \
        kubectl patch -f - \
        -p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
        --type=merge \
        --local -oyaml > ./configs/argo-cd/local/extras/argocd-google-domain-wide-sa-json.yaml
    kubectl --namespace argocd \
        create secret generic argo-workflows-sso \
        --from-literal=client-id={{ARGO_WORKFLOWS_CLIENT_ID}} \
        --from-literal=client-secret={{ARGO_WORKFLOWS_CLIENT_SECRET}} \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets | \
        kubectl patch -f - \
        -p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
        --type=merge \
        --local -oyaml > ./configs/argo-cd/local/extras/argo-workflows-sso.yaml

argo-workflows:
    @if kubectl get namespace argo > /dev/null 2>&1; then
        echo "Namespace argo already exists."
    else
        echo "Namespace argo does not exist. Creating..."
        kubectl create namespace argo
        echo "Namespace argo has been created."
    end
    echo "Creating secrets for Argo Workflows..."
    kubectl --namespace argo \
        create secret generic argo-workflows-sso \
        --from-literal=client-id={{ARGO_WORKFLOWS_CLIENT_ID}} \
        --from-literal=client-secret={{ARGO_WORKFLOWS_CLIENT_SECRET}} \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets | \
        tee ./configs/argo-workflows/local/extras/argo-workflows-sso.yaml > /dev/null

argo-events:
    @if kubectl get namespace argo-events > /dev/null 2>&1; then
        echo "Namespace argo-events already exists."
    else
        echo "Namespace argo-events does not exist. Creating..."
        kubectl create namespace argo-events
        echo "Namespace argo-events has been created."
    end
    echo "Creating secrets for Argo Events..."
    # Webhook secret for fpi
    kubectl --namespace argo-events \
        create secret generic webhook-secret-fpi \
        --from-literal=secret={{FPI_WEBHOOK_SECRET}} \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets | \
        tee ./configs/argo-events/local/extras/secret-webhook-fpi.yaml
    # GH token for fpi
    kubectl --namespace argo-events \
        create secret generic gh-token-fpi \
        --from-literal=secret={{FPI_GITHUB_TOKEN}} \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets | \
        tee ./configs/argo-events/local/extras/secret-gh-token-fpi.yaml
    # Webhook secret for dt
    kubectl --namespace argo-events \
        create secret generic webhook-secret-dt \
        --from-literal=secret={{DT_WEBHOOK_SECRET}} \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets | \
        tee ./configs/argo-events/local/extras/secret-webhook-dt.yaml
    # GH token for dt
    kubectl --namespace argo-events \
        create secret generic gh-token-fpi \
        --from-literal=secret={{DT_GITHUB_TOKEN}} \
        --output json \
        --dry-run=client | \
        kubeseal --format yaml \
        --controller-name=sealed-secrets \
        --controller-namespace=sealed-secrets | \
        tee ./configs/argo-events/local/extras/secret-gh-token-dt.yaml







# @kubectl --namespace argocd \
	# 	create secret \
	# 	generic argocd-google-domain-wide-sa-json \
	# 	--from-file=googleAuth.json=devopslaboratory-f90072620e7c.json \
	# 	--output json \
	# 	--dry-run=client | \
	# 	kubeseal --format yaml \
	# 	--controller-name=sealed-secrets \
	# 	--controller-namespace=sealed-secrets -oyaml - | \
	# 	kubectl patch -f - \
	# 	-p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
	# 	--dry-run=client \
	# 	--type=merge \
	# 	--local -oyaml > ./configs/argo-cd/local/extras/argocd-google-domain-wide-sa-json.yaml
	# @kubectl --namespace argocd \
	# 	create secret \
	# 	generic argo-workflows-sso \
	# 	--from-literal=client-id=$(ARGO_WORKFLOWS_CLIENT_ID) \
	# 	--from-literal=client-secret=$(ARGO_WORKFLOWS_CLIENT_SECRET) \
	# 	--output json \
	# 	--dry-run=client | \
	# 	kubeseal --format yaml \
	# 	--controller-name=sealed-secrets \
	# 	--controller-namespace=sealed-secrets | \
	# 	kubectl patch -f - \
	# 	-p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
	# 	--type=merge \
	# 	--local -oyaml > ./configs/argo-cd/local/extras/argo-workflows-sso.yaml