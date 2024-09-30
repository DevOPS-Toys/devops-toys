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
		-f configs/argo-cd/local/values.yaml \
		--wait
	kubectl apply -n argocd -f bootstrap/projects.yaml
	
all: cluster

# Teardown 
destroy:
	kind delete cluster --name devops-toys
