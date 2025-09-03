# AWS EKS Cluster with Karpenter Autoscaling

This repository contains Terraform code to deploy a production-ready AWS EKS cluster with Karpenter autoscaling, supporting both x86 and ARM64 (Graviton) instances with Spot capacity.

## Architecture Overview

- **EKS Cluster**: Latest available version (1.31)
- **VPC**: Dedicated VPC with public and private subnets across 2 AZs
- **Karpenter**: v1.0.0 with node pools for x86 and ARM64 instances
- **Instance Types**: Mix of On-Demand and Spot instances for cost optimization
- **Graviton Support**: ARM64-based AWS Graviton instances for better price/performance

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.13
3. **kubectl** >= 1.28
4. **helm** >= 2.11

## Version Requirements

This project uses the following provider versions:

- **AWS Provider**: ~> 6.0
- **Kubernetes Provider**: ~> 2.23
- **Helm Provider**: ~> 2.11
- **Kubectl Provider**: ~> 1.14
- **EKS Module**: ~> 21.1
- **VPC Module**: ~> 6.0
- **IAM Module**: ~> 6.0

## Quick Start

### 1. Clone and Initialize

```bash
# Clone this repository
git clone <repository-url>
cd eks-karpenter-terraform

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Copy the example variables file and adjust as needed:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
cluster_name = "my-eks-cluster"
region       = "us-west-2"
environment  = "dev"
```

### 3. Deploy Infrastructure

```bash
# Plan the deployment
terraform plan

# Apply the configuration
terraform apply -auto-approve
```

This will create:
- VPC with public/private subnets
- EKS cluster with managed node group for system workloads
- IAM roles and policies
- Karpenter controller
- Node pools for x86 and ARM64 instances

### 4. Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name)

# Verify connection
kubectl get nodes
```

## Using the Cluster

### Deploy to x86 Instances

To deploy a workload on x86 instances:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-x86
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-x86
  template:
    metadata:
      labels:
        app: nginx-x86
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
        karpenter.sh/nodepool: x86-pool
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
```

Apply with: `kubectl apply -f examples/nginx-x86.yaml`

### Deploy to Graviton (ARM64) Instances

To deploy a workload on Graviton instances:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-graviton
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-graviton
  template:
    metadata:
      labels:
        app: nginx-graviton
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
        karpenter.sh/nodepool: graviton-pool
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
```

Apply with: `kubectl apply -f examples/nginx-graviton.yaml`

### Deploy with Spot Instances Preference

To prefer Spot instances for cost savings:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-job
spec:
  replicas: 5
  selector:
    matchLabels:
      app: batch-job
  template:
    metadata:
      labels:
        app: batch-job
    spec:
      nodeSelector:
        karpenter.sh/nodepool: spot-pool
      tolerations:
      - key: spot
        operator: Equal
        value: "true"
        effect: NoSchedule
      containers:
      - name: worker
        image: busybox
        command: ["sleep", "3600"]
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
```

## Karpenter Node Pools

The setup includes three Karpenter node pools:

### 1. x86-pool
- **Instance Types**: m6i, m5, c5, c6i families
- **Capacity Type**: On-Demand and Spot
- **Use Case**: General x86 workloads

### 2. graviton-pool
- **Instance Types**: m7g, m6g, c7g, c6g families (ARM64)
- **Capacity Type**: On-Demand and Spot
- **Use Case**: ARM64-compatible workloads with better price/performance

### 3. spot-pool
- **Instance Types**: Mixed x86 and ARM64
- **Capacity Type**: Spot only
- **Use Case**: Fault-tolerant, batch workloads

## Monitoring Karpenter

Check Karpenter logs:
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

View provisioned nodes:
```bash
kubectl get nodes -L karpenter.sh/nodepool -L node.kubernetes.io/instance-type -L karpenter.sh/capacity-type
```

View Karpenter node pools:
```bash
kubectl get nodepools
kubectl get ec2nodeclasses
```

## Cost Optimization Tips

1. **Use Graviton instances** where possible - up to 40% better price/performance
2. **Enable Spot instances** for non-critical workloads - up to 90% cost savings
3. **Set appropriate resource requests** to ensure efficient bin-packing
4. **Configure disruption budgets** for production workloads

## Testing Autoscaling

Deploy a test application to trigger autoscaling:

```bash
# Deploy a scalable application
kubectl apply -f examples/autoscale-test.yaml

# Scale up to trigger node provisioning
kubectl scale deployment autoscale-test --replicas=50

# Watch nodes being provisioned
kubectl get nodes -w

# Scale down
kubectl scale deployment autoscale-test --replicas=1
```

## Architecture Decisions

### Why Karpenter over Cluster Autoscaler?
- **Faster scaling**: Provisions nodes in <30 seconds vs 2-10 minutes
- **Better bin-packing**: Groups pods efficiently
- **Cost optimization**: Automatic right-sizing and consolidation
- **Flexibility**: No need to manage Auto Scaling Groups

### Why Graviton?
- **Performance**: Up to 40% better price-performance
- **Cost**: Generally 20% cheaper than x86 equivalents
- **Sustainability**: Up to 60% better energy efficiency

### Instance Selection Strategy
- **Diverse instance types**: Reduces chance of capacity issues
- **Spot with fallback**: Prioritizes Spot but falls back to On-Demand
- **Latest generation**: Focuses on current-gen instances for best performance

## Cleanup

To destroy all resources:

```bash
# Remove all Karpenter-provisioned nodes first
kubectl delete deployments --all

# Wait for nodes to be terminated
kubectl get nodes -w

# Destroy infrastructure
terraform destroy -auto-approve
```

## Troubleshooting

### Nodes not provisioning
1. Check Karpenter logs: `kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter`
2. Verify IAM permissions: `kubectl describe configmap -n karpenter karpenter-global-settings`
3. Check EC2 limits in your AWS account

### Pods not scheduling on Graviton
1. Ensure image supports ARM64: `docker manifest inspect <image>`
2. Check node selector: `kubernetes.io/arch: arm64`
3. Verify Graviton node pool is active: `kubectl get ec2nodeclasses`

### Spot instances being interrupted frequently
1. Diversify instance types in the node pool
2. Consider using Spot placement scores
3. Set up proper pod disruption budgets

## Security Considerations

- **IRSA**: IAM Roles for Service Accounts enabled for secure AWS API access
- **Private Endpoints**: EKS API endpoint can be made private
- **Network Policies**: Implement Kubernetes network policies
- **IMDS v2**: Instance metadata service v2 enforced
- **Encryption**: EKS secrets encrypted at rest using AWS KMS

## Documentation

- [Deployment Checklist](docs/deployment-check-list.md) - Step-by-step guide for production deployments
- [Troubleshooting Guide](docs/troubleshooting.md) - Common issues and solutions

## Additional Resources

- [Karpenter Documentation](https://karpenter.sh/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Graviton Getting Started](https://github.com/aws/aws-graviton-getting-started)
- [Spot Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)

## Support

For issues or questions, please open an issue in this repository.