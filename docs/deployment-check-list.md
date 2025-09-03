# EKS Karpenter Deployment Checklist

Use this checklist to ensure a successful deployment of your EKS cluster with Karpenter.

## Pre-Deployment

### Prerequisites
- [ ] AWS CLI installed and configured
  ```bash
  aws --version
  aws sts get-caller-identity
  ```

- [ ] Terraform installed (>= 1.13)
  ```bash
  terraform version
  ```

- [ ] kubectl installed (>= 1.28)
  ```bash
  kubectl version --client
  ```

- [ ] Helm installed (>= 2.11)
  ```bash
  helm version
  ```

### AWS Account Setup
- [ ] Sufficient IAM permissions (AdministratorAccess or equivalent)
- [ ] Service quotas checked:
  - [ ] VPCs (default: 5)
  - [ ] Elastic IPs (default: 5)
  - [ ] EC2 instances (varies by type)
  - [ ] EKS clusters (default: 100)

- [ ] Budget alerts configured in AWS Billing
- [ ] Region selected and configured
  ```bash
  aws configure get region
  ```

## Deployment Steps

### 1. Repository Setup
- [ ] Clone repository
  ```bash
  git clone <repository-url>
  cd eks-karpenter-terraform
  ```

- [ ] Create terraform.tfvars from template
  ```bash
  cp terraform.tfvars.example terraform.tfvars
  ```

- [ ] Edit terraform.tfvars with your values:
  - [ ] cluster_name
  - [ ] region
  - [ ] environment
  - [ ] vpc_cidr (ensure no conflicts)

### 2. Terraform Deployment
- [ ] Initialize Terraform
  ```bash
  terraform init
  ```

- [ ] Validate configuration
  ```bash
  terraform validate
  ```

- [ ] Review planned changes
  ```bash
  terraform plan
  ```

- [ ] Apply configuration
  ```bash
  terraform apply
  ```

- [ ] Save Terraform outputs
  ```bash
  terraform output > outputs.txt
  ```

### 3. Cluster Access Configuration
- [ ] Update kubeconfig
  ```bash
  aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name)
  ```

- [ ] Verify cluster access
  ```bash
  kubectl cluster-info
  kubectl get nodes
  ```

### 4. Validate Karpenter Installation
- [ ] Check Karpenter pods
  ```bash
  kubectl get pods -n karpenter
  ```

- [ ] Verify NodePools
  ```bash
  kubectl get nodepools
  # Should see: x86-pool, graviton-pool, spot-pool
  ```

- [ ] Verify EC2NodeClasses
  ```bash
  kubectl get ec2nodeclasses
  # Should see: x86-node-class, graviton-node-class
  ```

### 5. Test Node Provisioning
- [ ] Deploy test pod
  ```bash
  kubectl apply -f examples/autoscale-test.yaml
  ```

- [ ] Verify node provisioning
  ```bash
  kubectl get nodes -w
  ```

- [ ] Check Karpenter logs
  ```bash
  kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
  ```

## Post-Deployment Validation

### Functionality Tests
- [ ] x86 workload deployment
  ```bash
  kubectl apply -f examples/nginx-x86.yaml
  kubectl wait --for=condition=available --timeout=300s deployment/nginx-x86
  ```

- [ ] Graviton workload deployment
  ```bash
  kubectl apply -f examples/nginx-graviton.yaml
  kubectl wait --for=condition=available --timeout=300s deployment/nginx-graviton
  ```

- [ ] Spot instance deployment
  ```bash
  kubectl apply -f examples/spot-batch-job.yaml
  ```

### Monitoring Setup
- [ ] Deploy metrics server
  ```bash
  kubectl apply -f examples/monitoring.yaml
  ```

- [ ] Verify metrics availability
  ```bash
  kubectl top nodes
  kubectl top pods --all-namespaces
  ```

### Security Validation
- [ ] IMDS v2 enforced
  ```bash
  kubectl get ec2nodeclasses -o yaml | grep httpTokens
  # Should show: httpTokens: required
  ```

- [ ] IRSA configured
  ```bash
  kubectl get sa -n karpenter karpenter -o yaml | grep role-arn
  ```

- [ ] Security groups properly configured
  ```bash
  aws ec2 describe-security-groups --filters "Name=tag:karpenter.sh/discovery,Values=$(terraform output -raw cluster_name)"
  ```

## Cost Optimization Checks

- [ ] Run cost analysis
  ```bash
  ./scripts/cost-optimization.sh
  ```

- [ ] Verify Spot instances are being used
  ```bash
  kubectl get nodes -L karpenter.sh/capacity-type | grep spot
  ```

- [ ] Check Graviton adoption
  ```bash
  kubectl get nodes -L kubernetes.io/arch | grep arm64
  ```

- [ ] Consolidation enabled
  ```bash
  kubectl get nodepool x86-pool -o yaml | grep consolidationPolicy
  # Should show: consolidationPolicy: WhenEmptyOrUnderutilized
  ```

## Documentation and Handover

- [ ] Document cluster details:
  - [ ] Cluster name
  - [ ] Region
  - [ ] VPC CIDR
  - [ ] NodePool configurations
  - [ ] Instance types used

- [ ] Create runbooks for:
  - [ ] Scaling procedures
  - [ ] Troubleshooting guides
  - [ ] Disaster recovery

- [ ] Set up monitoring dashboards:
  - [ ] CloudWatch dashboard
  - [ ] Cost Explorer views
  - [ ] Kubernetes dashboard

- [ ] Configure alerts:
  - [ ] Cost threshold alerts
  - [ ] Node scaling alerts
  - [ ] Application health checks

## Developer Enablement

- [ ] Create developer guide with:
  - [ ] How to deploy to x86 instances
  - [ ] How to deploy to Graviton instances
  - [ ] How to use Spot instances
  - [ ] Resource request/limit guidelines

- [ ] Provide example manifests:
  - [ ] Multi-architecture deployments
  - [ ] Spot-tolerant workloads
  - [ ] Production configurations

- [ ] Train team on:
  - [ ] Karpenter concepts
  - [ ] Cost optimization strategies
  - [ ] Troubleshooting procedures

## Backup and Recovery

- [ ] Document state backup:
  ```bash
  terraform state pull > terraform.tfstate.backup
  ```

- [ ] Test disaster recovery:
  - [ ] Cluster recreation procedure
  - [ ] Data restoration process
  - [ ] Application redeployment

- [ ] Create backup of configurations:
  ```bash
  kubectl get all --all-namespaces -o yaml > cluster-backup.yaml
  kubectl get nodepools,ec2nodeclasses -o yaml > karpenter-backup.yaml
  ```

## Final Validation

- [ ] Run complete validation script
  ```bash
  ./scripts/validate-deployment.sh
  ```

- [ ] Performance benchmark
  ```bash
  kubectl apply -f examples/architecture-comparison.yaml
  ```

- [ ] Cost report generation
  ```bash
  make cost-report
  ```

- [ ] Security scan
  - [ ] Review IAM policies
  - [ ] Check network policies
  - [ ] Validate encryption settings

## Sign-off

- [ ] Technical validation complete
- [ ] Documentation complete
- [ ] Handover complete
- [ ] Team training complete
- [ ] Monitoring and alerting configured
- [ ] Backup and recovery tested

## Notes

Add any deployment-specific notes here:

```
Date: _______________
Deployed by: _______________
Cluster Name: _______________
AWS Account ID: _______________
Region: _______________
Environment: _______________

Additional Notes:
_________________________________
_________________________________
_________________________________
```

## Quick Reference

### Useful Commands
```bash
# View all resources
make nodes
make pods

# Deploy examples
make deploy-all-examples

# Run autoscaling test
make scale-test

# View Karpenter logs
make karpenter-logs

# Cost analysis
make cost-report

# Cleanup
make destroy
```

### Support Contacts
- AWS Support: [AWS Support Center](https://console.aws.amazon.com/support/)
- Karpenter Docs: [karpenter.sh](https://karpenter.sh/)
- EKS Best Practices: [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)

## Rollback Procedure

If issues occur:
1. Keep current terraform state: `terraform state pull > emergency-backup.tfstate`
2. Check last working version: `git log --oneline`
3. Restore previous version: `git checkout <commit-hash>`
4. Re-apply configuration: `terraform apply`
5. Document incident and resolution