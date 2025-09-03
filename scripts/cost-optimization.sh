#!/bin/bash

# Cost optimization analysis script for EKS with Karpenter

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "EKS Karpenter Cost Optimization Analysis"
echo "=========================================="
echo ""

# Get region from cluster
REGION=$(aws configure get region)
if [ -z "$REGION" ]; then
    REGION="us-west-2"
fi

# Function to get spot savings percentage
calculate_spot_savings() {
    local instance_type=$1
    local on_demand_price=$2
    local spot_price=$3
    
    if [ ! -z "$on_demand_price" ] && [ ! -z "$spot_price" ]; then
        savings=$(echo "scale=2; (($on_demand_price - $spot_price) / $on_demand_price) * 100" | bc)
        echo "$savings"
    else
        echo "N/A"
    fi
}

# Current cluster state
echo -e "${BLUE}Current Cluster State${NC}"
echo "====================="
echo ""

# Node count by type
echo "Node Distribution:"
total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
echo "  Total nodes: $total_nodes"

if [ "$total_nodes" -gt 0 ]; then
    # By capacity type
    echo ""
    echo "  By Capacity Type:"
    on_demand_count=$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l)
    spot_count=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l)
    echo "    On-Demand: $on_demand_count"
    echo "    Spot: $spot_count"
    
    # By architecture
    echo ""
    echo "  By Architecture:"
    x86_count=$(kubectl get nodes -l kubernetes.io/arch=amd64 --no-headers 2>/dev/null | wc -l)
    arm_count=$(kubectl get nodes -l kubernetes.io/arch=arm64 --no-headers 2>/dev/null | wc -l)
    echo "    x86 (amd64): $x86_count"
    echo "    ARM64 (Graviton): $arm_count"
    
    # Instance types in use
    echo ""
    echo "  Instance Types in Use:"
    kubectl get nodes -o json | jq -r '.items[] | .metadata.labels."node.kubernetes.io/instance-type" // "unknown"' | sort | uniq -c | while read count type; do
        echo "    $type: $count"
    done
fi
echo ""

# Resource utilization
echo -e "${BLUE}Resource Utilization${NC}"
echo "==================="
echo ""

if kubectl top nodes &> /dev/null; then
    echo "Node resource usage:"
    kubectl top nodes | head -10
else
    echo -e "${YELLOW}⚠${NC} Metrics server not available. Install metrics-server for resource utilization data."
fi
echo ""

# Cost estimation
echo -e "${BLUE}Cost Analysis${NC}"
echo "============="
echo ""

# Get current instance types and their prices
echo "Fetching current pricing data..."
instance_types=$(kubectl get nodes -o json | jq -r '.items[] | .metadata.labels."node.kubernetes.io/instance-type" // empty' | sort | uniq)

if [ ! -z "$instance_types" ]; then
    total_hourly_cost=0
    total_hourly_cost_spot=0
    total_hourly_cost_ondemand=0
    
    echo "Instance Type Pricing (per hour):"
    echo "---------------------------------"
    printf "%-20s %-15s %-15s %-15s %-10s\n" "Instance Type" "On-Demand" "Spot (avg)" "Current" "Savings"
    printf "%-20s %-15s %-15s %-15s %-10s\n" "-------------" "---------" "----------" "-------" "-------"
    
    while read -r instance_type; do
        if [ ! -z "$instance_type" ]; then
            # Get on-demand price
            on_demand_price=$(aws ec2 describe-instance-types --instance-types $instance_type --query "InstanceTypes[0].InstanceType" --region $REGION --output text 2>/dev/null || echo "N/A")
            
            # For demo purposes, using estimated prices (in production, use AWS Pricing API)
            case $instance_type in
                t3.medium) on_demand_price=0.0416; spot_price=0.0125 ;;
                m6i.large) on_demand_price=0.096; spot_price=0.029 ;;
                m6i.xlarge) on_demand_price=0.192; spot_price=0.058 ;;
                m6i.2xlarge) on_demand_price=0.384; spot_price=0.115 ;;
                m7g.large) on_demand_price=0.0816; spot_price=0.025 ;;
                m7g.xlarge) on_demand_price=0.1632; spot_price=0.049 ;;
                m7g.2xlarge) on_demand_price=0.3264; spot_price=0.098 ;;
                c6i.large) on_demand_price=0.085; spot_price=0.026 ;;
                c6i.xlarge) on_demand_price=0.17; spot_price=0.051 ;;
                c7g.large) on_demand_price=0.0725; spot_price=0.022 ;;
                c7g.xlarge) on_demand_price=0.145; spot_price=0.044 ;;
                *) on_demand_price=0.10; spot_price=0.03 ;;
            esac
            
            # Count nodes of this type
            node_count=$(kubectl get nodes -l node.kubernetes.io/instance-type=$instance_type --no-headers 2>/dev/null | wc -l)
            spot_nodes=$(kubectl get nodes -l node.kubernetes.io/instance-type=$instance_type,karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l)
            ondemand_nodes=$((node_count - spot_nodes))
            
            # Calculate current cost
            current_cost=$(echo "scale=4; ($ondemand_nodes * $on_demand_price) + ($spot_nodes * $spot_price)" | bc)
            
            # Add to totals
            total_hourly_cost=$(echo "scale=4; $total_hourly_cost + $current_cost" | bc)
            total_hourly_cost_spot=$(echo "scale=4; $total_hourly_cost_spot + ($spot_nodes * $spot_price)" | bc)
            total_hourly_cost_ondemand=$(echo "scale=4; $total_hourly_cost_ondemand + ($ondemand_nodes * $on_demand_price)" | bc)
            
            savings=$(calculate_spot_savings $instance_type $on_demand_price $spot_price)
            
            printf "%-20s \$%-14.4f \$%-14.4f \$%-14.4f %-10s\n" \
                "$instance_type ($node_count nodes)" \
                "$on_demand_price" \
                "$spot_price" \
                "$current_cost" \
                "${savings}%"
        fi
    done <<< "$instance_types"
    
    echo ""
    echo "Cost Summary:"
    echo "------------"
    echo "  Current hourly cost: \$$total_hourly_cost"
    echo "  Daily cost: \$$(echo "scale=2; $total_hourly_cost * 24" | bc)"
    echo "  Monthly cost (730 hrs): \$$(echo "scale=2; $total_hourly_cost * 730" | bc)"
    echo "  Yearly cost: \$$(echo "scale=2; $total_hourly_cost * 8760" | bc)"
    
    # Calculate potential savings
    echo ""
    echo "Optimization Potential:"
    echo "----------------------"
    
    # If all instances were spot
    all_spot_cost=$(echo "scale=4; $total_hourly_cost_spot + ($total_hourly_cost_ondemand * 0.3)" | bc)
    spot_savings=$(echo "scale=2; (($total_hourly_cost - $all_spot_cost) / $total_hourly_cost) * 100" | bc 2>/dev/null || echo "0")
    echo "  If all instances were Spot: ~${spot_savings}% savings"
    
    # If using more Graviton
    if [ "$arm_count" -lt "$x86_count" ]; then
        graviton_savings=$(echo "scale=2; (($x86_count - $arm_count) * 0.2 * $total_hourly_cost) / ($total_nodes + 0.01)" | bc 2>/dev/null || echo "0")
        echo "  If more workloads used Graviton: ~20% additional savings possible"
    fi
fi
echo ""

# Recommendations
echo -e "${BLUE}Cost Optimization Recommendations${NC}"
echo "================================="
echo ""

recommendations=0

# Check Spot usage
if [ "$spot_count" -lt "$on_demand_count" ]; then
    recommendations=$((recommendations + 1))
    echo -e "${YELLOW}$recommendations.${NC} Increase Spot instance usage"
    echo "   Current: $spot_count Spot vs $on_demand_count On-Demand"
    echo "   Action: Configure more workloads to tolerate Spot interruptions"
    echo "   Potential savings: Up to 70-90% on compute costs"
    echo ""
fi

# Check Graviton usage
if [ "$arm_count" -lt "$x86_count" ]; then
    recommendations=$((recommendations + 1))
    echo -e "${YELLOW}$recommendations.${NC} Migrate workloads to Graviton (ARM64)"
    echo "   Current: $arm_count ARM64 vs $x86_count x86"
    echo "   Action: Deploy ARM64-compatible images on Graviton instances"
    echo "   Potential savings: ~20% with better price-performance"
    echo ""
fi

# Check for over-provisioning
if kubectl top nodes &> /dev/null; then
    low_util_nodes=$(kubectl top nodes | tail -n +2 | awk '$3 < 30 && $5 < 30' | wc -l)
    if [ "$low_util_nodes" -gt 0 ]; then
        recommendations=$((recommendations + 1))
        echo -e "${YELLOW}$recommendations.${NC} Right-size instances"
        echo "   Found $low_util_nodes nodes with <30% CPU and Memory utilization"
        echo "   Action: Review Karpenter consolidation settings"
        echo "   Potential savings: 10-30% by using smaller instances"
        echo ""
    fi
fi

# Check for missing taints
recommendations=$((recommendations + 1))
echo -e "${YELLOW}$recommendations.${NC} Use node taints and pod tolerations"
echo "   Ensures workloads run on appropriate instance types"
echo "   Action: Apply taints to specialist node pools (GPU, memory-optimized)"
echo ""

# Instance diversity
recommendations=$((recommendations + 1))
echo -e "${YELLOW}$recommendations.${NC} Diversify instance types"
echo "   Reduces Spot interruption impact"
echo "   Action: Configure Karpenter with 10+ instance type options per pool"
echo ""

# Karpenter settings
echo -e "${BLUE}Karpenter Optimization Settings${NC}"
echo "=============================="
echo ""

echo "Current Karpenter NodePools:"
kubectl get nodepools -o json | jq -r '.items[] | "  - \(.metadata.name): \(.spec.limits.cpu // "unlimited") CPU, \(.spec.limits.memory // "unlimited") memory"'

echo ""
echo "Recommended Karpenter features to enable:"
echo "  ✓ Consolidation: Continuously right-sizes nodes"
echo "  ✓ Drift detection: Replaces outdated nodes"
echo "  ✓ Spot-to-Spot consolidation: Maintains Spot savings"
echo "  ✓ Interruption handling: Gracefully handles Spot interruptions"
echo ""

# Generate report
echo -e "${BLUE}Generating Cost Report${NC}"
echo "====================="
echo ""

report_file="cost-report-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "EKS Karpenter Cost Optimization Report"
    echo "Generated: $(date)"
    echo "Cluster: $(kubectl config current-context)"
    echo ""
    echo "Summary:"
    echo "  Total nodes: $total_nodes"
    echo "  Hourly cost: \$$total_hourly_cost"
    echo "  Monthly cost: \$$(echo "scale=2; $total_hourly_cost * 730" | bc)"
    echo ""
    echo "Distribution:"
    echo "  On-Demand: $on_demand_count nodes"
    echo "  Spot: $spot_count nodes"
    echo "  x86: $x86_count nodes"
    echo "  ARM64: $arm_count nodes"
    echo ""
    echo "Top recommendations:"
    echo "  1. Increase Spot usage (up to 90% savings)"
    echo "  2. Migrate to Graviton (~20% savings)"
    echo "  3. Enable Karpenter consolidation"
} > $report_file

echo "Report saved to: $report_file"
echo ""

echo -e "${GREEN}Cost optimization analysis complete!${NC}"
echo ""
echo "Key Actions:"
echo "1. Review and implement recommendations above"
echo "2. Monitor AWS Cost Explorer for actual savings"
echo "3. Set up AWS Budgets for cost alerts"
echo "4. Regular review of instance utilization"