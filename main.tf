terraform {
  required_version = ">= 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.cluster_name
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Environment              = var.environment
    Cluster                  = var.cluster_name
    "karpenter.sh/discovery" = var.cluster_name
  }
}

################################################################################
# VPC Configuration
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  }

  tags = local.tags
}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.1"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  endpoint_public_access  = true
  endpoint_private_access = true

  addons = {
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    kube-proxy = {}
    coredns = {
      configuration_values = jsonencode({
        tolerations = [
          {
            key      = "system"
            operator = "Equal"
            value    = "true"
            effect   = "NoSchedule"
          }
        ]
      })
    }
    aws-ebs-csi-driver = {
      configuration_values = jsonencode({
        controller = {
          tolerations = [
            {
              key      = "system"
              operator = "Equal"
              value    = "true"
              effect   = "NoSchedule"
            }
          ]
        }
      })
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Enable IRSA
  enable_irsa = true

  # Managed node group for system workloads
  eks_managed_node_groups = {
    system = {
      name           = "${var.cluster_name}-sys"
      instance_types = ["t3.medium"]

      min_size     = 2
      max_size     = 3
      desired_size = 2

      capacity_type = "ON_DEMAND"

      labels = {
        role = "system"
      }

      taints = {
        system = {
          key    = "system"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      tags = merge(local.tags, {
        "karpenter.sh/discovery" = var.cluster_name
      })
    }
  }

  # Grant Karpenter access to launch instances
  enable_cluster_creator_admin_permissions = true

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = local.tags
}

################################################################################
# Karpenter
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.1"

  cluster_name = module.eks.cluster_name

  # Pod Identity configuration
  create_pod_identity_association = true
  namespace                       = "karpenter"
  service_account                 = "karpenter"

  # Karpenter controller will run on the system node group
  create_node_iam_role = false
  node_iam_role_arn    = module.eks_karpenter_node_iam_role.arn

  tags = local.tags
}

# Create IAM role for Karpenter nodes
module "eks_karpenter_node_iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-karpenter-node"

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }

  policies = {
    AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

# Install Karpenter using Helm
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version

  values = [
    <<-EOT
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
      featureGates:
        drift: true
        spotToSpotConsolidation: true
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    tolerations:
      - key: system
        value: "true"
        effect: NoSchedule
    nodeSelector:
      role: system
    EOT
  ]

  depends_on = [
    module.eks,
    module.karpenter
  ]
}

################################################################################
# Karpenter Node Pools and EC2 Node Classes
################################################################################

# EC2 Node Class for x86 instances
resource "kubectl_manifest" "karpenter_node_class_x86" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: x86-node-class
    spec:
      instanceStorePolicy: RAID0
      amiFamily: AL2023
      amiSelectorTerms:
        - alias: al2023@latest
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: "${var.cluster_name}"
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: "${var.cluster_name}"
      role: "${module.eks_karpenter_node_iam_role.name}"
      userData: |
        #!/bin/bash
        /etc/eks/bootstrap.sh ${var.cluster_name}
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 100Gi
            volumeType: gp3
            deleteOnTermination: true
      instanceMetadataOptions:
        httpEndpoint: enabled
        httpProtocolIPv6: disabled
        httpPutResponseHopLimit: 1
        httpTokens: required
      tags:
        Environment: ${var.environment}
        NodeType: x86
        ManagedBy: Karpenter
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# EC2 Node Class for Graviton (ARM64) instances
resource "kubectl_manifest" "karpenter_node_class_graviton" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: graviton-node-class
    spec:
      instanceStorePolicy: RAID0
      amiFamily: AL2023
      amiSelectorTerms:
        - alias: al2023-arm64@latest
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: "${var.cluster_name}"
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: "${var.cluster_name}"
      role: "${module.eks_karpenter_node_iam_role.name}"
      userData: |
        #!/bin/bash
        /etc/eks/bootstrap.sh ${var.cluster_name}
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 100Gi
            volumeType: gp3
            deleteOnTermination: true
      instanceMetadataOptions:
        httpEndpoint: enabled
        httpProtocolIPv6: disabled
        httpPutResponseHopLimit: 1
        httpTokens: required
      tags:
        Environment: ${var.environment}
        NodeType: graviton
        ManagedBy: Karpenter
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# Node Pool for x86 instances
resource "kubectl_manifest" "karpenter_nodepool_x86" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: x86-pool
    spec:
      template:
        metadata:
          labels:
            karpenter.sh/nodepool: x86-pool
            node-type: x86
        spec:
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
                - m6i.large
                - m6i.xlarge
                - m6i.2xlarge
                - m5.large
                - m5.xlarge
                - m5.2xlarge
                - c6i.large
                - c6i.xlarge
                - c6i.2xlarge
                - c5.large
                - c5.xlarge
                - c5.2xlarge
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: x86-node-class
          taints:
            - key: x86-pool
              value: "true"
              effect: NoSchedule
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
        budgets:
          - nodes: "10%"
      limits:
        cpu: "1000"
        memory: "1000Gi"
  YAML

  depends_on = [
    kubectl_manifest.karpenter_node_class_x86
  ]
}

# Node Pool for Graviton (ARM64) instances
resource "kubectl_manifest" "karpenter_nodepool_graviton" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: graviton-pool
    spec:
      template:
        metadata:
          labels:
            karpenter.sh/nodepool: graviton-pool
            node-type: graviton
        spec:
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["arm64"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
                - m7g.large
                - m7g.xlarge
                - m7g.2xlarge
                - m6g.large
                - m6g.xlarge
                - m6g.2xlarge
                - c7g.large
                - c7g.xlarge
                - c7g.2xlarge
                - c6g.large
                - c6g.xlarge
                - c6g.2xlarge
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: graviton-node-class
          taints:
            - key: graviton-pool
              value: "true"
              effect: NoSchedule
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
        budgets:
          - nodes: "10%"
      limits:
        cpu: "1000"
        memory: "1000Gi"
  YAML

  depends_on = [
    kubectl_manifest.karpenter_node_class_graviton
  ]
}

# Node Pool for Spot-only instances (mixed architecture)
resource "kubectl_manifest" "karpenter_nodepool_spot" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: spot-pool
    spec:
      template:
        metadata:
          labels:
            karpenter.sh/nodepool: spot-pool
            node-type: spot
        spec:
          requirements:
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot"]
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
                # x86 instances
                - m6i.large
                - m6i.xlarge
                - m5.large
                - m5.xlarge
                - c6i.large
                - c6i.xlarge
                - c5.large
                - c5.xlarge
                # ARM64 instances
                - m7g.large
                - m7g.xlarge
                - m6g.large
                - m6g.xlarge
                - c7g.large
                - c7g.xlarge
                - c6g.large
                - c6g.xlarge
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: x86-node-class
          taints:
            - key: spot
              value: "true"
              effect: NoSchedule
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
        budgets:
          - nodes: "50%"
      limits:
        cpu: "1000"
        memory: "1000Gi"
  YAML

  depends_on = [
    kubectl_manifest.karpenter_node_class_x86
  ]
}