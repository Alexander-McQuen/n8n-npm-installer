#!/bin/bash

# n8n and Nginx Proxy Manager Auto-Install Script for Ubuntu 22+
# This script installs Docker, n8n, and Nginx Proxy Manager

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root for security reasons. Please run as a regular user with sudo privileges."
fi

# Check if user has sudo privileges
if ! sudo -v >/dev/null 2>&1; then
    error "This script requires sudo privileges. Please ensure your user is in the sudo group."
fi

log "Starting n8n and Nginx Proxy Manager installation..."

# Update system packages with retry logic
update_system() {
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Updating system packages (attempt $attempt of $max_attempts)..."
        if sudo apt update; then
            log "Package lists updated successfully!"
            break
        else
            warning "Package update failed on attempt $attempt"
            if [ $attempt -lt $max_attempts ]; then
                log "Switching to main Ubuntu repositories..."
                # Backup original sources.list
                sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%s) 2>/dev/null || true
                # Try switching to main repositories if using regional mirrors
                sudo sed -i.bak 's/[a-z][a-z]\.archive\.ubuntu\.com/archive.ubuntu.com/g' /etc/apt/sources.list 2>/dev/null || true
                sudo sed -i.bak 's/[a-z][a-z]-[a-z][a-z]-[0-9]\.clouds\.archive\.ubuntu\.com/archive.ubuntu.com/g' /etc/apt/sources.list 2>/dev/null || true
                sudo apt clean
                sleep 5
            fi
        fi
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        warning "System update failed after $max_attempts attempts. Continuing with existing packages..."
    fi
    
    # Try upgrade but don't fail if it doesn't work
    log "Attempting system upgrade..."
    sudo apt upgrade -y || warning "System upgrade failed, but continuing installation..."
}

# Install required packages with comprehensive retry logic
install_packages() {
    log "Installing required packages..."
    
    # Essential packages that we absolutely need
    local essential_packages="curl wget"
    # Nice-to-have packages
    local optional_packages="apt-transport-https ca-certificates gnupg lsb-release software-properties-common unzip"
    
    # Install essential packages first
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Installing essential packages (attempt $attempt of $max_attempts)..."
        if sudo apt install -y $essential_packages; then
            log "Essential packages installed successfully!"
            break
        else
            warning "Essential package installation failed on attempt $attempt"
            if [ $attempt -lt $max_attempts ]; then
                log "Trying to fix package issues..."
                sudo apt update --fix-missing || true
                sudo apt-get clean
                sudo apt-get autoclean
                sudo dpkg --configure -a || true
                sleep 5
            fi
        fi
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Failed to install essential packages (curl, wget). Cannot continue."
    fi
    
    # Try to install optional packages (don't fail if they don't install)
    log "Installing optional packages..."
    for package in $optional_packages; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log "Installing $package..."
            if ! sudo apt install -y "$package" 2>/dev/null; then
                warning "Failed to install $package, but continuing..."
            fi
        else
            log "$package is already installed"
        fi
    done
    
    log "Package installation phase completed!"
}

update_system
install_packages

# Check if Docker is already installed
check_and_install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log "Docker is already installed. Checking version..."
        docker --version
        log "Skipping Docker installation."
        return 0
    fi

    log "Installing Docker..."
    
    # Try multiple installation methods
    local docker_installed=false
    
    # Method 1: Official Docker repository (preferred)
    if ! $docker_installed; then
        log "Attempting Docker installation via official repository..."
        if install_docker_official; then
            docker_installed=true
        else
            warning "Official Docker installation failed, trying alternative method..."
        fi
    fi
    
    # Method 2: Ubuntu repository (fallback)
    if ! $docker_installed; then
        log "Attempting Docker installation via Ubuntu repository..."
        if install_docker_ubuntu; then
            docker_installed=true
        else
            warning "Ubuntu Docker installation failed, trying snap..."
        fi
    fi
    
    # Method 3: Snap (last resort)
    if ! $docker_installed; then
        log "Attempting Docker installation via snap..."
        if install_docker_snap; then
            docker_installed=true
        else
            error "All Docker installation methods failed!"
        fi
    fi
    
    if $docker_installed; then
        # Add current user to docker group
        sudo usermod -aG docker $USER || warning "Failed to add user to docker group"
        
        # Enable and start Docker service
        sudo systemctl enable docker || warning "Failed to enable docker service"
        sudo systemctl start docker || warning "Failed to start docker service"
        
        log "Docker installed successfully!"
        docker --version
    fi
}

# Official Docker installation method
install_docker_official() {
    # Add Docker's official GPG key
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null; then
        return 1
    fi
    
    # Add Docker repository
    if ! echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null; then
        return 1
    fi
    
    # Update package index
    if ! sudo apt update; then
        return 1
    fi
    
    # Install Docker Engine
    if sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        return 0
    else
        return 1
    fi
}

# Ubuntu repository Docker installation
install_docker_ubuntu() {
    if sudo apt install -y docker.io docker-compose-plugin; then
        return 0
    else
        return 1
    fi
}

# Snap Docker installation (last resort)
install_docker_snap() {
    if command -v snap >/dev/null 2>&1; then
        if sudo snap install docker; then
            return 0
        fi
    fi
    return 1
}

check_and_install_docker

# Check Docker Compose availability with fallback options
check_docker_compose() {
    log "Checking Docker Compose availability..."
    
    # Check for Docker Compose plugin (preferred)
    if docker compose version >/dev/null 2>&1; then
        log "Docker Compose plugin is available"
        return 0
    fi
    
    # Check for standalone docker-compose (fallback)
    if command -v docker-compose >/dev/null 2>&1; then
        log "Standalone docker-compose is available"
        # Create alias for consistency
        echo 'alias docker-compose="docker compose"' >> ~/.bashrc
        return 0
    fi
    
    # Try to install docker-compose as fallback
    log "Docker Compose not found, attempting to install..."
    
    # Method 1: Try installing via apt
    if sudo apt install -y docker-compose-plugin; then
        log "Docker Compose plugin installed via apt"
        return 0
    fi
    
    # Method 2: Install standalone docker-compose
    log "Installing standalone docker-compose..."
    local compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    if [ -z "$compose_version" ]; then
        compose_version="v2.21.0"  # Fallback version
    fi
    
    if sudo curl -L "https://github.com/docker/compose/releases/download/$compose_version/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
        sudo chmod +x /usr/local/bin/docker-compose
        if docker-compose --version >/dev/null 2>&1; then
            log "Standalone docker-compose installed successfully"
            return 0
        fi
    fi
    
    error "Failed to install Docker Compose. Please install it manually."
}

check_docker_compose

# Create application directory
APP_DIR="$HOME/n8n-npm-stack"
log "Creating application directory at $APP_DIR..."
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# Create necessary directories
mkdir -p nginx-proxy-manager/data
mkdir -p nginx-proxy-manager/letsencrypt
mkdir -p n8n/data

# Set proper permissions
sudo chown -R $USER:$USER "$APP_DIR"

# Create Docker Compose file
log "Creating Docker Compose configuration..."
cat > docker-compose.yml <<'EOF'
version: '3.8'

networks:
  proxy-network:
    driver: bridge

services:
  # Nginx Proxy Manager
  nginx-proxy-manager:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - '80:80'      # HTTP
      - '443:443'    # HTTPS
      - '81:81'      # Admin Web Interface
    volumes:
      - ./nginx-proxy-manager/data:/data
      - ./nginx-proxy-manager/letsencrypt:/etc/letsencrypt
    networks:
      - proxy-network
    environment:
      # Optional: Set timezone
      - TZ=UTC
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:81/api/"]
      interval: 30s
      timeout: 10s
      retries: 3

  # n8n Workflow Automation
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - '5678:5678'  # Internal port (will be proxied)
    volumes:
      - ./n8n/data:/home/node/.n8n
    networks:
      - proxy-network
    environment:
      - N8N_HOST=localhost
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=http://localhost:5678/
      - GENERIC_TIMEZONE=UTC
      # Security settings
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=changeme123
      # Database settings (using SQLite by default)
      - DB_TYPE=sqlite
      - DB_SQLITE_DATABASE=/home/node/.n8n/database.sqlite
    depends_on:
      - nginx-proxy-manager
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Optional: Watchtower for automatic updates
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=86400  # Check for updates daily
      - WATCHTOWER_INCLUDE_STOPPED=true
    networks:
      - proxy-network
EOF

# Create environment file template
log "Creating environment file template..."
cat > .env.template <<'EOF'
# n8n Configuration
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=changeme123
N8N_HOST=your-domain.com
N8N_PROTOCOL=https
WEBHOOK_URL=https://your-domain.com/

# Timezone
TZ=UTC

# Optional: Database configuration (for PostgreSQL)
# DB_TYPE=postgresdb
# DB_POSTGRESDB_HOST=postgres
# DB_POSTGRESDB_PORT=5432
# DB_POSTGRESDB_DATABASE=n8n
# DB_POSTGRESDB_USER=n8n
# DB_POSTGRESDB_PASSWORD=your-password
EOF

# Create startup script
log "Creating startup script..."
cat > start.sh <<'EOF'
#!/bin/bash
echo "Starting n8n and Nginx Proxy Manager stack..."
docker compose up -d
echo "Stack started successfully!"
echo ""
echo "Access URLs:"
echo "- Nginx Proxy Manager: http://localhost:81"
echo "- n8n: http://localhost:5678"
echo ""
echo "Default credentials:"
echo "- NPM: admin@example.com / changeme"
echo "- n8n: admin / changeme123"
echo ""
echo "Please change these default credentials immediately!"
EOF

# Create stop script
cat > stop.sh <<'EOF'
#!/bin/bash
echo "Stopping n8n and Nginx Proxy Manager stack..."
docker compose down
echo "Stack stopped successfully!"
EOF

# Create update script
cat > update.sh <<'EOF'
#!/bin/bash
echo "Updating n8n and Nginx Proxy Manager stack..."
docker compose pull
docker compose up -d
echo "Stack updated successfully!"
EOF

# Create backup script
cat > backup.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
echo "Creating backup in $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
cp -r nginx-proxy-manager/data "$BACKUP_DIR/npm-data"
cp -r n8n/data "$BACKUP_DIR/n8n-data"
cp docker-compose.yml "$BACKUP_DIR/"
cp .env "$BACKUP_DIR/" 2>/dev/null || true
echo "Backup created successfully at $BACKUP_DIR"
EOF

# Make scripts executable
chmod +x start.sh stop.sh update.sh backup.sh

# Create systemd service (optional)
log "Creating systemd service..."
sudo tee /etc/systemd/system/n8n-npm-stack.service > /dev/null <<EOF
[Unit]
Description=n8n and Nginx Proxy Manager Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
sudo systemctl daemon-reload
sudo systemctl enable n8n-npm-stack.service

# Start the stack with better error handling
start_docker_stack() {
    log "Starting the Docker stack..."
    
    # Determine which docker compose command to use
    local compose_cmd="docker compose"
    if ! docker compose version >/dev/null 2>&1; then
        if command -v docker-compose >/dev/null 2>&1; then
            compose_cmd="docker-compose"
        else
            error "No Docker Compose found!"
        fi
    fi
    
    # Start the services
    if $compose_cmd up -d; then
        log "Docker stack started successfully!"
    else
        error "Failed to start Docker stack. Check the logs with: $compose_cmd logs"
    fi
    
    # Wait for services to be ready
    log "Waiting for services to start..."
    local max_wait=60
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker ps | grep -q nginx-proxy-manager && docker ps | grep -q n8n; then
            log "Services are running!"
            break
        fi
        sleep 5
        wait_time=$((wait_time + 5))
        log "Waiting... ($wait_time/$max_wait seconds)"
    done
    
    if [ $wait_time -ge $max_wait ]; then
        warning "Services may not have started properly within $max_wait seconds"
        log "Current container status:"
        docker ps -a
        log "Check logs with: $compose_cmd logs"
    fi
}

start_docker_stack

# Display final information
echo ""
echo "=============================================="
echo -e "${GREEN}Installation completed successfully!${NC}"
echo "=============================================="
echo ""
echo "📂 Installation directory: $APP_DIR"
echo ""
echo "🌐 Access URLs:"
echo "   • Nginx Proxy Manager: http://$(hostname -I | awk '{print $1}'):81"
echo "   • n8n: http://$(hostname -I | awk '{print $1}'):5678"
echo ""
echo "🔐 Default credentials (CHANGE IMMEDIATELY!):"
echo "   • Nginx Proxy Manager: admin@example.com / changeme"
echo "   • n8n: admin / changeme123"
echo ""
echo "🛠️  Management commands:"
echo "   • Start:   ./start.sh"
echo "   • Stop:    ./stop.sh"
echo "   • Update:  ./update.sh"
echo "   • Backup:  ./backup.sh"
echo "   • Logs:    docker compose logs -f"
echo ""
echo "🔧 Systemd service commands:"
echo "   • Start:   sudo systemctl start n8n-npm-stack"
echo "   • Stop:    sudo systemctl stop n8n-npm-stack"
echo "   • Status:  sudo systemctl status n8n-npm-stack"
echo ""
echo "⚠️  IMPORTANT SECURITY NOTES:"
echo "   1. Change default passwords immediately"
echo "   2. Configure SSL certificates in Nginx Proxy Manager"
echo "   3. Set up proper domain names"
echo "   4. Configure firewall rules if needed"
echo "   5. Regular backups are recommended"
echo ""
echo "📖 Next steps:"
echo "   1. Access Nginx Proxy Manager and change default credentials"
echo "   2. Set up SSL certificates for your domains"
echo "   3. Create proxy hosts pointing to n8n (localhost:5678)"
echo "   4. Access n8n and change default credentials"
echo "   5. Configure your first workflow!"
echo ""

# Check if reboot is needed for Docker group membership
if ! groups | grep -q docker; then
    warning "You may need to log out and log back in (or reboot) for Docker group membership to take effect."
fi

log "Installation script completed!"
