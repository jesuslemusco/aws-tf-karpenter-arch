#!/bin/bash

# EC2 Quota Checker Script
# Checks AWS EC2 quotas for Spot and On-Demand instances
# Usage: ./check-ec2-quotas.sh [region]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Default region
REGION=${1:-us-east-1}

# Function to print section headers
print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD} $1${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
}

# Function to print sub-headers
print_subheader() {
    echo ""
    echo -e "${BLUE}${BOLD}── $1${NC}"
}

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
        exit 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}AWS credentials are not configured properly.${NC}"
        exit 1
    fi
}

# Function to format quota value with color coding
format_quota_value() {
    local value=$1
    local name=$2
    
    # Handle N/A or empty values
    if [ "$value" == "N/A" ] || [ -z "$value" ]; then
        echo -e "${GREEN}$name vCPUs${NC}"
        return
    fi
    
    # Use awk for floating point comparison to avoid bc issues
    if awk "BEGIN {exit !($value == 0)}"; then
        echo -e "${RED}$value vCPUs (BLOCKED - Request Increase!)${NC}"
    elif awk "BEGIN {exit !($value < 32)}"; then
        echo -e "${YELLOW}$value vCPUs (Limited)${NC}"
    else
        echo -e "${GREEN}$value vCPUs${NC}"
    fi
}

# Function to get quota value
get_quota() {
    local quota_code=$1
    local quota_name=$2
    
    result=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code "$quota_code" \
        --region "$REGION" 2>/dev/null | jq -r '.Quota.Value' || echo "N/A")
    
    if [ "$result" != "N/A" ]; then
        echo -e "  ${BOLD}$quota_name:${NC} $(format_quota_value $result "$quota_name")"
    fi
}

# Function to check quota increase requests
check_quota_requests() {
    local quota_code=$1
    
    request=$(aws service-quotas list-requested-service-quota-change-history \
        --service-code ec2 \
        --region "$REGION" 2>/dev/null | \
        jq -r ".RequestedQuotas[] | select(.QuotaCode==\"$quota_code\" and .Status==\"PENDING\") | .DesiredValue" | head -1)
    
    if [ ! -z "$request" ]; then
        echo -e "    ${YELLOW}⏳ Pending request for: $request vCPUs${NC}"
    fi
}

# Main script
main() {
    clear
    
    # Check prerequisites
    check_aws_cli
    check_aws_credentials
    
    # Get account info
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    echo -e "${BOLD}EC2 Quota Checker${NC}"
    echo -e "Account: ${BOLD}$ACCOUNT_ID${NC}"
    echo -e "Region:  ${BOLD}$REGION${NC}"
    echo -e "Date:    ${BOLD}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    
    # On-Demand Instance Quotas
    print_header "ON-DEMAND INSTANCE QUOTAS"
    
    print_subheader "Standard Instances (A, C, D, H, I, M, R, T, Z)"
    get_quota "L-1216C47A" "Running On-Demand Standard instances"
    check_quota_requests "L-1216C47A"
    
    print_subheader "High Memory Instances"
    get_quota "L-43DA4232" "Running On-Demand High Memory instances"
    check_quota_requests "L-43DA4232"
    
    print_subheader "GPU Instances"
    get_quota "L-DB2E81BA" "Running On-Demand G and VT instances"
    check_quota_requests "L-DB2E81BA"
    get_quota "L-417A185B" "Running On-Demand P instances"
    check_quota_requests "L-417A185B"
    
    print_subheader "FPGA Instances"
    get_quota "L-74FC7D96" "Running On-Demand F instances"
    check_quota_requests "L-74FC7D96"
    
    print_subheader "Inf Instances"
    get_quota "L-B5D1601B" "Running On-Demand Inf instances"
    check_quota_requests "L-B5D1601B"
    
    print_subheader "Other Instance Types"
    get_quota "L-6E869C2A" "Running On-Demand X instances"
    check_quota_requests "L-6E869C2A"
    get_quota "L-8B27377A" "Running On-Demand DL instances"
    check_quota_requests "L-8B27377A"
    
    # Spot Instance Quotas
    print_header "SPOT INSTANCE QUOTAS"
    
    print_subheader "Standard Spot Instances"
    get_quota "L-34B43A08" "All Standard (A, C, D, H, I, M, R, T, Z) Spot Instance Requests"
    check_quota_requests "L-34B43A08"
    
    print_subheader "High Memory Spot Instances"
    get_quota "L-E3A00192" "All High Memory Spot Instance Requests"
    check_quota_requests "L-E3A00192"
    
    print_subheader "GPU Spot Instances"
    get_quota "L-3819A6DF" "All G and VT Spot Instance Requests"
    check_quota_requests "L-3819A6DF"
    get_quota "L-7212CCBC" "All P Spot Instance Requests"
    check_quota_requests "L-7212CCBC"
    
    print_subheader "FPGA Spot Instances"
    get_quota "L-88CF9481" "All F Spot Instance Requests"
    check_quota_requests "L-88CF9481"
    
    print_subheader "Inf Spot Instances"
    get_quota "L-779673C1" "All Inf Spot Instance Requests"
    check_quota_requests "L-779673C1"
    
    print_subheader "Other Spot Instance Types"
    get_quota "L-7295265B" "All X Spot Instance Requests"
    check_quota_requests "L-7295265B"
    get_quota "L-85EED4F7" "All DL Spot Instance Requests"
    check_quota_requests "L-85EED4F7"
    
    # Fleet Quotas
    print_header "FLEET AND OTHER QUOTAS"
    
    print_subheader "Fleet Limits"
    get_quota "L-49667964" "Max Spot Fleet requests"
    check_quota_requests "L-49667964"
    get_quota "L-3819A6DF" "Max EC2 Fleet requests"
    check_quota_requests "L-3819A6DF"
    
    # Check current usage
    print_header "CURRENT USAGE"
    
    print_subheader "Running Instances"
    
    # Count running instances by type
    RUNNING_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" \
        --region "$REGION" \
        --query "Reservations[].Instances[].[InstanceType,InstanceLifecycle]" \
        --output json 2>/dev/null)
    
    if [ "$RUNNING_INSTANCES" != "[]" ] && [ ! -z "$RUNNING_INSTANCES" ]; then
        ON_DEMAND_COUNT=$(echo "$RUNNING_INSTANCES" | jq '[.[] | select(.[1] != "spot")] | length')
        SPOT_COUNT=$(echo "$RUNNING_INSTANCES" | jq '[.[] | select(.[1] == "spot")] | length')
        
        echo -e "  On-Demand Instances: ${BOLD}$ON_DEMAND_COUNT${NC}"
        echo -e "  Spot Instances: ${BOLD}$SPOT_COUNT${NC}"
        
        # Show instance type breakdown
        echo ""
        echo -e "  ${BOLD}Instance Type Breakdown:${NC}"
        echo "$RUNNING_INSTANCES" | jq -r 'group_by(.[0]) | .[] | "    \(.[0][0]): \(length)"'
    else
        echo -e "  ${GREEN}No running instances${NC}"
    fi
    
    print_subheader "Active Fleets"
    
    FLEET_COUNT=$(aws ec2 describe-fleets --region "$REGION" --query "Fleets | length(@)" --output text 2>/dev/null || echo 0)
    SPOT_FLEET_COUNT=$(aws ec2 describe-spot-fleet-requests \
        --region "$REGION" \
        --query "SpotFleetRequestConfigs[?SpotFleetRequestState=='active'] | length(@)" \
        --output text 2>/dev/null || echo 0)
    
    echo -e "  EC2 Fleets: ${BOLD}$FLEET_COUNT${NC}"
    echo -e "  Spot Fleets: ${BOLD}$SPOT_FLEET_COUNT${NC}"
    
    # Recommendations
    print_header "RECOMMENDATIONS"
    
    # Check for zero quotas
    ZERO_QUOTAS=()
    
    CHECK_ON_DEMAND=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code "L-1216C47A" \
        --region "$REGION" 2>/dev/null | jq -r '.Quota.Value')
    
    CHECK_SPOT=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code "L-34B43A08" \
        --region "$REGION" 2>/dev/null | jq -r '.Quota.Value')
    
    if [ "$CHECK_ON_DEMAND" == "0" ] || [ "$CHECK_ON_DEMAND" == "0.0" ]; then
        echo -e "${RED}❌ Critical: On-Demand Standard instance quota is 0${NC}"
        echo -e "   Run: ${YELLOW}aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-1216C47A --desired-value 32 --region $REGION${NC}"
        echo ""
    fi
    
    if [ "$CHECK_SPOT" == "0" ] || [ "$CHECK_SPOT" == "0.0" ]; then
        echo -e "${RED}❌ Critical: Spot Standard instance quota is 0${NC}"
        echo -e "   Run: ${YELLOW}aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-34B43A08 --desired-value 32 --region $REGION${NC}"
        echo ""
    fi
    
    if [ "$CHECK_ON_DEMAND" != "0" ] && [ "$CHECK_ON_DEMAND" != "0.0" ] && \
       [ "$CHECK_SPOT" != "0" ] && [ "$CHECK_SPOT" != "0.0" ]; then
        echo -e "${GREEN}✓ Basic quotas look good!${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Run main function
main