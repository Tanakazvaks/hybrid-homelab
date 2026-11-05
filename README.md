# Hybrid Linux/Windows Homelab

A virtualized enterprise-style lab built on a Windows laptop with VirtualBox: a **Windows Server 2022 domain controller** (AD DS, DNS, DHCP) and **Ubuntu 26.04 servers joined to Active Directory with SSSD**, all managed from a single **Ansible control node over SSH (Linux) and WinRM (Windows)**, plus **PowerShell automation** for user provisioning and health reporting.

## Results

| What | Manual | Automated |
|---|---|---|
| New Linux server: patched, hardened, AD-joined | ~50 min | **~20 min end to end**, with the Ansible run itself under 5 min |
| Create 8 AD users with OUs and group membership | ~15–20 min in ADUC | **1.6 seconds** from a CSV |
| Re-running any playbook or script | n/a | **Idempotent**: `changed=0` / users skipped |

## Architecture

```mermaid
flowchart LR
    subgraph LabNet["LabNet - VirtualBox NAT Network 10.10.10.0/24"]
        DC01["DC01 - 10.10.10.10<br/>Windows Server 2022<br/>AD DS - DNS - DHCP"]
        LNX01["LNX01 - 10.10.10.21<br/>Ubuntu 26.04<br/>Ansible control node"]
        LNX02["LNX02 - 10.10.10.22<br/>Ubuntu 26.04"]
        LNX03["LNX03 - 10.10.10.23<br/>Ubuntu 26.04<br/>built by Ansible"]
    end
    LNX01 -- "SSH" --> LNX02
    LNX01 -- "SSH" --> LNX03
    LNX01 -- "WinRM (NTLM, encrypted)" --> DC01
    LNX01 & LNX02 & LNX03 -- "Kerberos / LDAP via SSSD" --> DC01
```

| Host | OS | Role | IP |
|---|---|---|---|
| DC01 | Windows Server 2022 | AD DS, DNS, DHCP (scope .100–.200) | 10.10.10.10 |
| LNX01 | Ubuntu 26.04 LTS | Ansible control node, domain member | 10.10.10.21 |
| LNX02 | Ubuntu 26.04 LTS | Domain member | 10.10.10.22 |
| LNX03 | Ubuntu 26.04 LTS | Domain member, built end to end by Ansible | 10.10.10.23 |

## What's in this repo

```
├── ansible.cfg                    # inventory path, sudo.ws for Ubuntu 26.04 (see Challenges)
├── inventory.ini                  # [linux] over SSH, [windows] over WinRM
├── site.yml                       # runs baseline + domain join
├── group_vars/windows/vault.yml   # DC01 credentials, encrypted with Ansible Vault (AES256)
├── playbooks/
│   ├── linux-baseline.yml         # patching, packages, chrony, SSH hardening, UFW, auto-updates
│   ├── linux-domain-join.yml      # realmd/SSSD join, mkhomedir, AD-group sudo
│   └── windows-dc.yml             # DC roles/services, deploy scripts, run health check, fetch report
├── scripts/
│   ├── New-LabUsers.ps1           # bulk AD user provisioning from CSV (-WhatIf, idempotent, logged)
│   ├── Get-ServerHealth.ps1       # disk/memory/services/events health check, console + HTML
│   └── new-hires.csv              # sample input
└── docs/screenshots/
```

## Highlights

**Active Directory + Linux integration**
- Built a `homelab.local` forest with an OU structure (`Lab → Users / Groups`) and DHCP authorized in AD.
- Joined Ubuntu servers to AD with **realmd + SSSD**. AD users log into Linux with their AD password, home directories are created on first login, and **sudo is granted through the AD `LinuxAdmins` group** with no local accounts.
- SSSD ID mapping gives each AD user the **same UID on every Linux server**, which keeps file ownership consistent.

**Ansible (SSH + WinRM)**
- `linux-baseline.yml` applies updates, installs a standard toolset, sets the time zone and NTP, hardens SSH (`PermitRootLogin no`, `MaxAuthTries 3`, validated with `sshd -t` before applying), enables UFW with deny-by-default inbound, and turns on unattended security upgrades.
- `linux-domain-join.yml` checks membership before joining, so re-runs skip the join. The AD join password is prompted at runtime and never logged (`no_log`).
- `windows-dc.yml` manages DC01 over **WinRM with NTLM message encryption**. It enforces DC roles and services, deploys PowerShell scripts **from Git**, runs the health check remotely and fetches the HTML report back.
- Windows credentials are stored with **Ansible Vault**.

**PowerShell**
- `New-LabUsers.ps1`: builds usernames, creates department OUs on demand, forces a password change at first logon, adds group memberships, skips existing users, supports `-WhatIf`, and writes a CSV log.
- `Get-ServerHealth.ps1`: PASS/WARN/FAIL checks for disk, memory, 6 DC services and System log errors, with colour console output and an HTML report.

## Challenges solved

| Problem | Cause | Fix |
|---|---|---|
| VMs crawling; VirtualBox "turtle" mode | Windows Home with Memory Integrity / VBS holding VT-x (`HM: fall back to NEM`) | Disabled Memory Integrity, VirtualMachinePlatform and hypervisorlaunchtype; confirmed `HypervisorPresent = False` |
| Ansible `Timeout waiting for privilege escalation prompt` | Ubuntu 26.04 ships **sudo-rs**, whose prompt Ansible doesn't recognize | `become_exe = /usr/bin/sudo.ws` (classic sudo) in `ansible.cfg` |
| Cloned VM had no network | Installer netplan config pinned the interface to the original **MAC address** | Removed the `match: macaddress` / `set-name` lines |
| Clone reported the source VM's MAC | Cloned from a **live snapshot**, so it resumed saved memory | `VBoxManage discardstate` before first boot, then a cold boot |
| Clones shared identity | Copied `/etc/machine-id` and SSH host keys | Regenerated both on each clone |
| DC01 `^?` in `chronyc sources` | w32time advertises ~10 s root dispersion; VirtualBox guest time sync interferes | Configured DC01 as a reliable NTP source (pool.ntp.org); documented as a known issue, since skew stays well inside Kerberos's 5-minute limit |
| Health check WARN: 5 System errors | Triage showed DHCP authorization errors from the install window plus benign VM-reboot service events | No action needed; a future improvement is an allow-list of known-benign event IDs |

## How to run

```bash
# Linux: baseline + domain join (prompts for sudo and AD join passwords)
ansible-playbook site.yml -K

# New server only
ansible-playbook site.yml -K --limit lnx03

# Windows DC (prompts for the vault password)
ansible-playbook playbooks/windows-dc.yml --ask-vault-pass
```

```powershell
# On DC01: dry run, then create users
.\New-LabUsers.ps1 -CsvPath .\new-hires.csv -WhatIf
.\New-LabUsers.ps1 -CsvPath .\new-hires.csv

# Health report
.\Get-ServerHealth.ps1
```

## Screenshots

### Infrastructure
| VirtualBox lab | LabNet (10.10.10.0/24) | DC01 Server Manager |
|---|---|---|
| ![](docs/screenshots/01-virtualbox-manager.png) | ![](docs/screenshots/02-labnet-network.png) | ![](docs/screenshots/03-dc01-server-manager.png) |

### Active Directory + Linux
| OU structure and user | LNX01 in AD Computers | LNX01 joined (realm list) |
|---|---|---|
| ![](docs/screenshots/10-ad-user-group.png) | ![](docs/screenshots/11-ad-computer-lnx01.png) | ![](docs/screenshots/09-lnx01-domain-joined.png) |

| AD user login + sudo on LNX01 | AD user login on LNX02 |
|---|---|
| ![](docs/screenshots/12-ad-user-linux-login.png) | ![](docs/screenshots/13-ad-user-lnx02-login.png) |

### Ansible
| Ping | Baseline re-run (changed=0) | LNX03 joined by Ansible |
|---|---|---|
| ![](docs/screenshots/14-ansible-ping.png) | ![](docs/screenshots/16-ansible-baseline-idempotent.png) | ![](docs/screenshots/18-lnx03-joined-by-ansible.png) |

| WinRM ping | Vault + WinRM | Windows DC playbook |
|---|---|---|
| ![](docs/screenshots/26-ansible-win-ping.png) | ![](docs/screenshots/27-ansible-vault-winrm.png) | ![](docs/screenshots/28-ansible-windows-dc.png) |

### PowerShell
| Bulk users: -WhatIf | Users created | Health check console |
|---|---|---|
| ![](docs/screenshots/19-ps-bulk-users-whatif.png) | ![](docs/screenshots/20-ps-bulk-users-created.png) | ![](docs/screenshots/23-ps-health-console.png) |

| Health check HTML | Event triage |
|---|---|
| ![](docs/screenshots/24-ps-health-html.png) | ![](docs/screenshots/25-ps-event-triage.png) |

## Next steps
- Prometheus + Grafana monitoring stack with node_exporter and windows_exporter
- Kubernetes (kubeadm) cluster with a Jenkins CI/CD pipeline
- Ansible roles + Molecule tests; Windows hardening baseline playbook
---

## Part 2: Monitoring, Alerting & Performance Tuning

Prometheus and Grafana run in Docker on lnx01 and monitor every server in the lab: node_exporter on the 3 Ubuntu servers and windows_exporter on the domain controller. Alert rules catch outages and overloads, and fio benchmarks were used to tune disk I/O with measured before/after results.

### Results

- **4/4 hosts monitored** (3 Linux + 1 Windows) at 15-second intervals, with dashboards and datasource provisioned as code
- **HostDown alert** fired within 1 minute of a server going offline and **cleared automatically** when it recovered
- **Disk I/O tuning: +40% IOPS** (3,048 → 4,282) and **~30% lower latency** (10.4 ms → 7.5 ms) on 4K random read/write
- **HighCPU alert** went pending → firing after 5 minutes at 100% CPU (stress-ng) and resolved on its own afterwards

### Architecture

```mermaid
flowchart LR
    subgraph LNX01["lnx01 (Docker)"]
        P[Prometheus :9090] --> G[Grafana :3000]
    end
    P -- scrape :9100 --> N1[lnx01 node_exporter]
    P -- scrape :9100 --> N2[lnx02 node_exporter]
    P -- scrape :9100 --> N3[lnx03 node_exporter]
    P -- scrape :9182 --> W[dc01 windows_exporter]
    P -- evaluates --> A[alerts.yml]
```

### What was added

| File | Purpose |
|---|---|
| `playbooks/docker.yml` | Installs Docker + Compose on the monitoring server |
| `playbooks/exporters-linux.yml` | Installs node_exporter, opens UFW only to LabNet and the Docker network |
| `playbooks/exporters-windows.yml` | Downloads the latest windows_exporter MSI, installs it over WinRM, adds a firewall rule |
| `playbooks/disk-tuning.yml` | Sets the `none` I/O scheduler via a persistent udev rule |
| `monitoring/docker-compose.yml` | Prometheus + Grafana stack with persistent volumes |
| `monitoring/prometheus/prometheus.yml` | Scrape targets with host/os/role labels |
| `monitoring/prometheus/alerts.yml` | HostDown, DiskSpaceLow, HighMemory, HighCPU rules |
| `monitoring/grafana/provisioning/` | Datasource and Homelab Overview dashboard as code |

### Performance tuning

Tested on lnx03 with fio (4K blocks, 70% read / 30% write, queue depth 32, direct I/O, 60 s per run).

| Scheduler | Read IOPS | Write IOPS | Total IOPS | Avg read latency |
|---|---|---|---|---|
| mq-deadline (default), run 1 | 2,135 | 913 | 3,048 | 10.4 ms |
| mq-deadline (default), run 2 | 2,065 | 884 | 2,949 | 10.8 ms |
| **none (tuned)** | **2,996** | **1,286** | **4,282** | **7.5 ms** |

The disks are virtual, and VirtualBox and the host OS already schedule the physical I/O, so the guest-level `mq-deadline` scheduler was a redundant second layer. The baseline was run twice to confirm the gain wasn't noise, then the change was rolled out to all Linux servers with Ansible.

### Challenges

| Problem | Cause | Fix |
|---|---|---|
| Community Windows dashboard showed N/A everywhere | windows_exporter v0.32 renamed its metrics | Built and provisioned a custom dashboard using the new metric names |
| Prometheus couldn't scrape lnx01's own exporter | Container traffic comes from the Docker network (172.16.0.0/12), not LabNet | Added a scoped UFW rule for the Docker subnet |
| HostDown kept firing after lnx02 came back | lnx02 was offline when the exporter playbook ran, so node_exporter was never installed | Re-ran the playbook with `--limit lnx02` |
| lnx01 ran low on disk for Docker images | Ubuntu installer only allocated half the volume group | Grew the root LV online with `lvextend -r -l +100%FREE` |

### How to run

```bash
ansible-playbook playbooks/docker.yml -K
ansible-playbook playbooks/exporters-linux.yml -K
ansible-playbook playbooks/exporters-windows.yml --ask-vault-pass
ansible-playbook playbooks/disk-tuning.yml -K
cd monitoring && docker compose up -d   # needs monitoring/.env with GRAFANA_ADMIN_PASSWORD
```

### Screenshots

| | |
|---|---|
| ![Prometheus targets](screenshots/p2-01-prometheus-targets.png) Prometheus scrape targets | ![Grafana](screenshots/p2-02-grafana-linux.png) Grafana metrics |
| ![HostDown firing](screenshots/p2-04-prometheus-alert-firing.png) HostDown firing for lnx02 | ![Alerts cleared](screenshots/p2-05-prometheus-alerts-cleared.png) Alert cleared after recovery |
| ![All hosts up](screenshots/p2-06-all-hosts-up.png) Homelab Overview, all hosts up | ![Disk tuning](screenshots/p2-07-disk-tuning-ansible.png) Disk tuning rolled out with Ansible |
| ![CPU stress](screenshots/p2-08-grafana-cpu-stress.png) lnx03 at 100% CPU under stress-ng | ![HighCPU history](screenshots/p2-09-highcpu-alert-history.png) HighCPU pending → firing → resolved |
