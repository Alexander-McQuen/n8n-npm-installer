#!/bin/bash

# ==============================================================================
#
#          n8n and Nginx Proxy Manager Installer for Ubuntu 22.04+
#
# This script automates the installation of:
#   1. Docker Engine and Docker Compose Plugin
#   2. n8n (a workflow automation tool)
#   3. Nginx Proxy Manager (for easy reverse proxying and SSL management)
#
# The entire setup is containerized using Docker.
#
# ==============================================================================

# --- Configuration ---
# You can change these variables if you want.
INSTALL_DIR="$HOME/n8n_stack"
DOCKER_NETWORK_NAME="n8n-proxy-network"
N8N_SUBDOMAIN="n8n.your-domain.com" # IMPORTANT: Replace with your actual domain/subdomain

# --- Helper Functions ---
# Function to print messages in a pretty format
print_info() {
    echo -e "\n\e[1;34m[INFO]\e[0m $1"
}

# Function to print success messages
print_success() {
    echo -e "\e[1;32m[SUCCESS]\e[0m $1"
}

# Function to print error messages and exit
print_error() {
    echo -e "\e[1;31m[ERROR]\e[0m $1"
    exit 1
}

# Function to check the exit status of the last command
check_status() {
    if [ $? -ne 0 ]; then
        print_error "$1"
    fi
}

# --- Main Script ---

# 1. Update System & Install Dependencies
# ------------------------------------------------------------------------------
print_info "Updating package lists and installing required dependencies..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
check_status "Failed to install dependencies."

# 2. Install Docker Engine and Docker Compose
# ------------------------------------------------------------------------------
print_info "Installing Docker Engine and Docker Compose..."

# Add Docker's official GPG key
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    check_status "Failed to add Docker GPG key."
else
    print_info "Docker GPG key already exists."
fi


# Set up the Docker repository
if ! grep -q "download.docker.com" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    check_status "Failed to set up Docker repository."
else
    print_info "Docker repository already exists in sources.list."
fi

# Install Docker Engine, CLI, Containerd, and Compose plugin
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
check_status "Failed to install Docker packages."

# Add current user to the docker group to run docker commands without sudo
sudo usermod -aG docker $USER
check_status "Failed to add user to the docker group."

print_success "Docker and Docker Compose installed successfully."
print_info "IMPORTANT: You need to log out and log back in for the group changes to take effect."

# 3. Set Up Directories
# ------------------------------------------------------------------------------
print_info "Creating installation directory at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR/n8n-data"
mkdir -p "$INSTALL_DIR/npm-data"
mkdir -p "$INSTALL_DIR/npm-letsencrypt"
cd "$INSTALL_DIR"
check_status "Failed to create or navigate to the installation directory."

# 4. Create Docker Compose Configuration
# ------------------------------------------------------------------------------
print_info "Creating docker-compose.yml file..."

# WARNING: Do not change the VUE_APP_URL_BASE_API and WEBHOOK_URL.
# They use the Docker service name 'n8n' to communicate over the internal Docker network.
# The N8N_HOST should be the subdomain you will use to access n8n publicly.

cat > docker-compose.yml << EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n
    container_name: n8n
    restart: unless-stopped
    ports:
      - '127.0.0.1:5678:5678'
    environment:
      - N8N_HOST=${N8N_SUBDOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - VUE_APP_URL_BASE_API=http://localhost:5678/
      - WEBHOOK_URL=https://${N8N_SUBDOMAIN}/
      - GENERIC_TIMEZONE=America/New_York # Change to your timezone, e.g., Europe/Berlin
    volumes:
      - ./n8n-data:/home/node/.n8n
    networks:
      - ${DOCKER_NETWORK_NAME}

  nginx-proxy-manager:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - '80:80'   # Public HTTP Port
      - '443:443' # Public HTTPS Port
      - '81:81'   # Admin Web UI Port
    volumes:
      - ./npm-data:/data
      - ./npm-letsencrypt:/etc/letsencrypt
    networks:
      - ${DOCKER_NETWORK_NAME}

networks:
  ${DOCKER_NETWORK_NAME}:
    name: ${DOCKER_NETWORK_NAME}
    driver: bridge
EOF

check_status "Failed to create docker-compose.yml file."
print_success "docker-compose.yml created successfully."

# 5. Final Instructions and Starting Services
# ------------------------------------------------------------------------------
echo ""
echo -e "\e[1;32m========================= INSTALLATION COMPLETE =========================\e[0m"
echo ""
echo "The script has finished. Here are your next steps:"
echo ""
echo -e "\e[1;33mAction Required:\e[0m Please log out and log back in now."
echo "This is necessary to apply the Docker group permissions."
echo ""
echo "After you log back in, navigate to the installation directory:"
echo -e "\e[1;35mcd ${INSTALL_DIR}\e[0m"
echo ""
echo "And start the services with:"
echo -e "\e[1;35mdocker compose up -d\e[0m"
echo ""
echo "Once the containers are running:"
echo ""
echo -e "1. \e[1;36mConfigure Nginx Proxy Manager:\e[0m"
echo "   - Open your browser and go to: \e[4mhttp://<your-server-ip>:81\e[0m"
echo "   - Default Admin User:"
echo "     - Email:    \e[1;32madmin@example.com\e[0m"
echo "     - Password: \e[1;32mchangeme\e[0m"
echo "   - You will be forced to change these credentials on your first login."
echo ""
echo -e "2. \e[1;36mSet Up Your Domain:\e[0m"
echo "   - Point an A record for \e[1;33m${N8N_SUBDOMAIN}\e[0m to your server's public IP address."
echo ""
echo -e "3. \e[1;36mCreate the Proxy Host:\e[0m"
echo "   - In Nginx Proxy Manager, go to 'Hosts' -> 'Proxy Hosts'."
echo "   - Add a new proxy host:"
echo "     - Domain Name: \e[1;33m${N8N_SUBDOMAIN}\e[0m"
echo "     - Scheme: \e[1;32mhttp\e[0m"
echo "     - Forward Hostname / IP: \e[1;32mn8n\e[0m (this is the container name)"
echo "     - Forward Port: \e[1;32m5678\e[0m"
echo "     - Enable 'Block Common Exploits'."
echo "   - Go to the 'SSL' tab, request a new SSL certificate, and enable 'Force SSL'."
echo ""
echo -e "4. \e[1;36mAccess n8n:\e[0m"
echo "   - You should now be able to securely access your n8n instance at:"
echo "     \e[4mhttps://${N8N_SUBDOMAIN}\e[0m"
echo ""
echo -e "\e[1;32m=========================================================================\e[0m"
