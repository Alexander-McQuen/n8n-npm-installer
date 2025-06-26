#!/bin/bash

# ==============================================================================
# Script Name: n8n & NPM Installer
# Description: Installs n8n and Nginx Proxy Manager via Docker on Ubuntu.
#              Designed to be run via: curl -sSL <url> | sudo bash
# Author:      Your Name / AI Assistant
# Version:     1.5 (Cleaned up compose files)
# OS:          Ubuntu 22.04+
# ==============================================================================

# --- Configuration ---
BASE_DIR="/opt/docker-apps"
N8N_DIR="$BASE_DIR/n8n"
NPM_DIR="$BASE_DIR/npm"
N8N_TIMEZONE="Europe/Berlin" # Find yours: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones

# --- Colors for Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script requires root privileges to run.${NC}"
    echo -e "${YELLOW}Please run it using the following command:${NC}"
    echo "curl -sSL https://raw.githubusercontent.com/Alexander-McQuen/n8n-npm-installer/main/install.sh | sudo bash"
    exit 1
  fi
}

press_enter_to_continue() {
  read -p "Press [Enter] to return to the menu..." < /dev/tty
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
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
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

  if [ -n "$SUDO_USER" ]; then
      usermod -aG docker "$SUDO_USER"
      echo -e "\n${YELLOW}Added user '$SUDO_USER' to the 'docker' group.${NC}"
      echo -e "${YELLOW}You may need to log out and log back in for this to take full effect.${NC}"
  fi
}

# 2. Install n8n
install_n8n() {
  echo -e "${YELLOW}---> Installing n8n...${NC}"
  if [ -d "$N8N_DIR" ]; then echo -e "${RED}n8n directory already exists. Installation aborted.${NC}"; return; fi
  echo -e "Creating directory: ${N8N_DIR}"
  mkdir -p "$N8N_DIR"
  cat <<EOF > "${N8N_DIR}/docker-compose.yml"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - GENERIC_TIMEZONE=${N8N_TIMEZONE}
    volumes:
      - n8n_data:/home/node/.n8n
volumes:
  n8n_data:
EOF
  echo -e "Starting n8n container..."
  (cd "$N8N_DIR" && docker-compose up -d)
  echo -e "\n${GREEN}n8n has been installed!${NC}"
  echo -e "It is running on port ${YELLOW}5678${NC}. Use Nginx Proxy Manager to expose it."
}

# 3. Install Nginx Proxy Manager
install_npm() {
  echo -e "${YELLOW}---> Installing Nginx Proxy Manager...${NC}"
  if [ -d "$NPM_DIR" ]; then echo -e "${RED}Nginx Proxy Manager directory already exists. Installation aborted.${NC}"; return; fi
  echo -e "Creating directory: ${NPM_DIR}"
  mkdir -p "${NPM_DIR}/data" && mkdir -p "${NPM_DIR}/letsencrypt"
  cat <<EOF > "${NPM_DIR}/docker-compose.yml"
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
  echo -e "\n${GREEN}Nginx Proxy Manager has been installed!${NC}"
  echo -e "Access the admin UI at: ${YELLOW}http://<your_server_ip>:81${NC}"
  echo -e "Default credentials:"
  echo -e "  Email:    ${YELLOW}admin@example.com${NC}"
  echo -e "  Password: ${YELLOW}changeme${NC}"
  echo -e "${RED}IMPORTANT: Log in immediately and change your email and password!${NC}"
}

# 4. Remove n8n
remove_n8n() {
  echo -e "${YELLOW}---> Removing n8n...${NC}"
  if [ ! -d "$N8N_DIR" ]; then echo -e "${RED}n8n directory not found. Nothing to do.${NC}"; return; fi
  read -p "Are you sure you want to permanently remove n8n and all its data? (y/N): " confirm < /dev/tty
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    echo "Stopping and removing n8n containers and volumes..."
    (cd "$N8N_DIR" && docker-compose down -v)
    rm -rf "$N8N_DIR"
    echo -e "${GREEN}n8n successfully removed.${NC}"
  else echo "Removal cancelled."; fi
}

# 5. Remove Nginx Proxy Manager
remove_npm() {
  echo -e "${YELLOW}---> Removing Nginx Proxy Manager...${NC}"
  if [ ! -d "$NPM_DIR" ]; then echo -e "${RED}Nginx Proxy Manager directory not found. Nothing to do.${NC}"; return; fi
  read -p "Are you sure you want to permanently remove NPM and all its data? (y/N): " confirm < /dev/tty
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    echo "Stopping and removing NPM containers and volumes..."
    (cd "$NPM_DIR" && docker-compose down -v)
    rm -rf "$NPM_DIR"
    echo -e "${GREEN}Nginx Proxy Manager successfully removed.${NC}"
  else echo "Removal cancelled."; fi
}

# --- Main Menu Logic ---
display_menu() {
  clear
  echo "================================================"
  echo "      Docker App Management Script"
  echo "================================================"
  echo -e " ${GREEN}1.${NC} Install/Verify Docker & Docker Compose"
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
  read -p "Enter your choice [1-6 or q]: " choice < /dev/tty
  clear
  case $choice in
    1) install_docker; press_enter_to_continue ;;
    2) install_n8n; press_enter_to_continue ;;
    3) install_npm; press_enter_to_continue ;;
    4)
      echo -e "${RED}This will remove BOTH applications.${NC}\n"
      remove_n8n; echo ""; remove_npm
      press_enter_to_continue ;;
    5) remove_n8n; press_enter_to_continue ;;
    6) remove_npm; press_enter_to_continue ;;
    q|Q) echo "Exiting."; exit 0 ;;
    *) echo -e "${RED}Invalid option. Please try again.${NC}"; sleep 2 ;;
  esac
done
