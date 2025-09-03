# Project Structure

```
eks-karpenter-terraform/
│
├── README.md                          # Main documentation
├── DEPLOYMENT-CHECKLIST.md            # Step-by-step deployment guide
├── TROUBLESHOOTING.md                 # Common issues and solutions
├── PROJECT-STRUCTURE.md               # This file
│
├── Makefile                           # Automation commands
├── .gitignore                         # Git ignore patterns
│
├── terraform.tfvars.example           # Example configuration
├── main.tf                            # Main Terraform configuration
├── variables.tf                       # Terraform variable definitions
├── outputs.tf                         # Terraform outputs
│
├── examples/                          # Example Kubernetes manifests
│   ├── nginx-x86.yaml                # x86 deployment example
│   ├── nginx-graviton.yaml           # ARM64/Graviton deployment
│   ├── spot-batch-job.yaml           # Spot instance workload
│   ├── autoscale-test.yaml           # Autoscaling test deployment
│   ├── architecture-comparison.yaml   # Performance comparison
│   └── monitoring.yaml                # Monitoring setup
│
└── scripts/                           # Utility scripts
    ├── validate-deployment.sh         # Deployment validation
    └── cost-optimization.sh           # Cost analysis tool
```

## File Descriptions

### Root Files

**README.md**
- Complete documentation for the project
- Architecture overview
- Quick start guide
- Usage examples
- Best practices

**DEPLOYMENT-CHECKLIST.md**
- Pre-deployment requirements
- Step-by-step deployment process
- Post-deployment validation
- Sign-off checklist

**TROUBLESHOOTING.md**
- Common issues and solutions
- Debugging commands
- Error message reference
- Support resources

**Makefile**
- Automated deployment commands
- Testing utilities
- Monitoring helpers
- Cleanup procedures

### Terraform Files

**main.tf**
- VPC configuration
- EKS cluster setup
- Karpenter installation
- NodePool definitions
- EC2NodeClass configurations

**variables.tf**
- Input variable definitions
- Default values
- Variable descriptions

**outputs.tf**
- Cluster information outputs
- Connection details
- Resource identifiers

**terraform.tfvars.example**
- Example configuration values
- Template for customization

### Example Manifests

**nginx-x86.yaml**
- Demonstrates x86 node selection
- Uses nodeSelector for architecture
- Includes service exposure

**nginx-graviton.yaml**
- ARM64/Graviton deployment
- Architecture-specific configuration
- Cost-optimized workload

**spot-batch-job.yaml**
- Spot-tolerant batch job
- Interruption handling
- Cost-optimized computing

**autoscale-test.yaml**
- Triggers Karpenter autoscaling
- HPA configuration
- Load testing deployment

**architecture-comparison.yaml**
- Performance benchmarking
- x86 vs Graviton comparison
- Cost analysis helper

**monitoring.yaml**
- Metrics server deployment
- Kubernetes dashboard
- Resource monitoring

### Utility Scripts

**validate-deployment.sh**
- Comprehensive validation checks
- Prerequisites verification
- Cluster health assessment
- Multi-architecture validation

**cost-optimization.sh**
- Cost analysis reporting
- Optimization recommendations
- Instance type analysis
- Savings calculations

## Adding New Components

When adding new components to the project:

1. **Terraform Modules**: Place in a `modules/` directory
2. **Additional Scripts**: Add to `scripts/` with executable permissions
3. **Documentation**: Update README.md and relevant guides
4. **Examples**: Add to `examples/` with descriptive names
5. **Tests**: Create a `tests/` directory for test cases

## Best Practices

1. **Keep Terraform files modular** - Separate concerns into different files
2. **Document all examples** - Include comments in YAML files
3. **Make scripts executable** - `chmod +x scripts/*.sh`
4. **Use consistent naming** - Kebab-case for files, snake_case for variables
5. **Update .gitignore** - Exclude sensitive and generated files

## Development Workflow

1. **Feature Development**
   ```bash
   git checkout -b feature/new-component
   # Make changes
   terraform fmt
   terraform validate
   git add .
   git commit -m "Add new component"
   ```

2. **Testing**
   ```bash
   terraform plan
   terraform apply -auto-approve
   ./scripts/validate-deployment.sh
   ```

3. **Documentation**
   - Update README.md if adding features
   - Add examples if introducing new patterns
   - Update TROUBLESHOOTING.md with known issues

4. **Cleanup**
   ```bash
   make cleanup-examples
   terraform destroy -auto-approve
   ```

## File Permissions

Ensure proper permissions:
```bash
chmod +x scripts/*.sh
chmod +x Makefile
chmod 644 *.md
chmod 644 *.tf
chmod 644 examples/*.yaml
```

## Version Control

### Files to Track
- All `.tf` files
- All `.md` documentation
- `Makefile`
- `examples/` directory
- `scripts/` directory
- `.gitignore`

### Files to Ignore
- `*.tfstate*` - Terraform state files
- `*.tfvars` - Sensitive configuration
- `.terraform/` - Provider plugins
- `*.pem` - SSH keys
- `kubeconfig` - Cluster credentials

## Contributing Guidelines

1. **Code Style**
   - Run `terraform fmt` before committing
   - Use meaningful variable names
   - Comment complex configurations

2. **Documentation**
   - Update README for user-facing changes
   - Add troubleshooting entries for known issues
   - Include examples for new features

3. **Testing**
   - Test on fresh AWS account when possible
   - Validate both x86 and ARM64 deployments
   - Check cost implications

4. **Security**
   - Never commit credentials
   - Use IAM roles over access keys
   - Enable encryption where possible
   - Follow principle of least privilege