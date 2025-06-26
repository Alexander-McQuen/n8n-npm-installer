#!/bin/bash

# ==============================================================================
# Script Name: n8n & NPM Installer
# Description: Installs n8n and Nginx Proxy Manager via Docker on Ubuntu.
#              Designed to be run via: curl -sSL <url> | sudo bash
# Author:      Your Name / AI Assistant
# Version:     1.6 (Uses printf for robust color display)
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
    printf "%b\n" "${RED}Error: This script requires root privileges to run.${NC}"
    printf "%b\n" "${YELLOW}Please run it using the following command:${NC}"
    printf "curl -sSL https://raw.githubusercontent.com/Alexander-McQuen/n8n-npm-installer/main/install.sh | sudo bash\n"
    exit 1
  fi
}

press_enter_to_continue() {
  read -p "Press [Enter] to return to the menu..." < /dev/tty
}

# --- Core Functions ---

install_docker() {
  printf "%b\n" "${YELLOW}---> Checking for Docker...${NC}"
  if command -v docker &> /dev/null; then
    printf "%b\n" "${GREEN}Docker is already installed. Skipping.${NC}"
  else
    printf "%b\n" "${YELLOW}---> Installing Docker...${NC}"
    apt-get update >/dev/null
    apt-get install -y ca-certificates curl gnupg >/dev/null
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update >/dev/null
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin >/dev/null
    printf "%b\n" "${GREEN}Docker installed successfully.${NC}"
  fi

  printf "\n%b\n" "${YELLOW}---> Checking for Docker Compose...${NC}"
  if command -v docker-compose &> /dev/null; then
    printf "%b\n" "${GREEN}Docker Compose is already installed. Skipping.${NC}"
  else
    printf "%b\n" "${YELLOW}---> Installing Docker Compose...${NC}"
    LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    printf "%b\n" "${GREEN}Docker Compose ${LATEST_COMPOSE} installed successfully.${NC}"
  fi

  if [ -n "$SUDO_USER" ]; then
      usermod -aG docker "$SUDO_USER"
      printf "\n%b\n" "${YELLOW}Added user '$SUDO_USER' to the 'docker' group.${NC}"
      printf "%b\n" "${YELLOW}You may need to log out and log back in for this to take full effect.${NC}"
  fi
}

install_n8n() {
  printf "%b\n" "${YELLOW}---> Installing n8n...${NC}"
  if [ -d "$N8N_DIR" ]; then printf "%b\n" "${RED}n8n directory already exists. Installation aborted.${NC}"; return; fi
  printf "Creating directory: %s\n" "${N8N_DIR}"
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
  printf "Starting n8n container...\n"
  (cd "$N8N_DIR" && docker-compose up -d)
  printf "\n%b\n" "${GREEN}n8n has been installed!${NC}"
  printf "It is running on port %b. Use Nginx Proxy Manager to expose it.\n" "${YELLOW}5678${NC}"
}

install_npm() {
  printf "%b\n" "${YELLOW}---> Installing Nginx Proxy Manager...${NC}"
  if [ -d "$NPM_DIR" ]; then printf "%b\n" "${RED}Nginx Proxy Manager directory already exists. Installation aborted.${NC}"; return; fi
  printf "Creating directory: %s\n" "${NPM_DIR}"
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
  printf "Starting Nginx Proxy Manager container...\n"
  (cd "$NPM_DIR" && docker-compose up -d)
  printf "\n%b\n" "${GREEN}Nginx Proxy Manager has been installed!${NC}"
  printf "Access the admin UI at: %b\n" "${YELLOW}http://<your_server_ip>:81${NC}"
  printf "Default credentials:\n"
  printf "  Email:    %b\n" "${YELLOW}admin@example.com${NC}"
  printf "  Password: %b\n" "${YELLOW}changeme${NC}"
  printf "%b\n" "${RED}IMPORTANT: Log in immediately and change your email and password!${NC}"
}

remove_n8n() {
  printf "%b\n" "${YELLOW}---> Removing n8n...${NC}"
  if [ ! -d "$N8N_DIR" ]; then printf "%b\n" "${RED}n8n directory not found. Nothing to do.${NC}"; return; fi
  read -p "Are you sure you want to permanently remove n8n and all its data? (y/N): " confirm < /dev/tty
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    printf "Stopping and removing n8n containers and volumes...\n"
    (cd "$N8N_DIR" && docker-compose down -v >/dev/null 2>&1)
    rm -rf "$N8N_DIR"
    printf "%b\n" "${GREEN}n8n successfully removed.${NC}"
  else printf "Removal cancelled.\n"; fi
}

remove_npm() {
  printf "%b\n" "${YELLOW}---> Removing Nginx Proxy Manager...${NC}"
  if [ ! -d "$NPM_DIR" ]; then printf "%b\n" "${RED}Nginx Proxy Manager directory not found. Nothing to do.${NC}"; return; fi
  read -p "Are you sure you want to permanently remove NPM and all its data? (y/N): " confirm < /dev/tty
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    printf "Stopping and removing NPM containers and volumes...\n"
    (cd "$NPM_DIR" && docker-compose down -v >/dev/null 2>&1)
    rm -rf "$NPM_DIR"
    printf "%b\n" "${GREEN}Nginx Proxy Manager successfully removed.${NC}"
  else printf "Removal cancelled.\n"; fi
}

display_menu() {
  clear
  printf "================================================\n"
  printf "      Docker App Management Script\n"
  printf "================================================\n"
  printf " %b1.%b Install/Verify Docker & Docker Compose\n" "${GREEN}" "${NC}"
  printf "\n"
  printf " %b2.%b Install n8n\n" "${GREEN}" "${NC}"
  printf " %b3.%b Install Nginx Proxy Manager\n" "${GREEN}" "${NC}"
  printf "\n"
  printf " %b4.%b REMOVE n8n AND Nginx Proxy Manager\n" "${RED}" "${NC}"
  printf " %b5.%b REMOVE n8n only\n" "${RED}" "${NC}"
  printf " %b6.%b REMOVE Nginx Proxy Manager only\n" "${RED}" "${NC}"
  printf "\n"
  printf " %bq.%b Quit\n" "${YELLOW}" "${NC}"
  printf "================================================\n"
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
      printf "%b\n\n" "${RED}This will remove BOTH applications.${NC}"
      remove_n8n; echo ""; remove_npm
      press_enter_to_continue ;;
    5) remove_n8n; press_enter_to_continue ;;
    6) remove_npm; press_enter_to_continue ;;
    q|Q) printf "Exiting.\n"; exit 0 ;;
    *) printf "%b\n" "${RED}Invalid option. Please try again.${NC}"; sleep 2 ;;
  esac
done
