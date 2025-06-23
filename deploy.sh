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

    # Read .env file and export variables
    while IFS='=' read -r key value; do
      # Skip empty lines and comments
      [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

      # Remove quotes from value if present
      value=$(echo "$value" | sed 's/^["'\'']//' | sed 's/["'\'']$//')

      # Export the variable
      export "$key"="$value"
    done <"$env_file"

    echo -e "${GREEN}✅ Environment variables loaded${NC}"
  else
    echo -e "${YELLOW}⚠️  .env file not found, using fallback defaults${NC}"
  fi
}

# Load environment variables first
load_env

# Default configuration (fallback values if .env is missing)
DEFAULT_RPC_URL="${DEFAULT_RPC_URL:-http://127.0.0.1:8545}"
DEFAULT_SENDER="${DEFAULT_SENDER:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
DEFAULT_PRIVATE_KEY="${DEFAULT_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
SCRIPT_DIR="script"

# Available deployment scripts
AVAILABLE_SCRIPTS=(
  "01_DeployStaker.s.sol"
  "02_DeployAirdropImpl.s.sol"
  "03_DeployAirdropFactory.s.sol"
  "04_DeployAirdrop.s.sol"
  "FullDeploy.s.sol"
)

# Function to display usage
usage() {
  echo -e "${CYAN}Usage: $0 [script_file] [options]${NC}"
  echo ""
  echo -e "${YELLOW}Examples:${NC}"
  echo "  $0                     # Interactive menu with deployment scripts and utilities"
  echo "  $0 FullDeploy.s.sol"
  echo "  $0 01_DeployStaker.s.sol"
  echo "  $0 Deploy.s.sol --rpc-url http://localhost:8545"
  echo "  $0 Deploy.s.sol --sender 0x1234... --private-key 0xabcd..."
  echo ""
  echo -e "${YELLOW}Interactive Menu Options:${NC}"
  echo "  1-5) Deploy specific scripts"
  echo "  c)   Clear saved addresses (removes scripts/config/deployed-addresses.json)"
  echo "  p)   Print current config (displays scripts/config/deploy-config.json)"
  echo "  e)   Show environment variables"
  echo "  q)   Quit"
  echo ""
  echo -e "${YELLOW}Command Line Options:${NC}"
  echo "  --rpc-url <url>        RPC URL (default: $DEFAULT_RPC_URL)"
  echo "  --sender <address>     Sender address (default: $DEFAULT_SENDER)"
  echo "  --private-key <key>    Private key (default from .env or Anvil account #0)"
  echo "  --script-dir <dir>     Script directory (default: $SCRIPT_DIR)"
  echo "  --no-broadcast         Don't broadcast transactions (simulation only)"
  echo "  --verify               Verify contracts on Etherscan"
  echo "  --help, -h             Show this help message"
  echo ""
  echo -e "${BLUE}Default Anvil Accounts:${NC}"
  echo "  Account #0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
  echo "  Account #1: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
  echo "  Account #2: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
  echo ""
  echo -e "${CYAN}Environment Configuration:${NC}"
  echo "  Create a .env file in the project root with:"
  echo "  DEFAULT_RPC_URL=http://127.0.0.1:8545"
  echo "  DEFAULT_SENDER=0xYourAddress"
  echo "  DEFAULT_PRIVATE_KEY=0xYourPrivateKey"
}

# Function to show environment variables
show_env_vars() {
  echo -e "${CYAN}🌍 Current Environment Variables:${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}DEFAULT_RPC_URL:${NC}     ${DEFAULT_RPC_URL}"
  echo -e "${YELLOW}DEFAULT_SENDER:${NC}      ${DEFAULT_SENDER}"
  echo -e "${YELLOW}DEFAULT_PRIVATE_KEY:${NC}  ${DEFAULT_PRIVATE_KEY:0:10}...${DEFAULT_PRIVATE_KEY: -4}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# Function to clear deployed addresses
clear_deployed_addresses() {
  local addresses_file="script/config/deployed-addresses.json"

  if [[ -f "$addresses_file" ]]; then
    echo -e "${YELLOW}⚠️  This will delete all saved contract addresses!${NC}"
    echo -e "${BLUE}File: $addresses_file${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rm "$addresses_file"
      echo -e "${GREEN}✅ Deployed addresses cleared successfully!${NC}"
    else
      echo -e "${YELLOW}⏹️  Operation cancelled${NC}"
    fi
  else
    echo -e "${YELLOW}ℹ️  No deployed addresses file found at: $addresses_file${NC}"
  fi
  echo ""
}

# Function to print current config
print_current_config() {
  local config_file="script/config/deploy-config.json"
  local addresses_file="script/config/deployed-addresses.json"

  echo -e "${CYAN}📋 Current Deploy Configuration:${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Display deploy configuration
  if [[ -f "$config_file" ]]; then
    echo -e "${YELLOW}📄 Deploy Config: $config_file${NC}"
    echo ""
    cat "$config_file"
    echo ""
  else
    echo -e "${RED}❌ Config file not found at: $config_file${NC}"
    echo ""
  fi

  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Display deployed addresses
  echo -e "${CYAN}📍 Previous Deployments:${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  if [[ -f "$addresses_file" ]]; then
    echo -e "${YELLOW}📄 Deployed Addresses: $addresses_file${NC}"
    echo ""
    cat "$addresses_file"
    echo ""
  else
    echo -e "${PURPLE}ℹ️  No previous deployments detected${NC}"
    echo -e "${PURPLE}   (No deployed-addresses.json found)${NC}"
    echo ""
  fi

  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# Function to show interactive script selection menu
show_script_menu() {
  echo -e "${CYAN}🎯 Select a deployment script:${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  for i in "${!AVAILABLE_SCRIPTS[@]}"; do
    local num=$((i + 1))
    local script="${AVAILABLE_SCRIPTS[$i]}"
    local description=""

    # Add descriptions for each script
    case "$script" in
    "01_DeployStaker.s.sol")
      description="Deploy Staker contract"
      ;;
    "02_DeployAirdropImpl.s.sol")
      description="Deploy Airdrop Implementation"
      ;;
    "03_DeployAirdropFactory.s.sol")
      description="Deploy Airdrop Factory"
      ;;
    "04_DeployAirdrop.s.sol")
      description="Deploy Airdrop contract"
      ;;
    "FullDeploy.s.sol")
      description="Full deployment (all contracts)"
      ;;
    esac

    echo -e "${YELLOW}  $num)${NC} $script ${BLUE}- $description${NC}"
  done

  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${PURPLE}  c)${NC} Clear saved addresses ${BLUE}(clear saved addresses)${NC}"
  echo -e "${PURPLE}  p)${NC} Print current config ${BLUE}(print current config)${NC}"
  echo -e "${PURPLE}  e)${NC} Show environment variables ${BLUE}(show env vars)${NC}"
  echo -e "${PURPLE}  h)${NC} Show help ${BLUE}(display usage information)${NC}"
  echo -e "${CYAN}  q)${NC} Quit"
  echo ""
}

# Function to get user script selection
select_script() {
  while true; do
    show_script_menu
    read -p "Enter your choice (1-${#AVAILABLE_SCRIPTS[@]}, c, p, e, h, or q): " choice

    case "$choice" in
    [1-5])
      local index=$((choice - 1))
      if [[ $index -ge 0 && $index -lt ${#AVAILABLE_SCRIPTS[@]} ]]; then
        SCRIPT_FILE="${AVAILABLE_SCRIPTS[$index]}"
        echo -e "${GREEN}✅ Selected: $SCRIPT_FILE${NC}"
        return 0
      else
        echo -e "${RED}❌ Invalid selection. Please try again.${NC}"
      fi
      ;;
    [cC])
      clear_deployed_addresses
      ;;
    [pP])
      print_current_config
      ;;
    [eE])
      show_env_vars
      ;;
    [hH])
      usage
      ;;
    [qQ])
      echo -e "${YELLOW}👋 Goodbye!${NC}"
      exit 0
      ;;
    *)
      echo -e "${RED}❌ Invalid input. Please enter a number (1-${#AVAILABLE_SCRIPTS[@]}), 'c', 'p', 'e', 'h', or 'q' to quit.${NC}"
      ;;
    esac
    echo ""
  done
}

# Function to check if file exists
check_script_file() {
  local script_file="$1"
  local full_path="$SCRIPT_DIR/$script_file"

  if [[ ! -f "$full_path" ]]; then
    echo -e "${RED}❌ Error: Script file '$full_path' not found${NC}"
    echo -e "${YELLOW}💡 Available scripts in $SCRIPT_DIR/:${NC}"
    if [[ -d "$SCRIPT_DIR" ]]; then
      ls -la "$SCRIPT_DIR"/*.sol 2>/dev/null || echo "  No .sol files found"
    else
      echo "  Script directory '$SCRIPT_DIR' not found"
    fi
    exit 1
  fi
}

# Function to validate Ethereum address
validate_address() {
  local address="$1"
  if [[ ! "$address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo -e "${RED}❌ Error: Invalid Ethereum address format: $address${NC}"
    exit 1
  fi
}

# Function to validate private key
validate_private_key() {
  local key="$1"
  if [[ ! "$key" =~ ^0x[a-fA-F0-9]{64}$ ]]; then
    echo -e "${RED}❌ Error: Invalid private key format: $key${NC}"
    exit 1
  fi
}

# Parse command line arguments
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  usage
  exit 0
fi

# If no arguments provided, show interactive menu
if [[ $# -eq 0 ]]; then
  select_script
else
  SCRIPT_FILE="$1"
  shift
fi

# Initialize variables with defaults from .env
RPC_URL="$DEFAULT_RPC_URL"
SENDER="$DEFAULT_SENDER"
PRIVATE_KEY="$DEFAULT_PRIVATE_KEY"
BROADCAST="--broadcast"
VERIFY=""
EXTRA_ARGS=""

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  --rpc-url)
    RPC_URL="$2"
    shift 2
    ;;
  --sender)
    SENDER="$2"
    shift 2
    ;;
  --private-key)
    PRIVATE_KEY="$2"
    shift 2
    ;;
  --script-dir)
    SCRIPT_DIR="$2"
    shift 2
    ;;
  --no-broadcast)
    BROADCAST=""
    shift
    ;;
  --verify)
    VERIFY="--verify"
    shift
    ;;
  --*)
    # Pass through any other forge script arguments
    EXTRA_ARGS="$EXTRA_ARGS $1"
    if [[ $# -gt 1 ]] && [[ ! "$2" =~ ^-- ]]; then
      EXTRA_ARGS="$EXTRA_ARGS $2"
      shift
    fi
    shift
    ;;
  *)
    echo -e "${RED}❌ Error: Unknown argument: $1${NC}"
    usage
    exit 1
    ;;
  esac
done

# Validate inputs
check_script_file "$SCRIPT_FILE"
validate_address "$SENDER"
validate_private_key "$PRIVATE_KEY"

# Construct the full script path
FULL_SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_FILE"

# Display deployment information
echo -e "${CYAN}🚀 Foundry Script Deployment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}📄 Script:${NC}      $FULL_SCRIPT_PATH"
echo -e "${YELLOW}🌐 RPC URL:${NC}     $RPC_URL"
echo -e "${YELLOW}👤 Sender:${NC}      $SENDER"
echo -e "${YELLOW}🔑 Private Key:${NC}  ${PRIVATE_KEY:0:10}...${PRIVATE_KEY: -4}"
echo -e "${YELLOW}📡 Broadcast:${NC}   ${BROADCAST:+Yes}${BROADCAST:-No (Simulation only)}"
echo -e "${YELLOW}✅ Verify:${NC}      ${VERIFY:+Yes}${VERIFY:-No}"
if [[ -n "$EXTRA_ARGS" ]]; then
  echo -e "${YELLOW}⚙️  Extra Args:${NC}  $EXTRA_ARGS"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Ask for confirmation if broadcasting
if [[ -n "$BROADCAST" ]]; then
  echo -e "${YELLOW}⚠️  This will broadcast transactions to the network!${NC}"
  read -p "Do you want to continue? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}⏹️  Deployment cancelled${NC}"
    exit 0
  fi
fi

# Build the forge command
FORGE_CMD="forge script $FULL_SCRIPT_PATH --rpc-url $RPC_URL --sender $SENDER --private-key $PRIVATE_KEY"

if [[ -n "$BROADCAST" ]]; then
  FORGE_CMD="$FORGE_CMD $BROADCAST"
fi

if [[ -n "$VERIFY" ]]; then
  FORGE_CMD="$FORGE_CMD $VERIFY"
fi

if [[ -n "$EXTRA_ARGS" ]]; then
  FORGE_CMD="$FORGE_CMD $EXTRA_ARGS"
fi

# Execute the command
echo -e "${CYAN}🔄 Executing: $FORGE_CMD${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Run the forge command and capture exit code
if eval "$FORGE_CMD"; then
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  if [[ -n "$BROADCAST" ]]; then
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
  else
    echo -e "${GREEN}✅ Simulation completed successfully!${NC}"
  fi
else
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}❌ Deployment failed!${NC}"
  exit 1
fi
