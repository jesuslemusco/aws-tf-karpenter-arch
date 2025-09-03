# Troubleshooting Guide

This guide helps resolve common issues with the EKS Karpenter deployment.

## Table of Contents
- [Terraform Issues](#terraform-issues)
- [EKS Cluster Issues](#eks-cluster-issues)
- [Karpenter Issues](#karpenter-issues)
- [Node Provisioning Issues](#node-provisioning-issues)
- [Cost Issues](#cost-issues)
- [Debugging Commands](#debugging-commands)

## Terraform Issues

### Error: Provider initialization failed

**Symptoms:**
```
Error: Failed to query available provider packages
```

**Solution:**
```bash
# Clean Terraform cache
rm -rf .terraform/
rm .terraform.lock.hcl

# Re-initialize
terraform init -upgrade
```

### Error: Insufficient IAM permissions

**Symptoms:**
```
Error: creating EKS Cluster: AccessDeniedException
```

**Solution:**
Ensure your AWS IAM user/role has the following permissions:
- `eks:*`
- `ec2:*`
- `iam:*`
- `autoscaling:*`

Or attach the `AdministratorAccess` policy for deployment.

### Error: VPC already exists

**Symptoms:**
```
Error: creating VPC: VpcLimitExceeded
```

**Solution:**
1. Check existing VPCs: `aws ec2 describe-vpcs --region us-west-2`
2. Either delete unused VPCs or use a different CIDR:
   ```hcl
   vpc_cidr = "10.1.0.0/16"  # in terraform.tfvars
   ```

## EKS Cluster Issues

### Cannot connect to cluster

**Symptoms:**
```
Unable to connect to the server: dial tcp: lookup <cluster-endpoint>
```

**Solution:**
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name eks-karpenter-cluster

# Verify connection
kubectl cluster-info
```

### Nodes not joining cluster

**Symptoms:**
Nodes created but not appearing in `kubectl get nodes`

**Solution:**
1. Check node security groups:
   ```bash
   aws ec2 describe-security-groups --filters "Name=tag:karpenter.sh/discovery,Values=<cluster-name>"
   ```

2. Verify IAM role permissions:
   ```bash
   kubectl describe configmap -n kube-system aws-auth
   ```

3. Check node logs:
   ```bash
   # SSH to node using Session Manager
   aws ssm start-session --target <instance-id>
   
   # Check kubelet logs
   sudo journalctl -u kubelet -f
   ```

## Karpenter Issues

### Karpenter not provisioning nodes

**Symptoms:**
Pods remain in Pending state, no new nodes created

**Solution:**

1. **Check Karpenter logs:**
   ```bash
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
   ```

2. **Verify NodePools exist:**
   ```bash
   kubectl get nodepools
   kubectl describe nodepool x86-pool
   ```

3. **Check EC2NodeClasses:**
   ```bash
   kubectl get ec2nodeclasses
   kubectl describe ec2nodeclass x86-node-class
   ```

4. **Verify IAM permissions:**
   ```bash
   # Check Karpenter service account
   kubectl get sa -n karpenter karpenter -o yaml
   
   # Verify IRSA annotation
   kubectl get sa -n karpenter karpenter -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
   ```

5. **Check subnet tags:**
   ```bash
   aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=<cluster-name>"
   ```

### Karpenter provisioning wrong instance types

**Symptoms:**
Getting instances different from those specified in NodePool

**Solution:**
1. Review NodePool requirements:
   ```bash
   kubectl get nodepool x86-pool -o yaml | grep -A 20 requirements
   ```

2. Check for conflicting taints/tolerations:
   ```bash
   kubectl describe pod <pod-name>
   ```

3. Verify instance availability in region:
   ```bash
   aws ec2 describe-instance-type-offerings --region us-west-2 --filters "Name=instance-type,Values=m6i.large"
   ```

### Spot instances being interrupted frequently

**Symptoms:**
Nodes being terminated within minutes/hours

**Solution:**

1. **Increase instance diversity:**
   ```yaml
   # Add more instance types to the NodePool
   - m6i.large
   - m6i.xlarge
   - m5.large
   - m5a.large
   - m5n.large
   ```

2. **Check Spot pricing history:**
   ```bash
   aws ec2 describe-spot-price-history \
     --instance-types m6i.large \
     --product-descriptions "Linux/UNIX" \
     --max-results 10
   ```

3. **Use multiple availability zones:**
   Ensure subnets span multiple AZs

4. **Implement pod disruption budgets:**
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: app-pdb
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: myapp
   ```

## Node Provisioning Issues

### Nodes not scaling down

**Symptoms:**
Empty or underutilized nodes not being removed

**Solution:**

1. **Check consolidation settings:**
   ```bash
   kubectl get nodepool x86-pool -o yaml | grep -A 5 disruption
   ```

2. **Look for pods preventing deletion:**
   ```bash
   kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name>
   ```

3. **Check for PodDisruptionBudgets:**
   ```bash
   kubectl get pdb --all-namespaces
   ```

4. **Verify no local storage:**
   ```bash
   kubectl get pods --all-namespaces -o json | jq '.items[] | select(.spec.volumes[]?.emptyDir != null) | .metadata.name'
   ```

### ARM64/Graviton nodes not working

**Symptoms:**
Pods fail to run on Graviton instances

**Solution:**

1. **Verify image supports ARM64:**
   ```bash
   docker manifest inspect <image:tag> | jq '.manifests[].platform'
   ```

2. **Check node selector:**
   ```yaml
   nodeSelector:
     kubernetes.io/arch: arm64
   ```

3. **Build multi-arch images:**
   ```dockerfile
   # Use buildx for multi-arch
   docker buildx build --platform linux/amd64,linux/arm64 -t myapp:latest .
   ```

## Cost Issues

### Higher than expected costs

**Symptoms:**
AWS bill exceeds estimates

**Solution:**

1. **Check instance distribution:**
   ```bash
   # Run cost analysis
   ./scripts/cost-optimization.sh
   ```

2. **Verify Spot usage:**
   ```bash
   kubectl get nodes -L karpenter.sh/capacity-type
   ```

3. **Enable consolidation:**
   ```yaml
   disruption:
     consolidationPolicy: WhenEmptyOrUnderutilized
     consolidateAfter: 1m
   ```

4. **Review instance types:**
   - Use latest generation (m7g vs m6g)
   - Prefer Graviton where possible
   - Right-size based on actual usage

## Debugging Commands

### Essential debugging commands

```bash
# Cluster status
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods --all-namespaces

# Karpenter status
kubectl get nodepools
kubectl get ec2nodeclasses
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Node information
kubectl describe node <node-name>
kubectl get nodes -L karpenter.sh/nodepool -L node.kubernetes.io/instance-type

# Pod scheduling issues
kubectl describe pod <pod-name>
kubectl get events --sort-by='.lastTimestamp'

# Resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# AWS resources
aws ec2 describe-instances --filters "Name=tag:karpenter.sh/discovery,Values=<cluster-name>"
aws eks describe-cluster --name <cluster-name>
```

### Enable verbose logging

For Karpenter:
```bash
kubectl set env -n karpenter deployment/karpenter KARPENTER_LOG_LEVEL=debug
```

### Check AWS service quotas

```bash
# EC2 limits
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A

# Check current usage
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceType]' --output text | sort | uniq -c
```

## Common Error Messages

### "InsufficientInstanceCapacity"
- **Cause:** AWS doesn't have capacity for requested instance type
- **Solution:** Add more instance types to NodePool

### "SpotInstanceTermination"
- **Cause:** Spot instance reclaimed by AWS
- **Solution:** Normal behavior, Karpenter will provision replacement

### "NodeNotReady"
- **Cause:** Node failed to initialize properly
- **Solution:** Check kubelet logs on the node

### "FailedScheduling"
- **Cause:** No nodes match pod requirements
- **Solution:** Review nodeSelector, taints, and resource requests

## Getting Help

If issues persist:

1. **Collect logs:**
   ```bash
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter > karpenter.log
   kubectl get events --all-namespaces > events.log
   kubectl describe nodes > nodes.log
   ```

2. **Check AWS CloudTrail** for API errors

3. **Review Karpenter documentation:** https://karpenter.sh/

4. **Check EKS best practices:** https://aws.github.io/aws-eks-best-practices/

5. **Open an issue** in this repository with:
   - Description of the issue
   - Steps to reproduce
   - Relevant logs
   - Terraform version
   - AWS region