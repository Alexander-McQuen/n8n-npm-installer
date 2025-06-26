# 🚀 n8n + Nginx Proxy Manager Auto-Installer

Easy one-line installation of n8n (workflow automation) and Nginx Proxy Manager on Ubuntu 22+

## ⚡ Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/YOUR-USERNAME/n8n-npm-installer/main/install.sh | bash
```

🎯 What This Installs

Docker (if not already installed)
n8n - Powerful workflow automation tool
Nginx Proxy Manager - Easy SSL and reverse proxy management
Auto-update system with Watchtower

🌐 Access Your Services
After installation:

Nginx Proxy Manager: http://your-server-ip:81
n8n: http://your-server-ip:5678

🔐 Default Credentials (Change Immediately!)

Nginx Proxy Manager: admin@example.com / changeme
n8n: admin / changeme123

🛠️ Requirements

Ubuntu 22.04 or newer
Sudo privileges
Internet connection

📋 What to Do After Installation

Change default passwords
Set up SSL certificates in Nginx Proxy Manager
Configure your domains
Start creating workflows in n8n!

🆘 Support
If you encounter issues, please check:

Docker is running: sudo systemctl status docker
Services are up: docker ps
Logs: docker compose logs -f

📜 License
