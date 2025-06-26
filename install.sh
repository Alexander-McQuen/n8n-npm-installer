#!/bin/bash

# Docker n8n & Nginx Proxy Manager Installer
# Compatible with Ubuntu 22.04+
# Author: Auto-Installer Script
# Version: 1.1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
N8N_DATA_DIR="$HOME/n8n-data"
NPM_DATA_DIR="$HOME/npm-data"
COMPOSE_DIR="$HOME/docker-apps"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Function to get user input safely
get_input() {
    local prompt="$1"
    local input=""
    echo -n "$prompt"
    read input
    echo "$input"
}

# Function to get yes/no input
get_yes_no() {
    local prompt="$1"
    local input=""
    while true; do
        echo -n "$prompt (y/N): "
        read input
        case "${input,,}" in
            y|yes) return 0 ;;
            n|no|"") return 1 ;;
            *) echo "Please enter y or n" ;;
        esac
    done
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root for security reasons."
        print_status "Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Function to check Ubuntu version
check_ubuntu_version() {
    if ! lsb_release -d | grep -q "Ubuntu"; then
        print_error "This script is designed for Ubuntu systems only."
        exit 1
    fi
    
    VERSION=$(lsb_release -rs | cut -d. -f1)
    if [[ $VERSION -lt 22 ]]; then
        print_error "This script requires Ubuntu 22.04 or higher."
        exit 1
    fi
    
    print_status "Ubuntu version check passed."
}

# Function to install Docker and Docker Compose
install_docker() {
    print_header "Installing Docker & Docker Compose"
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        print_warning "Docker is already installed."
        docker --version
        return 0
    fi
    
    print_status "Updating package index..."
    sudo apt-get update -qq
    
    print_status "Installing prerequisites..."
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    print_status "Adding Docker's official GPG key..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    print_status "Setting up Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    print_status "Installing Docker Engine..."
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    print_status "Adding user to docker group..."
    sudo usermod -aG docker $USER
    
    print_status "Starting and enabling Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
    
    print_status "Docker installation completed!"
    print_warning "Please log out and log back in for group changes to take effect."
    print_status "Or run: newgrp docker"
    
    # Test Docker installation
    if sudo docker run hello-world &> /dev/null; then
        print_status "Docker test successful!"
    else
        print_error "Docker test failed!"
    fi
}

# Function to install n8n
install_n8n() {
    print_header "Installing n8n"
    
    # Create directories
    mkdir -p "$COMPOSE_DIR/n8n"
    mkdir -p "$N8N_DATA_DIR"
    
    # Create docker-compose.yml for n8n
    cat > "$COMPOSE_DIR/n8n/docker-compose.yml" << EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=localhost
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=http://localhost:5678/
      - GENERIC_TIMEZONE=UTC
    volumes:
      - $N8N_DATA_DIR:/home/node/.n8n
    networks:
      - n8n-network

networks:
  n8n-network:
    driver: bridge
EOF

    print_status "Starting n8n container..."
    cd "$COMPOSE_DIR/n8n"
    
    if docker compose up -d; then
        print_status "n8n installed successfully!"
        print_status "Access n8n at: http://localhost:5678"
        print_status "Data directory: $N8N_DATA_DIR"
        
        # Wait for n8n to start
        print_status "Waiting for n8n to start..."
        sleep 10
        
        if docker compose ps | grep -q "Up"; then
            print_status "n8n is running successfully!"
        else
            print_error "n8n failed to start. Check logs with: docker compose logs"
        fi
    else
        print_error "Failed to install n8n!"
    fi
}

# Function to install Nginx Proxy Manager
install_npm() {
    print_header "Installing Nginx Proxy Manager"
    
    # Create directories
    mkdir -p "$COMPOSE_DIR/npm"
    mkdir -p "$NPM_DATA_DIR/data"
    mkdir -p "$NPM_DATA_DIR/letsencrypt"
    
    # Create docker-compose.yml for Nginx Proxy Manager
    cat > "$COMPOSE_DIR/npm/docker-compose.yml" << EOF
version: '3.8'

services:
  nginx-proxy-manager:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
      - '81:81'
    volumes:
      - $NPM_DATA_DIR/data:/data
      - $NPM_DATA_DIR/letsencrypt:/etc/letsencrypt
    networks:
      - npm-network

networks:
  npm-network:
    driver: bridge
EOF

    print_status "Starting Nginx Proxy Manager container..."
    cd "$COMPOSE_DIR/npm"
    
    if docker compose up -d; then
        print_status "Nginx Proxy Manager installed successfully!"
        print_status "Access NPM admin at: http://localhost:81"
        print_status "Default credentials:"
        print_status "Email: admin@example.com"
        print_status "Password: changeme"
        print_status "Data directory: $NPM_DATA_DIR"
        
        # Wait for NPM to start
        print_status "Waiting for Nginx Proxy Manager to start..."
        sleep 15
        
        if docker compose ps | grep -q "Up"; then
            print_status "Nginx Proxy Manager is running successfully!"
        else
            print_error "Nginx Proxy Manager failed to start. Check logs with: docker compose logs"
        fi
    else
        print_error "Failed to install Nginx Proxy Manager!"
    fi
}

# Function to remove both n8n and NPM
remove_both() {
    print_header "Removing n8n and Nginx Proxy Manager"
    
    print_warning "This will remove both n8n and Nginx Proxy Manager containers and their data!"
    if ! get_yes_no "Are you sure?"; then
        print_status "Operation cancelled."
        return 0
    fi
    
    remove_n8n
    remove_npm
    
    print_status "Both applications removed successfully!"
}

# Function to remove n8n
remove_n8n() {
    print_header "Removing n8n"
    
    if [[ -d "$COMPOSE_DIR/n8n" ]]; then
        cd "$COMPOSE_DIR/n8n"
        print_status "Stopping and removing n8n container..."
        docker compose down -v
        
        print_warning "Do you want to remove n8n data directory? ($N8N_DATA_DIR)"
        if get_yes_no "Remove data?"; then
            rm -rf "$N8N_DATA_DIR"
            print_status "n8n data directory removed."
        fi
        
        rm -rf "$COMPOSE_DIR/n8n"
        print_status "n8n removed successfully!"
    else
        print_warning "n8n installation not found."
    fi
}

# Function to remove Nginx Proxy Manager
remove_npm() {
    print_header "Removing Nginx Proxy Manager"
    
    if [[ -d "$COMPOSE_DIR/npm" ]]; then
        cd "$COMPOSE_DIR/npm"
        print_status "Stopping and removing Nginx Proxy Manager container..."
        docker compose down -v
        
        print_warning "Do you want to remove NPM data directory? ($NPM_DATA_DIR)"
        if get_yes_no "Remove data?"; then
            rm -rf "$NPM_DATA_DIR"
            print_status "NPM data directory removed."
        fi
        
        rm -rf "$COMPOSE_DIR/npm"
        print_status "Nginx Proxy Manager removed successfully!"
    else
        print_warning "Nginx Proxy Manager installation not found."
    fi
}

# Function to check service status
check_status() {
    print_header "Service Status"
    
    # Check Docker
    if command -v docker &> /dev/null; then
        print_status "Docker: $(docker --version)"
        if systemctl is-active --quiet docker; then
            print_status "Docker service: Running"
        else
            print_warning "Docker service: Not running"
        fi
    else
        print_warning "Docker: Not installed"
    fi
    
    echo
    
    # Check n8n
    if [[ -d "$COMPOSE_DIR/n8n" ]]; then
        cd "$COMPOSE_DIR/n8n"
        if docker compose ps | grep -q "Up"; then
            print_status "n8n: Running (http://localhost:5678)"
        else
            print_warning "n8n: Installed but not running"
        fi
    else
        print_warning "n8n: Not installed"
    fi
    
    # Check NPM
    if [[ -d "$COMPOSE_DIR/npm" ]]; then
        cd "$COMPOSE_DIR/npm"
        if docker compose ps | grep -q "Up"; then
            print_status "Nginx Proxy Manager: Running (http://localhost:81)"
        else
            print_warning "Nginx Proxy Manager: Installed but not running"
        fi
    else
        print_warning "Nginx Proxy Manager: Not installed"
    fi
}

# Function to show logs
show_logs() {
    print_header "View Logs"
    echo "1. n8n logs"
    echo "2. Nginx Proxy Manager logs"
    echo "3. Back to main menu"
    echo
    
    choice=$(get_input "Select option (1-3): ")
    
    case "$choice" in
        1)
            if [[ -d "$COMPOSE_DIR/n8n" ]]; then
                cd "$COMPOSE_DIR/n8n"
                docker compose logs -f
            else
                print_warning "n8n not installed"
            fi
            ;;
        2)
            if [[ -d "$COMPOSE_DIR/npm" ]]; then
                cd "$COMPOSE_DIR/npm"
                docker compose logs -f
            else
                print_warning "Nginx Proxy Manager not installed"
            fi
            ;;
        3|"")
            return 0
            ;;
        *)
            print_error "Invalid option '$choice'"
            ;;
    esac
}

# Function to pause for user input
pause() {
    echo
    echo -n "Press Enter to continue..."
    read
}

# Main menu function
show_menu() {
    clear
    print_header "Docker n8n & Nginx Proxy Manager Installer"
    echo "System: $(lsb_release -d | cut -f2)"
    echo "User: $USER"
    echo
    echo "1. Install Docker & Docker Compose"
    echo "2. Install n8n"
    echo "3. Install Nginx Proxy Manager"
    echo "4. Remove both n8n & NPM"
    echo "5. Remove n8n only"
    echo "6. Remove Nginx Proxy Manager only"
    echo "7. Check service status"
    echo "8. View logs"
    echo "9. Exit"
    echo
}

# Main script execution
main() {
    check_root
    check_ubuntu_version
    
    while true; do
        show_menu
        choice=$(get_input "Select an option (1-9): ")
        echo
        
        case "$choice" in
            1)
                install_docker
                pause
                ;;
            2)
                if ! command -v docker &> /dev/null; then
                    print_error "Docker is not installed. Please install Docker first (option 1)."
                else
                    install_n8n
                fi
                pause
                ;;
            3)
                if ! command -v docker &> /dev/null; then
                    print_error "Docker is not installed. Please install Docker first (option 1)."
                else
                    install_npm
                fi
                pause
                ;;
            4)
                remove_both
                pause
                ;;
            5)
                remove_n8n
                pause
                ;;
            6)
                remove_npm
                pause
                ;;
            7)
                check_status
                pause
                ;;
            8)
                show_logs
                ;;
            9|"")
                print_status "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option '$choice'. Please enter a number between 1-9."
                pause
                ;;
        esac
    done
}

# Run the main function
main
