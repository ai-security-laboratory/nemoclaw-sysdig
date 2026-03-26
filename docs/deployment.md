# Deployment Guide

## Prerequisites

On your local machine:
- `yq` — YAML parser: `brew install yq`
- `rsync` — file sync: usually pre-installed
- SSH access to your target VMs

On the target VM:
- Python 3.11+
- `rsync`

---

## 1. Configure local secrets

```bash
cp config/env.example .env
```

Edit `.env` with:
- `NVIDIA_API_KEY` — from [build.nvidia.com](https://build.nvidia.com)
- `SYSDIG_SECURE_TOKEN` — from Sysdig Secure → Settings → API Tokens
- `SYSDIG_URL` — your Sysdig tenant URL

---

## 2. Configure target VMs

```bash
cp config/targets.example.yaml config/targets.yaml
```

Edit `config/targets.yaml` with your VM's IP, SSH user, and key path. File is gitignored.

---

## 3. Deploy

```bash
make deploy SCENARIO=01-security-triage TARGET=my-oracle-vm
```

This will:
1. `rsync` the scenario files to `/opt/nemoclaw/01-security-triage/` on the VM
2. Upload `.env` over SCP
3. Run `setup.sh` remotely (creates Python venv, installs deps)

---

## 4. Run tests

**Locally (unit tests, no credentials):**
```bash
make test SCENARIO=01-security-triage
```

**Remotely (integration tests on the VM):**
```bash
make test SCENARIO=01-security-triage TARGET=my-oracle-vm
```

---

## 5. Teardown

```bash
make teardown SCENARIO=01-security-triage TARGET=my-oracle-vm
```

Removes `/opt/nemoclaw/01-security-triage` from the VM. Prompts for confirmation.

---

## SSH key setup

The deploy scripts use the SSH key specified in `config/targets.yaml` (falls back to `SSH_KEY_PATH` env var). Make sure the public key is in `~/.ssh/authorized_keys` on the VM.

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@<vm-ip>
```
