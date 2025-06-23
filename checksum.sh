#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to load environment variables from .env file
load_env() {
  local env_file=".env"
  if [[ -f "$env_file" ]]; then
    echo -e "${BLUE}📁 Loading environment variables from $env_file${NC}"
    while IFS='=' read -r key value; do
      [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
      value=$(echo "$value" | sed 's/^["'\'']//' | sed 's/["'\'']$//')
      export "$key"="$value"
    done <"$env_file"
    echo -e "${GREEN}✅ Environment variables loaded${NC}"
  else
    echo -e "${YELLOW}⚠️  .env file not found, using fallback defaults${NC}"
  fi
}

# Function to display usage
usage() {
  echo -e "${CYAN}Usage: $0 [options]${NC}"
  echo ""
  echo -e "${YELLOW}Options:${NC}"
  echo "  --rpc-url <url>        RPC URL (default: from .env or http://127.0.0.1:8545)"
  echo "  --help, -h             Show this help message"
  echo ""
  echo -e "${YELLOW}Examples:${NC}"
  echo "  $0                                   # Use default RPC from .env"
  echo "  $0 --rpc-url http://localhost:8545   # Use specific RPC"
  echo "  $0 --rpc-url \$SEPOLIA_RPC_URL        # Use Sepolia"
  echo ""
  echo -e "${CYAN}Description:${NC}"
  echo "  Verifies that deployed contracts match expected configuration."
  echo "  Checks contract addresses, variables, and inter-contract relationships."
}

# Function to check required files
check_required_files() {
  local missing_files=()

  if [[ ! -f "script/ChecksumScript.s.sol" ]]; then
    missing_files+=("script/ChecksumScript.s.sol")
  fi

  if [[ ! -f "script/config/deployed-addresses.json" ]]; then
    missing_files+=("script/config/deployed-addresses.json")
  fi

  if [[ ! -f "script/config/deploy-config.json" ]]; then
    missing_files+=("script/config/deploy-config.json")
  fi

  if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo -e "${RED}❌ Missing required files:${NC}"
    for file in "${missing_files[@]}"; do
      echo -e "${RED}   - $file${NC}"
    done
    echo ""
    echo -e "${YELLOW}💡 Make sure you have:${NC}"
    echo "   1. Deployed contracts using the deployment scripts"
    echo "   2. ChecksumScript.s.sol in the script directory"
    echo "   3. Valid deploy-config.json and deployed-addresses.json"
    exit 1
  fi
}

# Load environment variables first
load_env

# Default configuration
DEFAULT_RPC_URL="${DEFAULT_RPC_URL:-http://127.0.0.1:8545}"

# Parse command line arguments
RPC_URL="$DEFAULT_RPC_URL"

while [[ $# -gt 0 ]]; do
  case $1 in
  --rpc-url)
    RPC_URL="$2"
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo -e "${RED}❌ Error: Unknown argument: $1${NC}"
    usage
    exit 1
    ;;
  esac
done

# Check required files
check_required_files

# Display verification information
echo -e "${CYAN}🔍 Airdrop Deployment Checksum Verification${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🌐 RPC URL:${NC}      $RPC_URL"
echo -e "${YELLOW}📄 Script:${NC}       script/ChecksumScript.s.sol"
echo -e "${YELLOW}📋 Config:${NC}       script/config/deploy-config.json"
echo -e "${YELLOW}📍 Addresses:${NC}    script/config/deployed-addresses.json"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Build and execute the forge command
FORGE_CMD="forge script script/ChecksumScript.s.sol --rpc-url $RPC_URL"

echo -e "${CYAN}🔄 Executing verification...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Run the forge command and capture exit code
if eval "$FORGE_CMD"; then
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}✅ Checksum verification completed!${NC}"
  echo ""
  echo -e "   ${YELLOW}What should you do if verification failed?${NC}"
  echo "   1. Check deploy-config.json for correct expected values"
  echo "   2. Verify deployed-addresses.json has correct contract addresses"
  echo "   3. Check if contracts were deployed to the correct network"
  echo -e "   ${YELLOW}NOTE:${NC} This script is meant to test input data from ${YELLOW}.env${NC}, ${YELLOW}deploy-config.json${NC} and ${YELLOW}deployed-addresses.json${NC}"
else
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}❌ Checksum verification failed!${NC}"
  echo ""
  echo -e "${YELLOW}🔧 Troubleshooting tips:${NC}"
  echo "   1. Ensure you're connected to the correct network"
  echo "   2. Check that contracts are actually deployed"
  echo "   3. Verify your deploy-config.json matches deployment parameters"
  echo "   4. Check deployed-addresses.json for valid contract addresses"
  exit 1
fi
