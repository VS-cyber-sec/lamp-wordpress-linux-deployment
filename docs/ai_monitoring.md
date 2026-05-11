# AI Monitoring — Setup and Usage

`ai_monitor.sh` uses the Claude API to analyse your server's logs and produce a plain-English health report every day.

---

## What it analyses

Every day at 7 AM (configurable), the script collects:

- Apache error log (last 24 hours)
- Apache access log summary (last 24 hours)
- fail2ban ban/unban events
- Disk usage across `/` and `/backup`
- Memory usage (`free -h`)
- Service status: Apache, MariaDB, fail2ban
- WordPress version

It sends all of this to Claude and gets back a structured report.

---

## Setup

### 1. Get a Claude API key

Sign up at [console.anthropic.com](https://console.anthropic.com) and create an API key. The free tier includes enough tokens for daily server reports.

### 2. Add the key to config.env

```bash
nano config/config.env
```

Set:
```
AI_MONITORING_ENABLED=true
ANTHROPIC_API_KEY=sk-ant-your-actual-key-here
AI_REPORT_EMAIL=true     # set false if you don't want emails
```

### 3. Install the cron job

```bash
sudo bash scripts/ai_monitor.sh --setup
```

This creates `/etc/cron.d/ai-monitor` to run the analysis daily at 7 AM.

### 4. Run immediately to test

```bash
sudo bash scripts/ai_monitor.sh
```

---

## Reading reports

Reports are saved as Markdown files in `ai/reports/YYYY-MM-DD.md`.

**View today's report:**
```bash
sudo bash scripts/ai_monitor.sh --report
# or
cat ai/reports/$(date +%Y-%m-%d).md
```

**List all reports:**
```bash
ls -la ai/reports/
```

---

## Example report output

```markdown
# AI Health Report — 2025-07-15

## Overall Status
✅ Healthy

## Summary
Server is operating normally. All three services (Apache, MariaDB, fail2ban)
are active. No unusual access patterns detected in the last 24 hours.
Disk usage is at 23% with ample headroom.

## Issues Found
None

## Security Events
- 3 IPs banned by fail2ban for WordPress login brute-force:
  192.168.1.44, 10.0.0.12, 185.234.x.x
- All bans applied within the configured 5-minute window

## Resource Health
- Disk (/): 23% used — healthy
- Disk (/backup): 41% used — healthy
- Memory: 687 MB used / 978 MB total — healthy

## Recommended Actions
No action needed.
```

---

## Customising the prompts

The AI prompts are in `ai/prompts/`:

- `log_analysis.txt` — how to analyse error logs
- `health_check.txt` — how to summarise server health
- `anomaly_detect.txt` — what to look for in access logs

Edit these to change the style, depth, or focus of the reports. The `{{PLACEHOLDER}}` tokens are replaced with actual log data at runtime.

---

## Cost

Each daily report uses approximately 2,000–4,000 tokens (input + output combined). At current Claude API pricing, this is well under $0.01 per report.
