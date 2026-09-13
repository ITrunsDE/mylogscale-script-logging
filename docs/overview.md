# Choose a LogScale ingest path for scripts, files, and syslog

## Goal

Pick one ingest path for your situation, then follow the matching how-to. This page is the map: scripts that emit structured events, log files already on disk, and devices or services that speak syslog.

All paths target LogScale Cloud. Use a dedicated ingest token per destination repository. Do not put real tokens in Git, tickets, or screenshots.

Get every script package and the file-ingest samples from GitHub:

→ [ITrunsDE/mylogscale-script-logging](https://github.com/ITrunsDE/mylogscale-script-logging)

```bash
git clone https://github.com/ITrunsDE/mylogscale-script-logging.git
```

Folders: `powershell/`, `bash/`, `python/`, `file-ingest/`.

## Quick chooser

| Your situation | Start here |
|---|---|
| Windows script you can edit | [Add logging to an existing PowerShell script](../powershell/README.md) |
| Linux Bash script you can edit | [Add logging to an existing Bash script](../bash/README.md) |
| Python script you can edit (3.8+, stdlib only) | [Add logging to an existing Python script](../python/README.md) |
| Log file already on disk (text lines or JSON Lines) | [Ingest an existing log file with LogScale Collector](../file-ingest/README.md) |
| Network device or service sends syslog | [Build a Multi-Repository Syslog Server with LogScale Collector](https://mylogscale.com/howtos/build-a-multi-repository-syslog-server-with-logscale-collector) |
| UniFi Network appliances | [Forward UniFi Syslog to a Remote Server](https://mylogscale.com/howtos/forward-unifi-syslog-to-a-remote-server) after the syslog server howto |

If more than one row applies, run them as separate pipelines. Example: a script writes JSON Lines locally and a collector ships the file — that is the script article plus the same collector file pattern, not a second copy of the events through direct HTTPS unless you want duplicates.

## Script logging (PowerShell, Bash, Python)

Use these when you own the script and can add explicit log calls. Shared rules across the three languages:

- Fields: `timestamp`, `level`, `message`, `script_name`, `run_id` (one `run_id` per execution).
- Levels: `INFO`, `WARN`, `ERROR`.
- Config file: `logscale.json` with independent `direct_logging_enabled` and `local_logging_enabled`.
- Direct path: one HTTPS event per call, short timeout, no retries.
- Local path: UTF-8 JSON Lines, one file per script and UTC day, startup cleanup (default 14 days).
- Logging failures warn; the main script continues.

| Language | Platform notes | Dependencies | Package folder |
|---|---|---|---|
| PowerShell | Windows PowerShell 5 and PowerShell 7 | None (no extra modules) | [powershell/](https://github.com/ITrunsDE/mylogscale-script-logging/tree/main/powershell) |
| Bash | Linux | `curl`, `jq` | [bash/](https://github.com/ITrunsDE/mylogscale-script-logging/tree/main/bash) |
| Python | 3.8+ | Standard library only (`logscale.py`, not `logging.py`) | [python/](https://github.com/ITrunsDE/mylogscale-script-logging/tree/main/python) |

**Direct vs collector for scripts**

| Need | Switch |
|---|---|
| Fastest path to Cloud, script may wait on HTTPS | Direct on, local off |
| Script must not depend on network success; collector ships later | Direct off, local on |
| Both | Both on — expect duplicate events if the collector also reads those files into the same repository |

Install the collector when you use the local file path:

- [[howto:Install LogScale Collector on Windows]]
- Linux collector context: [[howto:Build a Multi-Repository Syslog Server with LogScale Collector]]

## Existing files

Use the file-ingest howto when the application already writes logs and you will not inject script helpers. Scope: one event per line — plain text with a leading timestamp, or JSON Lines with a `timestamp` field. Multiline records are a separate topic.

Samples and collector templates: [file-ingest/](https://github.com/ITrunsDE/mylogscale-script-logging/tree/main/file-ingest) in the companion repo. Point a collector file source at the path, attach `existing-text` or `existing-jsonl`, append a verification line, then search the repository.

## Syslog from devices and services

Do not rebuild syslog setup inside this series. Use the published guide: open UDP/TCP listeners on the collector, one sink per repository token, verify each route.

→ [Build a Multi-Repository Syslog Server with LogScale Collector](https://mylogscale.com/howtos/build-a-multi-repository-syslog-server-with-logscale-collector)

For UniFi senders, configure the appliance against that listener:

→ [Forward UniFi Syslog to a Remote Server](https://mylogscale.com/howtos/forward-unifi-syslog-to-a-remote-server)

## Suggested order if you are new to the series

1. Pick **one** script language you already run in production-like tests and complete direct delivery first.
2. Add the collector file path for that same example if you need durable local shipping.
3. Point the collector at one real existing log file (text or JSONL).
4. Only then open syslog listeners for network devices.

That order reuses one Cloud repository and one collector host without mixing too many failure domains on day one.

## What this series does not cover yet

- Multiline log records
- Self-hosted LogScale as the primary test target
- Automatic capture of all console output (script articles use explicit calls only)
- High-volume batching, retries, or background senders in the direct HTTPS examples

## All how-tos

1. [Add logging to an existing PowerShell script with LogScale](../powershell/README.md)
2. [Add logging to an existing Bash script with LogScale](../bash/README.md)
3. [Add logging to an existing Python script with LogScale](../python/README.md)
4. [Ingest an existing log file with LogScale Collector](../file-ingest/README.md)
5. [Build a Multi-Repository Syslog Server with LogScale Collector](https://mylogscale.com/howtos/build-a-multi-repository-syslog-server-with-logscale-collector)
6. Related: [Forward UniFi Syslog to a Remote Server](https://mylogscale.com/howtos/forward-unifi-syslog-to-a-remote-server)
