#!/bin/bash

# ==============================================================================
# Script Name: Docker App Installer
# Description: Installs and manages n8n and Nginx Proxy Manager via Docker.
# Author:      Your Name / AI Assistant
# Version:     1.0
# OS:          Ubuntu 22.04+
# ==============================================================================

# --- Configuration ---
# You can change these directories if you like. /opt is a good place for them.
BASE_DIR="/opt/docker-apps"
N8N_DIR="$BASE_DIR/n8n"
NPM_DIR="$BASE_DIR/npm"
# Set your timezone for n8n. Find yours here: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
N8N_TIMEZONE="Europe/Berlin"

# --- Colors for Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---

# Function to check if the script is run as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root. Please use 'sudo ./setup_tools.sh'.${NC}"
    exit 1
  fi
}

# Function to pause and wait for user to press Enter
press_enter_to_continue() {
  read -p "Press [Enter] to continue..."
}

# --- Core Functions ---

# 1. Install Docker and Docker Compose
install_docker() {
  echo -e "${YELLOW}---> Checking for Docker...${NC}"
  if command -v docker &> /dev/null; then
    echo -e "${GREEN}Docker is already installed. Skipping.${NC}"
  else
    echo -e "${YELLOW}---> Installing Docker...${NC}"
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    echo -e "${GREEN}Docker installed successfully.${NC}"
  fi

  echo -e "\n${YELLOW}---> Checking for Docker Compose...${NC}"
  if command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}Docker Compose is already installed. Skipping.${NC}"
  else
    echo -e "${YELLOW}---> Installing Docker Compose...${NC}"
    LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose ${LATEST_COMPOSE} installed successfully.${NC}"
  fi

  # Add current user to the docker group for non-sudo usage
  if [ -n "$SUDO_USER" ]; then
      usermod -aG docker $SUDO_USER
      echo -e "\n${YELLOW}Added user '$SUDO_USER' to the 'docker' group.${NC}"
      echo -e "${YELLOW}You may need to log out and log back in for this change to take effect.${NC}"
  fi
  
  press_enter_to_continue
}

# 2. Install n8n
install_n8n() {
  echo -e "${YELLOW}---> Installing n8n...${NC}"
  if [ -d "$N8N_DIR" ]; then
    echo -e "${RED}n8n directory already exists at $N8N_DIR. Installation aborted.${NC}"
    press_enter_to_continue
    return
  fi

  echo -e "Creating directory: ${N8N_DIR}"
  mkdir -p "$N8N_DIR"
  
  # Create the docker-compose.yml file for n8n
  cat <<EOF > "${N8N_DIR}/docker-compose.yml"
version: '3.7'

services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_HOST=\${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=\${WEBHOOK_URL}
      - GENERIC_TIMEZONE=${N8N_TIMEZONE}
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
EOF

  echo -e "Starting n8n container..."
  (cd "$N8N_DIR" && docker-compose up -d)

  echo -e "${GREEN}n8n has been installed!${NC}"
  echo -e "It is running on port ${YELLOW}5678${NC} on this machine."
  echo -e "You should now use Nginx Proxy Manager to expose it with a domain name."
  press_enter_to_continue
}

# 3. Install Nginx Proxy Manager
install_npm() {
  echo -e "${YELLOW}---> Installing Nginx Proxy Manager...${NC}"
  if [ -d "$NPM_DIR" ]; then
    echo -e "${RED}Nginx Proxy Manager directory already exists at $NPM_DIR. Installation aborted.${NC}"
    press_enter_to_continue
    return
  fi

  echo -e "Creating directory: ${NPM_DIR}"
  mkdir -p "${NPM_DIR}/data"
  mkdir -p "${NPM_DIR}/letsencrypt"

  # Create the docker-compose.yml file for NPM
  cat <<EOF > "${NPM_DIR}/docker-compose.yml"
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

  echo -e "Starting Nginx Proxy Manager container..."
  (cd "$NPM_DIR" && docker-compose up -d)

  echo -e "${GREEN}Nginx Proxy Manager has been installed!${NC}"
  echo -e "Access the admin UI at: ${YELLOW}http://<your_server_ip>:81${NC}"
  echo -e "Default credentials:"
  echo -e "  Email:    ${YELLOW}admin@example.com${NC}"
  echo -e "  Password: ${YELLOW}changeme${NC}"
  echo -e "${RED}IMPORTANT: Log in immediately and change your email and password!${NC}"
  press_enter_to_continue
}

# 4. Remove n8n
remove_n8n() {
  echo -e "${YELLOW}---> Removing n8n...${NC}"
  if [ ! -d "$N8N_DIR" ]; then
    echo -e "${RED}n8n directory not found. It might already be removed.${NC}"
    press_enter_to_continue
    return
  fi
  
  read -p "Are you sure you want to permanently remove n8n and all its data? (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Removal cancelled."
    press_enter_to_continue
    return
  fi

  echo "Stopping n8n container and removing volumes..."
  (cd "$N8N_DIR" && docker-compose down -v)
  
  echo "Deleting n8n directory: $N8N_DIR"
  rm -rf "$N8N_DIR"

  echo -e "${GREEN}n8n has been successfully removed.${NC}"
  press_enter_to_continue
}

# 5. Remove Nginx Proxy Manager
remove_npm() {
  echo -e "${YELLOW}---> Removing Nginx Proxy Manager...${NC}"
  if [ ! -d "$NPM_DIR" ]; then
    echo -e "${RED}Nginx Proxy Manager directory not found. It might already be removed.${NC}"
    press_enter_to_continue
    return
  fi

  read -p "Are you sure you want to permanently remove Nginx Proxy Manager and all its data? (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Removal cancelled."
    press_enter_to_continue
    return
  fi
  
  echo "Stopping NPM container and removing volumes..."
  (cd "$NPM_DIR" && docker-compose down -v)

  echo "Deleting NPM directory: $NPM_DIR"
  rm -rf "$NPM_DIR"

  echo -e "${GREEN}Nginx Proxy Manager has been successfully removed.${NC}"
  press_enter_to_continue
}

# --- Main Menu Logic ---
display_menu() {
  clear
  echo "================================================"
  echo "      Docker App Management Script"
  echo "================================================"
  echo -e " ${GREEN}1.${NC} Install Docker & Docker Compose"
  echo ""
  echo -e " ${GREEN}2.${NC} Install n8n"
  echo -e " ${GREEN}3.${NC} Install Nginx Proxy Manager"
  echo ""
  echo -e " ${RED}4.${NC} REMOVE n8n AND Nginx Proxy Manager"
  echo -e " ${RED}5.${NC} REMOVE n8n only"
  echo -e " ${RED}6.${NC} REMOVE Nginx Proxy Manager only"
  echo ""
  echo -e " ${YELLOW}q.${NC} Quit"
  echo "================================================"
}

# --- Main Loop ---
check_root

while true; do
  display_menu
  read -p "Enter your choice [1-6 or q]: " choice
  case $choice in
    1) install_docker ;;
    2) install_n8n ;;
    3) install_npm ;;
    4)
      echo -e "\n${RED}This will remove BOTH applications.${NC}"
      remove_n8n
      remove_npm
      ;;
    5) remove_n8n ;;
    6) remove_npm ;;
    q|Q)
      echo "Exiting."
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid option. Please try again.${NC}"
      sleep 2
      ;;
  esac
done
