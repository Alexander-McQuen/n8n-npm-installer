# 📚 Complete Guide: Upload Script to GitHub & Create One-Line Installer

## 🎯 Goal
Create a GitHub repository so anyone can install your n8n + Nginx Proxy Manager setup with just one command:
```bash
curl -sSL https://raw.githubusercontent.com/YOUR-USERNAME/n8n-npm-installer/main/install.sh | bash
```

---

## 📋 Step 1: Create a GitHub Account (if you don't have one)

1. Go to [github.com](https://github.com)
2. Click **"Sign up"**
3. Enter your details:
   - Username (this will be in your installation URL)
   - Email address
   - Password
4. Verify your account via email
5. Choose the **free plan**

---

## 📁 Step 2: Create a New Repository

1. **Log into GitHub**
2. Click the **green "New"** button (or the **"+"** in top right → **"New repository"**)
3. Fill in the repository details:
   - **Repository name**: `n8n-npm-installer` (or any name you prefer)
   - **Description**: `Easy one-line installer for n8n and Nginx Proxy Manager on Ubuntu`
   - **Make it Public** ✅ (so anyone can access the install script)
   - **Check "Add a README file"** ✅
4. Click **"Create repository"**

---

## 📝 Step 3: Upload Your Installation Script

### Method A: Using GitHub Web Interface (Easiest)

1. **In your new repository**, click **"Add file"** → **"Create new file"**
2. **Name the file**: `install.sh`
3. **Copy and paste** the entire installation script from the previous artifact into the file
4. **Scroll down** to "Commit new file"
5. **Add a commit message**: `Add n8n and Nginx Proxy Manager installer script`
6. Click **"Commit new file"**

### Method B: Upload via File Upload

1. **In your repository**, click **"Add file"** → **"Upload files"**
2. **Save the script** to your computer as `install.sh`
3. **Drag the file** into the upload area
4. **Add commit message**: `Add installer script`
5. Click **"Commit changes"**

---

## 📄 Step 4: Create a README File

1. **Click on the README.md file** in your repository
2. **Click the pencil icon** (Edit) in the top right
3. **Replace the content** with this template:

```markdown
# 🚀 n8n + Nginx Proxy Manager Auto-Installer

Easy one-line installation of n8n (workflow automation) and Nginx Proxy Manager on Ubuntu 22+

## ⚡ Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/Alexander-McQuen/n8n-npm-installer/main/install.sh | bash
```

> **Replace `YOUR-USERNAME` with your actual GitHub username!**

## 🎯 What This Installs

- **Docker** (if not already installed)
- **n8n** - Powerful workflow automation tool
- **Nginx Proxy Manager** - Easy SSL and reverse proxy management
- **Auto-update system** with Watchtower

## 🌐 Access Your Services

After installation:
- **Nginx Proxy Manager**: `http://your-server-ip:81`
- **n8n**: `http://your-server-ip:5678`

## 🔐 Default Credentials (Change Immediately!)

- **Nginx Proxy Manager**: `admin@example.com` / `changeme`
- **n8n**: `admin` / `changeme123`

## 🛠️ Requirements

- Ubuntu 22.04 or newer
- Sudo privileges
- Internet connection

## 📋 What to Do After Installation

1. Change default passwords
2. Set up SSL certificates in Nginx Proxy Manager
3. Configure your domains
4. Start creating workflows in n8n!

## 🆘 Support

If you encounter issues, please check:
- Docker is running: `sudo systemctl status docker`
- Services are up: `docker ps`
- Logs: `docker compose logs -f`

## 📜 License

MIT License - Feel free to use and modify!
```



