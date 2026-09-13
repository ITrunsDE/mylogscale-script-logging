# mylogscale-script-logging

Copy-paste helpers to add structured LogScale logging to existing **PowerShell**, **Bash**, and **Python** scripts.

Companion code for the mylogscale.com ingest how-tos (direct HTTPS to LogScale Cloud and local JSON Lines + Falcon LogScale Collector).

## Layout

| Directory | Functions | Example |
|-----------|-----------|---------|
| `powershell/` | `Initialize-LogScale`, `Write-LogScale` in `Logging.ps1` | `Example.ps1` |
| `bash/` | `initialize_logscale`, `write_logscale` in `logging.sh` | `example.sh` |
| `python/` | `initialize_logscale`, `write_logscale` in `logscale.py` | `example.py` |
| `file-ingest/` | Sample text/JSONL logs, parsers, Windows/Linux collector YAML | — |

Each folder also has:

- `logscale.direct.example.json` — direct HTTPS on, local off
- `logscale.collector.example.json` — local JSON Lines on, direct off
- `collector.example.yaml` — sample file source for the collector
- `parser.logscale` — `parseJson()` + `parseTimestamp(field=timestamp)`
- `.gitignore` — excludes real `logscale.json`, `logs/`, `collector.local.yaml`

## Quick start

1. Copy the folder for your language next to your script (or copy the functions into the script).
2. `cp logscale.direct.example.json logscale.json` and set your Cloud origin + ingest token.
3. Run the example:

```powershell
# PowerShell (Windows)
powershell.exe -NoProfile -File .\Example.ps1 -ConfigPath .\logscale.json
pwsh.exe -NoProfile -File .\Example.ps1 -ConfigPath .\logscale.json
```

```bash
# Bash (Linux): needs curl + jq
chmod +x ./example.sh
./example.sh ./logscale.json
```

```bash
# Python 3.8+ (stdlib only)
python3 example.py ./logscale.json
```

Expect `Main script result: 42` and five events sharing one `run_id`.

Collector path:

```text
# use logscale.collector.example.json, then point the collector at logs/<script>-*.jsonl
```

Never commit a real `logscale.json`. Tokens stay out of Git.

## Shared event fields

`timestamp`, `level` (`INFO`|`WARN`|`ERROR`), `message`, `script_name`, `run_id`, plus optional flat custom fields. Reserved fields cannot be overwritten. Logging failures print a warning; the main script continues.

## Docs

How-tos ship next to each package (open the folder on GitHub to read them):

| Path | Guide |
|------|--------|
| [powershell/README.md](powershell/README.md) | Add logging to an existing PowerShell script |
| [bash/README.md](bash/README.md) | Add logging to an existing Bash script |
| [python/README.md](python/README.md) | Add logging to an existing Python script |
| [file-ingest/README.md](file-ingest/README.md) | Ingest an existing log file |
| [docs/overview.md](docs/overview.md) | Choose a path (series overview) |

Published mylogscale.com URLs can replace these once the articles go live.
