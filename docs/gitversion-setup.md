# GitVersion Setup and Branching Strategy Guide

This guide explains how to use GitVersion for automatic semantic versioning in your local development and CI/CD pipeline.

## Table of Contents
- [What is GitVersion?](#what-is-gitversion)
- [Installation](#installation)
- [Branching Strategy](#branching-strategy)
- [Local Usage](#local-usage)
- [CI/CD Integration](#cicd-integration)
- [Tagging Strategy](#tagging-strategy)
- [Examples](#examples)

## What is GitVersion?

GitVersion is a tool that generates semantic version numbers based on your Git history and branching strategy. It automatically creates version numbers like `1.2.3-alpha.4` based on:
- Branch names
- Commit messages
- Tags
- Merge commits

## Installation

### macOS (Homebrew)
```bash
brew install gitversion
```

### Windows (Chocolatey)
```powershell
choco install gitversion.portable
```

### Linux (Native Options)

#### Option 1: Download Binary from repo 

```bash
# Download the latest GitVersion binary for Linux
export RELEASE=6.4.0
wget https://github.com/GitTools/GitVersion/releases/download/$RELEASE$/gitversion-linux-x64-$RELEASE$.tar.gz

# Extract the binary
tar -xvf gitversion-linux-x64-$RELEASE.tar.gz
rm gitversion-linux-x64-$RELEASE.tar.gz

# Move to a directory in PATH
sudo mv gitversion /usr/local/bin/
sudo chmod +x /usr/local/bin/gitversion

# Verify installation
gitversion --version
```

#### Option 2: Using .NET Tool (requires .NET SDK)
```bash
dotnet tool install --global GitVersion.Tool
```

### Docker
```bash
docker pull gittools/gitversion:latest
```

## Branching Strategy

Our repository follows GitFlow with the following branches:

### Main Branches
- **`main`** - Production-ready code (versions: `1.0.0`, `1.0.1`, etc.)
- **`develop`** - Integration branch for features (versions: `1.1.0-alpha.1`, `1.1.0-alpha.2`, etc.)

### Supporting Branches
- **`feature/*`** - New features (versions: `1.1.0-feature-name.1`)
- **`release/*`** - Release preparation (versions: `1.1.0-beta.1`)
- **`hotfix/*`** - Emergency fixes (versions: `1.0.1-beta.1`)
- **`support/*`** - Long-term support versions

## Local Usage

### Basic Commands

#### 1. Check Current Version
```bash
# Show the calculated version for current branch
gitversion /showvariable SemVer
```

#### 2. Show All Version Variables
```bash
# Display all version information
gitversion
```

#### 3. Update AssemblyInfo (if applicable)
```bash
# Update version in project files
gitversion /updateassemblyinfo
```

### Workflow Examples

#### Starting a New Feature
```bash
# Create feature branch from develop
git checkout develop
git pull origin develop
git checkout -b feature/new-authentication

# Check version (e.g., 1.1.0-new-authentication.1)
gitversion /showvariable SemVer

# Work on feature and commit
git add .
git commit -m "Add OAuth2 authentication"

# Version increments with each commit (1.1.0-new-authentication.2)
gitversion /showvariable SemVer
```

#### Creating a Release
```bash
# Create release branch from develop
git checkout develop
git checkout -b release/1.1.0

# Version will be 1.1.0-beta.1
gitversion /showvariable SemVer

# After testing, merge to main
git checkout main
git merge --no-ff release/1.1.0
git tag v1.1.0
git push origin main --tags

# Also merge back to develop
git checkout develop
git merge --no-ff release/1.1.0
```

#### Hotfix Flow
```bash
# Create hotfix from main
git checkout main
git checkout -b hotfix/critical-bug

# Version will be 1.0.1-beta.1
gitversion /showvariable SemVer

# Fix and merge to main
git checkout main
git merge --no-ff hotfix/critical-bug
git tag v1.0.1
git push origin main --tags

# Merge to develop
git checkout develop
git merge --no-ff hotfix/critical-bug
```

## Commit Message Conventions

Control version bumps with commit messages:

### Major Version Bump (Breaking Changes)
```bash
git commit -m "Breaking: Remove deprecated API endpoints +semver: major"
```

### Minor Version Bump (New Features)
```bash
git commit -m "Feature: Add user authentication +semver: minor"
```

### Patch Version Bump (Bug Fixes)
```bash
git commit -m "Fix: Resolve memory leak issue +semver: patch"
```

### No Version Bump
```bash
git commit -m "Docs: Update README +semver: skip"
```

## Tagging Strategy

### Manual Tagging
```bash
# After merging to main, tag the release
git checkout main
git tag v$(gitversion /showvariable SemVer)
git push origin --tags
```

### Automated Tagging Script
Create a script `tag-release.sh`:
```bash
#!/bin/bash
VERSION=$(gitversion /showvariable SemVer)
TAG="v${VERSION}"

echo "Creating tag: ${TAG}"
git tag -a "${TAG}" -m "Release ${VERSION}"
git push origin "${TAG}"
```

## Environment-Specific Versions

### Development Environment
```bash
# On develop branch
gitversion /showvariable InformationalVersion
# Output: 1.1.0-alpha.3+Branch.develop.Sha.a1b2c3d
```

### Staging Environment
```bash
# On release branch
gitversion /showvariable InformationalVersion
# Output: 1.1.0-beta.2+Branch.release-1.1.0.Sha.e4f5g6h
```

### Production Environment
```bash
# On main branch
gitversion /showvariable InformationalVersion
# Output: 1.0.0+Branch.main.Sha.i7j8k9l
```

## Terraform Integration

### Using GitVersion with Terraform

#### 1. Set Version as Terraform Variable
```bash
# Get version
VERSION=$(gitversion /showvariable SemVer)

# Apply with version tag
terraform apply -var="app_version=${VERSION}" -auto-approve
```

#### 2. Tag AWS Resources
```hcl
# variables.tf
variable "app_version" {
  description = "Application version from GitVersion"
  type        = string
  default     = "0.0.0"
}

# main.tf - Tag resources with version
resource "aws_eks_cluster" "main" {
  # ... other configuration ...
  
  tags = {
    Name        = var.cluster_name
    Environment = var.environment
    Version     = var.app_version
    ManagedBy   = "Terraform"
  }
}
```

#### 3. Create Version-Specific Resources
```bash
# Deploy version-specific infrastructure
DEPLOY_VERSION=$(gitversion /showvariable SemVer)
terraform workspace new "v${DEPLOY_VERSION}"
terraform workspace select "v${DEPLOY_VERSION}"
terraform apply -var="app_version=${DEPLOY_VERSION}"
```

## Scripts for Local Development

### `version.sh` - Display Current Version
```bash
#!/bin/bash
echo "Current version information:"
echo "=========================="
echo "SemVer: $(gitversion /showvariable SemVer)"
echo "Branch: $(git branch --show-current)"
echo "Commit: $(git rev-parse --short HEAD)"
echo "=========================="
```

### `bump-version.sh` - Interactive Version Bump
```bash
#!/bin/bash
echo "Select version bump type:"
echo "1) Major (Breaking changes)"
echo "2) Minor (New features)"
echo "3) Patch (Bug fixes)"
read -p "Choice: " choice

case $choice in
  1)
    MESSAGE_SUFFIX="+semver: major"
    ;;
  2)
    MESSAGE_SUFFIX="+semver: minor"
    ;;
  3)
    MESSAGE_SUFFIX="+semver: patch"
    ;;
  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

read -p "Commit message: " MESSAGE
git add .
git commit -m "${MESSAGE} ${MESSAGE_SUFFIX}"
echo "New version: $(gitversion /showvariable SemVer)"
```

## Best Practices

### 1. Branch Naming
- Use consistent prefixes: `feature/`, `release/`, `hotfix/`
- Use descriptive names: `feature/add-oauth` not `feature/oauth`
- Use hyphens not underscores: `feature/user-auth` not `feature/user_auth`

### 2. Commit Messages
- Start with type: `Fix:`, `Feature:`, `Breaking:`, `Docs:`
- Be descriptive but concise
- Include issue numbers: `Fix: Memory leak in worker process (#123)`
- Add semver hints when needed: `+semver: minor`

### 3. Tagging
- Always tag on main branch after release
- Use annotated tags: `git tag -a v1.0.0 -m "Release 1.0.0"`
- Push tags immediately: `git push origin --tags`
- Never delete or move tags in production

### 4. Version Increments
- Breaking changes → Major version
- New features → Minor version
- Bug fixes → Patch version
- Documentation/refactoring → No bump (use `+semver: skip`)

## Troubleshooting

### Issue: Version Not Incrementing
```bash
# Check if you have commits since last tag
git log --oneline $(git describe --tags --abbrev=0)..HEAD

# Force recalculation
gitversion /nocache
```

### Issue: Wrong Base Version
```bash
# Check current tags
git tag -l

# Check GitVersion configuration
cat GitVersion.yml

# Override base version temporarily
gitversion /overrideconfig next-version=2.0.0
```

### Issue: Incorrect Branch Detection
```bash
# Check branch configuration
git branch --show-current

# Ensure proper branch tracking
git branch --set-upstream-to=origin/develop develop
```

### Issue: CI/CD Version Mismatch
```bash
# Ensure full history is fetched
git fetch --unshallow
git fetch --tags

# Run GitVersion with debug info
gitversion /diag
```

## Quick Reference

| Branch | Version Format | Example |
|--------|---------------|---------|
| main | `major.minor.patch` | `1.0.0` |
| develop | `major.minor.patch-alpha.build` | `1.1.0-alpha.3` |
| feature/* | `major.minor.patch-branch.build` | `1.1.0-add-auth.2` |
| release/* | `major.minor.patch-beta.build` | `1.0.0-beta.1` |
| hotfix/* | `major.minor.patch-beta.build` | `1.0.1-beta.1` |

## Additional Resources

- [GitVersion Documentation](https://gitversion.net/docs/)
- [Semantic Versioning Spec](https://semver.org/)
- [GitFlow Workflow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow)
- [Conventional Commits](https://www.conventionalcommits.org/)