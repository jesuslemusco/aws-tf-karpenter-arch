#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "EKS Karpenter Deployment Validation"
echo "======================================"
echo ""

# Function to check command exists
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is not installed"
        return 1
    fi
}

# Function to check Kubernetes resource
check_k8s_resource() {
    local resource=$1
    local namespace=$2
    local name=$3
    
    if kubectl get $resource -n $namespace $name &> /dev/null; then
        echo -e "${GREEN}✓${NC} $resource/$name exists in namespace $namespace"
        return 0
    else
        echo -e "${RED}✗${NC} $resource/$name not found in namespace $namespace"
        return 1
    fi
}

# Check prerequisites
echo "Checking prerequisites..."
echo "------------------------"
check_command terraform
check_command kubectl
check_command helm
check_command aws
echo ""

# Check AWS credentials
echo "Checking AWS configuration..."
echo "-----------------------------"
if aws sts get-caller-identity &> /dev/null; then
    echo -e "${GREEN}✓${NC} AWS credentials are configured"
    aws sts get-caller-identity --query "Account" --output text | xargs -I {} echo "  Account ID: {}"
    aws configure get region | xargs -I {} echo "  Region: {}"
else
    echo -e "${RED}✗${NC} AWS credentials not configured"
    exit 1
fi
echo ""

# Check cluster connectivity
echo "Checking EKS cluster connectivity..."
echo "-----------------------------------"
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓${NC} Connected to Kubernetes cluster"
    kubectl cluster-info | head -n 1
else
    echo -e "${RED}✗${NC} Cannot connect to Kubernetes cluster"
    echo "  Run: aws eks update-kubeconfig --region <region> --name <cluster-name>"
    exit 1
fi
echo ""

# Check nodes
echo "Checking cluster nodes..."
echo "------------------------"
node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$node_count" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $node_count nodes"
    kubectl get nodes -L kubernetes.io/arch -L karpenter.sh/nodepool --no-headers | while read line; do
        echo "  - $line"
    done
else
    echo -e "${YELLOW}⚠${NC} No nodes found (Karpenter will provision them on demand)"
fi
echo ""

# Check Karpenter installation
echo "Checking Karpenter installation..."
echo "---------------------------------"
check_k8s_resource deployment karpenter karpenter
check_k8s_resource serviceaccount karpenter karpenter

# Check if Karpenter pods are running
karpenter_pods=$(kubectl get pods -n karpenter -l app.kubernetes.io/name=karpenter --no-headers 2>/dev/null | wc -l)
if [ "$karpenter_pods" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Karpenter pods are running"
    kubectl get pods -n karpenter -l app.kubernetes.io/name=karpenter --no-headers | while read line; do
        echo "  - $line"
    done
else
    echo -e "${RED}✗${NC} No Karpenter pods found"
fi
echo ""

# Check Karpenter NodePools
echo "Checking Karpenter NodePools..."
echo "-------------------------------"
nodepools=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l)
if [ "$nodepools" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $nodepools NodePools"
    kubectl get nodepools --no-headers | while read line; do
        echo "  - $line"
    done
else
    echo -e "${RED}✗${NC} No NodePools found"
fi
echo ""

# Check EC2NodeClasses
echo "Checking EC2NodeClasses..."
echo "-------------------------"
ec2nodeclasses=$(kubectl get ec2nodeclasses --no-headers 2>/dev/null | wc -l)
if [ "$ec2nodeclasses" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $ec2nodeclasses EC2NodeClasses"
    kubectl get ec2nodeclasses --no-headers | while read line; do
        echo "  - $line"
    done
else
    echo -e "${RED}✗${NC} No EC2NodeClasses found"
fi
echo ""

# Check EKS addons
echo "Checking EKS addons..."
echo "---------------------"
for addon in vpc-cni kube-proxy coredns aws-ebs-csi-driver; do
    if kubectl get deployment -n kube-system -l k8s-app=$addon &> /dev/null || \
       kubectl get daemonset -n kube-system -l k8s-app=$addon &> /dev/null || \
       kubectl get deployment -n kube-system $addon &> /dev/null; then
        echo -e "${GREEN}✓${NC} $addon is installed"
    else
        echo -e "${YELLOW}⚠${NC} $addon might not be installed"
    fi
done
echo ""

# Check system node group
echo "Checking system node group..."
echo "----------------------------"
system_nodes=$(kubectl get nodes -l role=system --no-headers 2>/dev/null | wc -l)
if [ "$system_nodes" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $system_nodes system nodes"
else
    echo -e "${YELLOW}⚠${NC} No dedicated system nodes found"
fi
echo ""

# Architecture support check
echo "Checking multi-architecture support..."
echo "-------------------------------------"
x86_pool=$(kubectl get nodepool x86-pool --no-headers 2>/dev/null | wc -l)
graviton_pool=$(kubectl get nodepool graviton-pool --no-headers 2>/dev/null | wc -l)
spot_pool=$(kubectl get nodepool spot-pool --no-headers 2>/dev/null | wc -l)

if [ "$x86_pool" -eq 1 ]; then
    echo -e "${GREEN}✓${NC} x86 NodePool configured"
else
    echo -e "${RED}✗${NC} x86 NodePool not found"
fi

if [ "$graviton_pool" -eq 1 ]; then
    echo -e "${GREEN}✓${NC} Graviton (ARM64) NodePool configured"
else
    echo -e "${RED}✗${NC} Graviton NodePool not found"
fi

if [ "$spot_pool" -eq 1 ]; then
    echo -e "${GREEN}✓${NC} Spot NodePool configured"
else
    echo -e "${RED}✗${NC} Spot NodePool not found"
fi
echo ""

# Test node provisioning
echo "Testing node provisioning..."
echo "---------------------------"
echo "Creating a test pod to trigger node provisioning..."
cat <<EOF | kubectl apply -f - &> /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: karpenter-test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "30"]
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
EOF

echo "Waiting for pod to be scheduled..."
timeout=60
while [ $timeout -gt 0 ]; do
    pod_status=$(kubectl get pod karpenter-test-pod -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$pod_status" = "Running" ] || [ "$pod_status" = "Succeeded" ]; then
        echo -e "${GREEN}✓${NC} Node provisioning successful"
        kubectl delete pod karpenter-test-pod --ignore-not-found=true &> /dev/null
        break
    fi
    sleep 2
    timeout=$((timeout - 2))
done

if [ $timeout -le 0 ]; then
    echo -e "${YELLOW}⚠${NC} Node provisioning timeout (pod might still be pending)"
    kubectl delete pod karpenter-test-pod --ignore-not-found=true &> /dev/null
fi
echo ""

# Summary
echo "======================================"
echo "Validation Summary"
echo "======================================"
errors=0
warnings=0

# Count results
if [ "$karpenter_pods" -eq 0 ]; then
    errors=$((errors + 1))
fi
if [ "$nodepools" -eq 0 ]; then
    errors=$((errors + 1))
fi
if [ "$ec2nodeclasses" -eq 0 ]; then
    errors=$((errors + 1))
fi
if [ "$system_nodes" -eq 0 ]; then
    warnings=$((warnings + 1))
fi

if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo "Your EKS cluster with Karpenter is ready to use."
    echo ""
    echo "Next steps:"
    echo "1. Deploy example workloads: make deploy-all-examples"
    echo "2. Test autoscaling: make scale-test"
    echo "3. Monitor nodes: make nodes-watch"
elif [ $errors -eq 0 ]; then
    echo -e "${YELLOW}⚠ Validation completed with $warnings warning(s)${NC}"
    echo "The cluster is functional but review the warnings above."
else
    echo -e "${RED}✗ Validation failed with $errors error(s)${NC}"
    echo "Please review the errors above and ensure Terraform deployment completed successfully."
    exit 1
fi