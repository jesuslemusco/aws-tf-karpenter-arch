.PHONY: help init validate plan apply destroy clean test deploy-x86 deploy-graviton deploy-spot scale-test

# Variables
CLUSTER_NAME ?= eks-karpenter-cluster
REGION ?= us-west-2
TERRAFORM := terraform
# KUBECTL := kubectl
KUBECTL := minikube kubectl --

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

init: ## Initialize Terraform
	@echo "Initializing Terraform..."
	$(TERRAFORM) init -upgrade

validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	$(TERRAFORM) fmt -recursive
	$(TERRAFORM) validate

plan: validate ## Plan Terraform changes
	@echo "Planning Terraform changes..."
	$(TERRAFORM) plan -out=tfplan

apply: ## Apply Terraform changes
	@echo "Applying Terraform changes..."
	$(TERRAFORM) apply -auto-approve

destroy: ## Destroy all resources
	@echo "WARNING: This will destroy all resources!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		echo "Removing all deployments first..."; \
		$(KUBECTL) delete deployments --all --all-namespaces --ignore-not-found=true; \
		sleep 30; \
		echo "Destroying infrastructure..."; \
		$(TERRAFORM) destroy -auto-approve; \
	else \
		echo "Cancelled."; \
	fi

clean: ## Clean up local files
	@echo "Cleaning up local files..."
	rm -rf .terraform/
	rm -f .terraform.lock.hcl
	rm -f terraform.tfstate*
	rm -f tfplan
	rm -f kubeconfig

kubeconfig: ## Update kubeconfig
	@echo "Updating kubeconfig..."
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER_NAME)

nodes: ## Show cluster nodes
	@echo "Cluster nodes:"
	$(KUBECTL) get nodes -L karpenter.sh/nodepool -L node.kubernetes.io/instance-type -L karpenter.sh/capacity-type

pods: ## Show all pods
	@echo "All pods:"
	$(KUBECTL) get pods --all-namespaces

karpenter-logs: ## Show Karpenter logs
	@echo "Karpenter logs:"
	$(KUBECTL) logs -n karpenter -l app.kubernetes.io/name=karpenter -f

deploy-x86: ## Deploy x86 example application
	@echo "Deploying x86 example..."
	$(KUBECTL) apply -f examples/nginx-x86.yaml
	@echo "Waiting for deployment..."
	$(KUBECTL) wait --for=condition=available --timeout=300s deployment/nginx-x86

deploy-graviton: ## Deploy Graviton example application
	@echo "Deploying Graviton example..."
	$(KUBECTL) apply -f examples/nginx-graviton.yaml
	@echo "Waiting for deployment..."
	$(KUBECTL) wait --for=condition=available --timeout=300s deployment/nginx-graviton

deploy-spot: ## Deploy Spot instance example
	@echo "Deploying Spot instance example..."
	$(KUBECTL) apply -f examples/spot-batch-job.yaml

deploy-all-examples: deploy-x86 deploy-graviton deploy-spot ## Deploy all example applications

scale-test: ## Run autoscaling test
	@echo "Running autoscaling test..."
	$(KUBECTL) apply -f examples/autoscale-test.yaml
	@echo "Scaling to 50 replicas..."
	$(KUBECTL) scale deployment autoscale-test --replicas=50
	@echo "Watch nodes being provisioned with: make nodes-watch"

nodes-watch: ## Watch nodes being provisioned
	$(KUBECTL) get nodes -w -L karpenter.sh/nodepool -L node.kubernetes.io/instance-type

cleanup-examples: ## Remove all example deployments
	@echo "Removing example deployments..."
	$(KUBECTL) delete -f examples/ --ignore-not-found=true

test-connection: ## Test EKS cluster connection
	@echo "Testing cluster connection..."
	$(KUBECTL) cluster-info
	$(KUBECTL) get nodes

cost-report: ## Show cost optimization information
	@echo "=== Cost Optimization Report ==="
	@echo ""
	@echo "Current Nodes:"
	@$(KUBECTL) get nodes -L node.kubernetes.io/instance-type -L karpenter.sh/capacity-type
	@echo ""
	@echo "Spot vs On-Demand distribution:"
	@$(KUBECTL) get nodes -o json | jq -r '.items[] | select(.metadata.labels."karpenter.sh/capacity-type" != null) | .metadata.labels."karpenter.sh/capacity-type"' | sort | uniq -c
	@echo ""
	@echo "Architecture distribution:"
	@$(KUBECTL) get nodes -o json | jq -r '.items[] | .status.nodeInfo.architecture' | sort | uniq -c
	@echo ""
	@echo "Tips:"
	@echo "- Graviton instances: ~20% cheaper than x86"
	@echo "- Spot instances: up to 90% cheaper than On-Demand"
	@echo "- Check AWS Cost Explorer for actual savings"

benchmark: ## Run architecture comparison benchmark
	@echo "Deploying benchmark comparison..."
	$(KUBECTL) apply -f examples/architecture-comparison.yaml
	@echo "Waiting for pods to start..."
	sleep 30
	@echo "Running comparison script..."
	$(KUBECTL) create configmap benchmark-script --from-file=examples/architecture-comparison.yaml -o yaml --dry-run=client | $(KUBECTL) apply -f -
	@bash -c "$$($(KUBECTL) get configmap comparison-script -n arch-comparison -o jsonpath='{.data.compare\.sh}')"

validate-multi-arch: ## Validate multi-architecture support
	@echo "Checking multi-architecture support..."
	@echo ""
	@echo "Node Pools:"
	$(KUBECTL) get nodepools
	@echo ""
	@echo "EC2 Node Classes:"
	$(KUBECTL) get ec2nodeclasses
	@echo ""
	@echo "Available architectures:"
	$(KUBECTL) get nodes -o json | jq -r '.items[] | .status.nodeInfo.architecture' | sort | uniq

monitor: ## Open monitoring dashboard
	@echo "Opening K9s dashboard (install with: brew install k9s)..."
	@which k9s > /dev/null 2>&1 && k9s || echo "K9s not installed. Install with: brew install k9s"

ssh-node: ## SSH into a node (requires node name as NODE=<name>)
	@if [ -z "$(NODE)" ]; then \
		echo "Usage: make ssh-node NODE=<node-name>"; \
		echo "Available nodes:"; \
		$(KUBECTL) get nodes -o name | cut -d/ -f2; \
	else \
		echo "Connecting to $(NODE)..."; \
		aws ssm start-session --target $$($(KUBECTL) get node $(NODE) -o jsonpath='{.spec.providerID}' | cut -d'/' -f5) --region $(REGION); \
	fi

versions: ## Show component versions
	@echo "Component versions:"
	@echo "==================="
	@echo "Terraform: $$($(TERRAFORM) version -json | jq -r .terraform_version)"
	@echo "kubectl: $$($(KUBECTL) version --client -o json | jq -r .clientVersion.gitVersion)"
	@echo "AWS CLI: $$(aws --version)"
	@echo "Helm: $$(helm version --short)"
	@echo ""
	@echo "Cluster versions:"
	@echo "================="
	@$(KUBECTL) version -o json | jq -r '"Kubernetes: " + .serverVersion.gitVersion' 2>/dev/null || echo "Not connected to cluster"
	@$(KUBECTL) get deployment -n karpenter karpenter -o json | jq -r '"Karpenter: " + .spec.template.spec.containers[0].image' | cut -d: -f2 2>/dev/null || echo "Karpenter not installed"

quick-start: init apply kubeconfig test-connection ## Complete quick start deployment
	@echo "✅ Deployment complete!"
	@echo "Run 'make deploy-all-examples' to deploy example applications"
