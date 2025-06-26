#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install Docker and Docker Compose
install_docker() {
    print_status "Installing Docker and Docker Compose..."
    
    # Update package index[7]
    sudo apt update
    
    # Install prerequisites[7]
    sudo apt install curl software-properties-common ca-certificates apt-transport-https -y
    
    # Add Docker's official GPG key[7]
    wget -O- https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor | sudo tee /etc/apt/keyrings/docker.gpg > /dev/null
    
    # Add Docker repository[7]
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index again
    sudo apt update
    
    # Install Docker[7]
    sudo apt install docker-ce docker-ce-cli containerd.io -y
    
    # Install Docker Compose[7]
    sudo apt-get install docker-compose -y
    
    # Add current user to docker group[4]
    sudo usermod -aG docker $USER
    
    # Start and enable Docker[4]
    sudo systemctl start docker
    sudo systemctl enable docker
    
    print_status "Docker and Docker Compose installed successfully!"
    print_warning "Please log out and log back in for group changes to take effect."
}

# Function to install n8n
install_n8n() {
    print_status "Installing n8n with Docker..."
    
    if ! command_exists docker; then
        print_error "Docker is not installed. Please install Docker first."
        return 1
    fi
    
    # Create n8n data volume[8]
    docker volume create n8n_data
    
    # Get domain/host configuration
    read -p "Enter your domain name (or press Enter for localhost): " domain
    if [ -z "$domain" ]; then
        domain="localhost"
    fi
    
    # Run n8n container[4][8]
    docker run -d \
        --name n8n \
        --restart unless-stopped \
        -p 5678:5678 \
        -e N8N_HOST="$domain" \
        -e WEBHOOK_TUNNEL_URL="https://$domain/" \
        -e WEBHOOK_URL="https://$domain/" \
        -v n8n_data:/home/node/.n8n \
        n8nio/n8n:latest
    
    print_status "n8n installed successfully!"
    print_status "Access n8n at: http://$domain:5678"
}

# Function to install Nginx Proxy Manager
install_nginx_proxy_manager() {
    print_status "Installing Nginx Proxy Manager with Docker..."
    
    if ! command_exists docker; then
        print_error "Docker is not installed. Please install Docker first."
        return 1
    fi
    
    # Create directory for Nginx Proxy Manager
    mkdir -p ~/nginx-proxy-manager
    cd ~/nginx-proxy-manager
    
    # Create docker-compose.yml for Nginx Proxy Manager[3]
    cat > docker-compose.yml << 'EOF'
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
    environment:
      DB_MYSQL_HOST: "db"
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: "npm"
      DB_MYSQL_PASSWORD: "npm"
      DB_MYSQL_NAME: "npm"
  db:
    image: 'jc21/mariadb-aria:latest'
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: 'npm'
      MYSQL_DATABASE: 'npm'
      MYSQL_USER: 'npm'
      MYSQL_PASSWORD: 'npm'
    volumes:
      - ./mysql:/var/lib/mysql
EOF
    
    # Start Nginx Proxy Manager
    docker-compose up -d
    
    cd ~
    
    print_status "Nginx Proxy Manager installed successfully!"
    print_status "Access admin panel at: http://localhost:81"
    print_status "Default credentials - Email: admin@example.com, Password: changeme"
}

# Function to remove n8n
remove_n8n() {
    print_status "Removing n8n..."
    
    # Stop and remove n8n container[9]
    docker stop n8n 2>/dev/null || true
    docker rm n8n 2>/dev/null || true
    
    # Remove n8n volume
    docker volume rm n8n_data 2>/dev/null || true
    
    print_status "n8n removed successfully!"
}

# Function to remove Nginx Proxy Manager
remove_nginx_proxy_manager() {
    print_status "Removing Nginx Proxy Manager..."
    
    # Navigate to nginx-proxy-manager directory and stop containers
    cd ~/nginx-proxy-manager 2>/dev/null || true
    docker-compose down 2>/dev/null || true
    
    # Remove containers manually if docker-compose fails[9]
    docker stop nginx-proxy-manager-app-1 nginx-proxy-manager-db-1 2>/dev/null || true
    docker rm nginx-proxy-manager-app-1 nginx-proxy-manager-db-1 2>/dev/null || true
    
    # Remove the directory
    cd ~
    rm -rf ~/nginx-proxy-manager
    
    print_status "Nginx Proxy Manager removed successfully!"
}

# Function to remove both n8n and Nginx Proxy Manager
remove_both() {
    print_status "Removing both n8n and Nginx Proxy Manager..."
    remove_n8n
    remove_nginx_proxy_manager
    print_status "Both applications removed successfully!"
}

# Function to display menu
show_menu() {
    echo
    echo -e "${BLUE}=== n8n & Nginx Proxy Manager Installation Script ===${NC}"
    echo "1. Install Docker & Docker Compose"
    echo "2. Install n8n on Docker"
    echo "3. Install Nginx Proxy Manager on Docker"
    echo "4. Remove both n8n & Nginx Proxy Manager"
    echo "5. Remove n8n only"
    echo "6. Remove Nginx Proxy Manager only"
    echo "7. Exit"
    echo
}

# Main script logic
main() {
    while true; do
        show_menu
        read -p "Please select an option (1-7): " choice
        
        case $choice in
            1)
                install_docker
                ;;
            2)
                install_n8n
                ;;
            3)
                install_nginx_proxy_manager
                ;;
            4)
                remove_both
                ;;
            5)
                remove_n8n
                ;;
            6)
                remove_nginx_proxy_manager
                ;;
            7)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-7."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Check if script is run as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root. Run as regular user with sudo privileges."
    exit 1
fi

# Check if running on Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    print_warning "This script is designed for Ubuntu 22+. Other distributions may not work correctly."
fi

# Start the main function
main
