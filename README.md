# ⚡ LAMP × WordPress Pro

> **One-command, production-grade WordPress on AWS EC2 — hardened, backed up, AI-monitored, and free-tier eligible.**

```
██╗      █████╗ ███╗   ███╗██████╗     ██╗    ██╗██████╗
██║     ██╔══██╗████╗ ████║██╔══██╗    ██║    ██║██╔══██╗
██║     ███████║██╔████╔██║██████╔╝    ██║ █╗ ██║██████╔╝
██║     ██╔══██║██║╚██╔╝██║██╔═══╝     ██║███╗██║██╔═══╝
███████╗██║  ██║██║ ╚═╝ ██║██║         ╚███╔███╔╝██║
╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝          ╚══╝╚══╝ ╚═╝
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![AWS Free Tier](https://img.shields.io/badge/AWS-Free%20Tier-orange?logo=amazonaws)](https://aws.amazon.com/free/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20LTS-E95420?logo=ubuntu)](https://ubuntu.com/)
[![AI Powered](https://img.shields.io/badge/AI-Claude%20Monitoring-blueviolet)](ai/)

---

## 🗺️ What this project does

Turns a blank Ubuntu 22.04 EC2 instance into a fully production-ready WordPress site in under 10 minutes.

| Phase | Script | What happens |
|-------|--------|--------------|
| 1️⃣ | `install_lamp.sh` | Installs Apache 2, MariaDB, PHP + all WP extensions |
| 2️⃣ | `install_wordpress.sh` | Downloads latest WordPress, sets up DB, writes wp-config |
| 3️⃣ | `harden_wordpress.sh` | Locks permissions, disables file editor, UFW + fail2ban |
| 4️⃣ | `ssl_setup.sh` | Free SSL via Let's Encrypt, auto-renewing |
| 5️⃣ | `backup.sh` | Encrypted rsync + mysqldump → S3, 28-day retention |
| 🤖 | `ai_monitor.sh` | Claude AI log analysis, anomaly detection, email reports |

---

## 🏗️ Architecture

```
                    ┌──────────────── AWS Cloud (Free Tier) ─────────────────┐
                    │                                                         │
  Internet ───────▶ │  ┌── Security Group ──────────────────────────────┐    │
                    │  │  Port 22   ✅ Your IP only  (SSH)              │    │
                    │  │  Port 80   ✅ Anywhere       (HTTP)            │    │
                    │  │  Port 443  ✅ Anywhere       (HTTPS)           │    │
                    │  │  All else  ❌ Silently blocked                 │    │
                    │  └────────────────────────────────────────────────┘    │
                    │                                                         │
                    │  ┌── EC2 t2.micro (Ubuntu 22.04) ─────────────────┐   │
                    │  │                                                  │   │
                    │  │   UFW Firewall (OS-level, belt + suspenders)    │   │
                    │  │                                                  │   │
                    │  │   Apache 2 ──► mod_php ──► WordPress            │   │
                    │  │      │             │           │                 │   │
                    │  │   SSL/TLS      PHP 8.1+    MariaDB              │   │
                    │  │   (Certbot)   extensions  wordpress_db          │   │
                    │  │                                                  │   │
                    │  │   fail2ban  ◄── watches ◄── /var/log/apache2/  │   │
                    │  │                                                  │   │
                    │  │   AI Monitor (cron, daily)                      │   │
                    │  │   Logs ──► Claude API ──► Email report          │   │
                    │  └──────────────────────────────────────────────────┘  │
                    │                                                         │
                    │  ┌── S3 Bucket ────────────────────────────────────┐   │
                    │  │  Encrypted weekly backups · 28-day retention    │   │
                    │  └─────────────────────────────────────────────────┘   │
                    └─────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### 1 — Launch EC2 (Ubuntu 22.04 LTS, t2.micro) and SSH in

```bash
ssh -i ~/wordpress-key.pem ubuntu@YOUR_ELASTIC_IP
```

### 2 — Clone and configure

```bash
git clone https://github.com/Vs-cyber-sec/lamp-wordpress-pro.git
cd lamp-wordpress-pro
cp config/config.example.env config/config.env
nano config/config.env        # fill in DB password, domain, email, API key
chmod +x scripts/*.sh
```

### 3 — Deploy everything

```bash
sudo bash scripts/deploy_all.sh
```

Or run phases individually:

```bash
sudo bash scripts/install_lamp.sh
sudo bash scripts/install_wordpress.sh
sudo bash scripts/harden_wordpress.sh
sudo bash scripts/ssl_setup.sh
sudo bash scripts/backup.sh --test
```

### 4 — Enable AI monitoring

```bash
# Set ANTHROPIC_API_KEY in config/config.env first
sudo bash scripts/ai_monitor.sh --setup
```

---

## 📁 Project Structure

```
lamp-wordpress-pro/
├── README.md
├── LICENSE
│
├── scripts/
│   ├── deploy_all.sh           ← Master: runs all phases in order
│   ├── install_lamp.sh         ← Phase 1: LAMP stack
│   ├── install_wordpress.sh    ← Phase 2: WordPress + DB
│   ├── harden_wordpress.sh     ← Phase 3: Security hardening
│   ├── ssl_setup.sh            ← Phase 4: Let's Encrypt SSL
│   ├── backup.sh               ← Backup: files + DB + S3
│   └── ai_monitor.sh           ← AI: log analysis + health reports
│
├── config/
│   ├── config.example.env      ← Template — copy to config.env
│   ├── apache_wordpress.conf   ← Apache VirtualHost config
│   ├── wp-config-template.php  ← WordPress config template
│   └── my.cnf.template         ← Secure MySQL credentials template
│
├── ai/
│   ├── prompts/
│   │   ├── log_analysis.txt    ← Prompt: Apache log analysis
│   │   ├── health_check.txt    ← Prompt: server health report
│   │   └── anomaly_detect.txt  ← Prompt: security anomaly detection
│   └── reports/                ← AI-generated reports saved here
│
└── docs/
    ├── aws_setup.md            ← Step-by-step EC2 launch guide
    ├── security.md             ← Every hardening step explained
    ├── backup_restore.md       ← How to restore from backup
    └── ai_monitoring.md        ← AI monitoring setup and usage
```

---

## 🛡️ Security improvements over the original

| Issue | Original | This version |
|-------|----------|--------------|
| DB password | Hardcoded in script | `~/.my.cnf` credentials file |
| Error handling | None | `set -euo pipefail` + `trap` on every script |
| DB setup | Manual | Fully automated with idempotency checks |
| OS firewall | None | UFW configured with minimal ruleset |
| Brute-force protection | None | fail2ban watching SSH + Apache |
| SSL | HTTP only | Let's Encrypt, auto-renews every 90 days |
| `wp-config.php` perms | 644 | 640, chowned to `www-data` |
| Backup password | Plaintext in command | `~/.my.cnf` — never in shell history |
| Backup destination | Local `/backup/` only | Local + S3 with AES encryption |
| Idempotency | Breaks on re-run | Safe to run multiple times |
| PHP extensions | `php-mysql` only | All WordPress-recommended extensions |
| Monitoring | None | AI-powered daily health reports |

---

## 🤖 AI Monitoring — how it works

`ai_monitor.sh` runs daily via cron. It:

1. Collects the last 24 hours of Apache error logs, access logs, fail2ban logs, and disk/memory stats
2. Sends them to the **Claude API** with a structured prompt
3. Gets back a plain-English report covering: anomalies found, top error patterns, security events, and recommended actions
4. Saves the report to `ai/reports/YYYY-MM-DD.md`
5. Optionally emails the report to you

See [`docs/ai_monitoring.md`](docs/ai_monitoring.md) for full setup.

---

## 💰 AWS Free Tier cost

| Resource | Free allowance | This project |
|----------|---------------|--------------|
| EC2 t2.micro | 750 hrs/month | ~744 hrs |
| EBS storage | 30 GB | 8 GB |
| S3 storage | 5 GB | < 1 GB |
| Data transfer | 15 GB out | Traffic-dependent |
| **Total** | | **$0 for 12 months** |

After 12 months: ~$12–15/month.

---

## 📄 License

MIT — use freely, modify, deploy, share.
