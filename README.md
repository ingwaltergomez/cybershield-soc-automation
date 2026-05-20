# 🔐 CyberShield GT - Automated SOC Deployment

> Automated deployment system for multi-tenant Security Operations Center (SOC) infrastructure using Wazuh.

## 📋 Overview

Creates isolated Wazuh stacks (Manager + Indexer + Dashboard) with automatic SSL/DNS configuration in under 3 minutes.

**Key Achievement:** Reduced manual deployment time from 2-3 hours to 3 minutes (95% reduction).

## 🏗️ Architecture

Dedicated stack per client approach:
- Each client gets isolated Wazuh components
- Automatic port detection
- SSL via Nginx Proxy Manager
- Let's Encrypt wildcard certificates

## ✨ Features

- ✅ Zero-touch deployment (3 minutes)
- ✅ Automatic SSL certificates
- ✅ Unique per-client authentication
- ✅ Port auto-detection
- ✅ DNS automation via NPM API
- ✅ Credential management

## 🛠️ Tech Stack

- **SIEM/EDR:** Wazuh 4.14.4
- **Orchestration:** Docker Compose
- **Reverse Proxy:** Nginx Proxy Manager
- **Certificates:** Let's Encrypt
- **OS:** Debian 12
- **Scripting:** Bash

## 🚀 Quick Start

```bash
# Configure credentials
cp scripts/lib/config.sh.example scripts/lib/config.sh
# Edit config.sh with your NPM credentials

# Create new client
./scripts/crear-cliente.sh client-name
```

## 🎬 Live Demo

Watch the complete automated deployment process:

![Automated Deployment](docs/screenshots/cybershield-soc-automation.gif)

**What you see:** Complete client creation from command execution to production-ready stack in **~3 minutes** ⚡

---

## 📸 Production Environment

### Wazuh Dashboard - Security Monitoring
![Wazuh Dashboard](docs/screenshots/wazuh-dashboard.png)

*Real-time security event monitoring with active agents across multiple clients*

### Docker Orchestration - Multi-Client Deployment
![Docker Containers](docs/screenshots/docker-containers.gif)

*15 containers running across 5 client stacks with automatic resource management*

### SSL Automation - Nginx Proxy Manager
![NPM Proxies](docs/screenshots/npm-proxies.png)

*Automated Let's Encrypt SSL configuration for 5 client subdomains*

📁 **[View complete visual documentation →](docs/SCREENSHOTS.md)**

---

## 🔧 Key Technical Challenges Solved

### Wazuh Multi-Tenancy Bug
**Problem:** Users created via API never receive correct `backend_roles`

**Solution:** Architectural change to dedicated stacks per client

### NPM Authentication Conflicts
**Problem:** Access Lists caused 401 errors

**Solution:** Removed Access List layer

### Secure Password Generation
**Solution:** Native `/dev/urandom` approach
```bash
head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9@#%-_=' | head -c 24
```

## 🎓 Learning Outcomes

Skills developed:
- SOC Operations & Wazuh deployment
- Docker Compose orchestration
- REST API integration
- Bash scripting & automation
- Security architecture design
- Problem solving & root cause analysis

## 🚫 Project Status

**Status:** Closed after 5 months of development

**Why?** Market analysis revealed:
- Single-person operation cannot deliver true 24/7 SOC
- TAM too small for venture-scale returns
- Better ROI via consulting/employment

**Key lesson:** Technical success ≠ Business viability

## 📊 Project Outcomes

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Deployment time | 2-3 hours | 3 minutes | 95% |
| Error rate | ~20% | <1% | 95% |
| Cost per client | $5K-15K/mo | $249/mo | 95% |

## 🤝 Credits

Built by Walter Gómez Cruz  
ISO 27001 Lead Implementer | DevSecOps Engineer

## 📝 License

MIT License

## 📧 Contact

- LinkedIn: [linkedin.com/in/ingwaltergomez](https://linkedin.com/in/ingwaltergomez)
- Email: wgomez@ingwaltergomez.com
