# Security Hardening Guide

Every security measure applied by `harden_wordpress.sh`, explained.

---

## 1. File permissions (chmod 755/644)

**What:** Sets all directories to `755` and all files to `644` using `find … -exec chmod`.

**Why:** If any file is writable by the web server user (`www-data`) AND readable/writable by others, an attacker who exploits a vulnerability can write malicious PHP files to your site. `644` means only the owner can write — everyone else reads.

**Critical exception:** `wp-config.php` is set to `640` — readable only by the owner and group, not by others at all.

---

## 2. DISALLOW_FILE_EDIT

**What:** Adds `define('DISALLOW_FILE_EDIT', true)` to `wp-config.php`.

**Why:** WordPress ships with a built-in code editor (Dashboard → Appearance → Theme File Editor). If an attacker ever gains your admin credentials, they can inject malicious PHP code directly — no SSH needed, no server access. This constant removes that editor entirely.

---

## 3. Apache autoindex disabled

**What:** Runs `a2dismod autoindex` and adds `Options -Indexes` to the VirtualHost.

**Why:** Without this, navigating to any folder without an index file shows a full file listing. Attackers routinely browse `wp-content/uploads/` looking for backup SQL files, debug logs, or sensitive data.

---

## 4. Apache security headers

**What:** Adds HTTP response headers via `mod_headers`.

| Header | Value | Prevents |
|--------|-------|---------|
| X-Frame-Options | SAMEORIGIN | Clickjacking attacks |
| X-Content-Type-Options | nosniff | MIME-type sniffing attacks |
| X-XSS-Protection | 1; mode=block | Reflected XSS in older browsers |
| Referrer-Policy | strict-origin-when-cross-origin | Referrer data leakage |
| Strict-Transport-Security | max-age=31536000 | SSL stripping (enabled after SSL) |

---

## 5. UFW firewall

**What:** Installs UFW and opens only ports 22, 80, 443.

**Why:** A fresh Ubuntu server has no OS-level firewall. Any service accidentally started on an unusual port (e.g. MariaDB on 3306) would be publicly accessible. UFW blocks everything not explicitly allowed.

**Rules applied:**
```
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH (your IP should further restrict this in AWS Security Group)
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
```

---

## 6. fail2ban

**What:** Installs fail2ban and configures jails for SSH, Apache, and WordPress login.

**Why:** Brute-force attacks against `wp-login.php` are constant on the internet. fail2ban watches the access log and automatically bans IPs that make too many failed login attempts.

**Jails configured:**
- `sshd` — 5 failed SSH logins → 1-hour ban
- `apache-auth` — 3 failed Apache auth attempts → ban
- `apache-badbots` — scanner user agents → ban
- `wordpress-login` — 5 POST attempts to wp-login.php in 5 minutes → ban

---

## 7. xmlrpc.php blocked

**What:** Blocks access to `xmlrpc.php` via `.htaccess`.

**Why:** WordPress's XML-RPC endpoint allows password brute-forcing at massive scale using a single request (the `multicall` method). Unless you use Jetpack or another XML-RPC-dependent plugin, block it entirely.

---

## 8. PHP execution blocked in uploads

**What:** Adds a `.htaccess` to `wp-content/uploads/` blocking PHP execution.

**Why:** The most common WordPress attack: upload a malicious PHP file disguised as an image, then execute it directly via its URL. Even if a plugin allows an attacker to upload a `.php` file, it can't execute if PHP is blocked in that directory.

---

## 9. ServerTokens Prod + ServerSignature Off

**What:** Hides Apache version from HTTP response headers and error pages.

**Why:** Version disclosure helps attackers target known vulnerabilities in specific Apache versions. `ServerTokens Prod` reduces `Server: Apache/2.4.52 (Ubuntu)` to just `Server: Apache`.

---

## 10. Automatic security updates

**What:** Installs and configures `unattended-upgrades` for the `security` pocket.

**Why:** Security patches are released constantly. Manual updates are slow. Automatic security updates close known vulnerabilities within hours of the patch being available. Non-security updates remain manual so you control when major changes happen.
