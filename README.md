# HuihuNetFucker

A small utility to automatically log in to the Huihu campus network. It provides:
- A C++ binary (libcurl-based) for Linux desktops/servers
- Two portable shell scripts for OpenWrt/BusyBox environments:
  - HuihuBashWget.sh (uclient-fetch/wget based, recommended for OpenWrt)
  - HuihuBashCurl.sh (curl based)

Use this software responsibly and only on networks where you have authorization.


## 1) Linux (desktop/server) build and run

Requirements:
- CMake >= 3.20
- C++20 compiler (GCC/Clang)
- libcurl development headers

Install build dependencies:
- Debian/Ubuntu:
  - sudo apt update && sudo apt install -y build-essential cmake libcurl4-openssl-dev
- Fedora/RHEL:
  - sudo dnf install -y gcc-c++ make cmake libcurl-devel
- Arch:
  - sudo pacman -S base-devel cmake curl
- openSUSE:
  - sudo zypper install -y gcc-c++ cmake libcurl-devel

Build:
1. mkdir -p build && cd build
2. cmake ..
3. make -j

Configuration:
Create a config.toml in the project root:

```toml
username = "yourusername"
pwd = "yourpassword"
```

Run:
- From build directory: ./HuihuFucker


## 2) OpenWrt usage (recommended: HuihuBashWget.sh)

OpenWrt ships BusyBox and uclient-fetch by default on many targets. The HuihuBashWget.sh script uses uclient-fetch when available and falls back to wget. It also supports ping-based fast connectivity checks and logs via logger when available.

What the script does:
- Periodically checks Internet connectivity (ping then HTTP 204) with strict timeouts
- If offline, sends a JSON POST to the Huihu portal to authenticate
- Loops forever with a short sleep between checks

Portal endpoint and payload:
- URL: http://10.10.16.12/api/portal/v1/login
- JSON: {"domain":"telecom|cmcc|unicom","username":"<phone or account>","password":"<pwd>"}

Files of interest in this repo:
- HuihuBashWget.sh (recommended on OpenWrt)
- HuihuBashCurl.sh (requires curl on OpenWrt)

### 2.1 Install dependencies

Minimal (for HuihuBashWget.sh):
- uclient-fetch (preferred) or wget
- ping (for faster reachability checks; optional but recommended)
- logger (usually in BusyBox; optional)

Commands (pick what you need):
- opkg update
- opkg install uclient-fetch
- opkg install wget-ssl ca-bundle ca-certificates  # if you need HTTPS to external check endpoints
- opkg install iputils-ping  # or install busybox-full if your BusyBox lacks ping
- Optional for curl-based script: opkg install curl

### 2.2 Configure the script

Open and edit HuihuBashWget.sh to set at least these variables:
- HUIHU_ACC: your account/phone number
- HUIHU_PWD: your password
- HUIHU_TELECOM: one of: telecom, cmcc, unicom
- CONNECTIVITY_URL: HTTP endpoint for connectivity check (defaults to Google 204)
- PING_HOST: a fast ICMP target (e.g., 1.1.1.1)
- HUIHU_CHECK_INTERVAL_S: recheck interval in seconds (default 15)
- CONNECT_TIMEOUT_S: timeout per connectivity probe (default 5)
- AUTH_TIMEOUT_S: timeout for auth HTTP request (default 8)
- DEBUG: set to 1 for verbose logs

Security tip: keep credentials private. Restrict file permissions:
- chmod 700 HuihuBashWget.sh

### 2.3 Run manually (foreground or background)

Foreground run (for testing):
- sh ./HuihuBashWget.sh

Background run with logging to system log:
- nohup sh /root/HuihuBashWget.sh >/dev/null 2>&1 &
- View logs: logread -e huihu-net

### 2.4 Autostart on boot (procd service)

Place the script in a stable path, e.g. /usr/bin/HuihuBashWget.sh, and make it executable:
- cp HuihuBashWget.sh /usr/bin/
- chmod +x /usr/bin/HuihuBashWget.sh

Create /etc/init.d/huihu-net with the following content:

```sh
#!/bin/sh /etc/rc.common
# OpenWrt procd service for HuihuBashWget.sh

START=95
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /bin/sh /usr/bin/HuihuBashWget.sh
    procd_set_param respawn 300 3 10  # threshold, retry, timeout
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
```

Enable and start the service:
- /etc/init.d/huihu-net enable
- /etc/init.d/huihu-net start

Check status and logs:
- ps w | grep HuihuBashWget.sh | grep -v grep
- logread -e huihu-net

### 2.5 Alternative: using the curl-based script

If you prefer curl or already have it installed, you can use HuihuBashCurl.sh. It behaves similarly but depends on curl.

Install:
- opkg update && opkg install curl

Configure inside HuihuBashCurl.sh:
- HUIHU_ACC, HUIHU_PWD, HUIHU_TELECOM, HUIHU_CHECK_INTERVAL_S, CONNECTIVITY_URL

Run:
- sh ./HuihuBashCurl.sh

Autostart: use the same procd init script as above, but change the command to:
- procd_set_param command /bin/sh /usr/bin/HuihuBashCurl.sh

### 2.6 Troubleshooting

- Not in campus network; exiting.
  - The portal may be unreachable from your current network. The script will exit to avoid looping when off-campus.
- Authentication error; will retry.
  - Wrong domain (HUIHU_TELECOM) or credentials. Try telecom, cmcc, or unicom as appropriate.
- Socket/curl error during auth; will retry.
  - Temporary network issues; the script will back off and retry.
- Connectivity checks never time out.
  - We set strict per-attempt timeouts: ping uses -W and -w, HTTP uses -T and --tries=1. Adjust CONNECT_TIMEOUT_S if your network is very slow.
- Need different connectivity endpoints.
  - Change CONNECTIVITY_URL (HTTP 204 URL) and PING_HOST to local or ISP-hosted services.
- See raw HTTP responses.
  - Set DEBUG=1 to print response bodies (and more detailed logs).


## 3) Notes and caveats

- The scripts and binary are intended for environments where you are authorized to authenticate to the Huihu portal.
- Credentials are stored in plain text. Consider restricting permissions or using a safe configuration store.
- The portal URL (10.10.16.12) and parameters may vary between campuses. Adjust PORTAL_URL or payload fields if your portal differs.
- On heavily restricted builds, some BusyBox options may be missing (e.g., ping -w). The script detects available tools and falls back where possible, but you may need to install iputils-ping or busybox-full.


## 4) Quick reference

- Linux build: mkdir -p build && cd build && cmake .. && make -j
- Config file: config.toml with username and pwd keys in project root
- OpenWrt run (wget/uclient-fetch): sh /usr/bin/HuihuBashWget.sh
- Logs on OpenWrt: logread -e huihu-net
- Autostart: /etc/init.d/huihu-net enable && /etc/init.d/huihu-net start


---

Legal/Disclaimer: This project is provided "as is" without warranty of any kind. Use at your own risk and ensure you comply with your institution's acceptable use policies.
