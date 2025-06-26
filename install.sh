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

# Update system packages
log "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install required packages
log "Installing required packages..."
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    unzip \
    wget

# Check if Docker is already installed
if command -v docker >/dev/null 2>&1; then
    log "Docker is already installed. Skipping Docker installation."
else
    log "Installing Docker..."
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index
    sudo apt update
    
    # Install Docker Engine
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    # Enable and start Docker service
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log "Docker installed successfully!"
fi

# Check if Docker Compose is available
if ! docker compose version >/dev/null 2>&1; then
    error "Docker Compose plugin is not available. Please check your Docker installation."
fi

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

# Start the stack
log "Starting the Docker stack..."
docker compose up -d

# Wait for services to be healthy
log "Waiting for services to start..."
sleep 30

# Check if services are running
if docker ps | grep -q nginx-proxy-manager && docker ps | grep -q n8n; then
    log "Services started successfully!"
else
    warning "Some services may not have started properly. Check with 'docker compose ps'"
fi

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
