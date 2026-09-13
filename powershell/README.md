# Add logging to an existing PowerShell script with LogScale

## Goal

Add explicit `INFO`, `WARN`, and `ERROR` events to an existing PowerShell script. Send each event directly to LogScale Cloud, write it to a daily local file for collector delivery, or enable both outputs. Logging failures produce a warning while the main script continues.

The implementation consists of two functions and a JSON configuration file. Each execution gets one `run_id`. Events include `timestamp`, `level`, `message`, and `script_name`, plus optional custom fields.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7 on Windows as the intended target. No additional PowerShell modules are required.
- A LogScale Cloud repository and permission to create an ingest token for direct delivery.
- Outbound HTTPS access to your Cloud ingest host, with a trusted certificate and a working TLS configuration.
- For local logging: a dedicated log directory writable by the script account. For collector delivery, the collector account also needs read access.
- The companion files from [ITrunsDE/mylogscale-script-logging](https://github.com/ITrunsDE/mylogscale-script-logging), used from the `powershell/` folder (for example under `C:\Scripts\LogScaleDemo` after clone or copy).

Clone or download the package, then work inside `powershell/`:

```powershell
git clone https://github.com/ITrunsDE/mylogscale-script-logging.git
cd mylogscale-script-logging\powershell
```

Files in that folder:

- [Logging functions](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/powershell/Logging.ps1)
- [Complete example script](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/powershell/Example.ps1)
- [Direct-delivery configuration](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/powershell/logscale.direct.example.json)
- [Collector-delivery configuration](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/powershell/logscale.collector.example.json)
- [Collector file source example](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/powershell/collector.example.yaml)
- [JSON Lines parser](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/powershell/parser.logscale)

For collector installation, use [[howto:Install LogScale Collector on Windows]].

## 1. Choose the outputs

The two JSON switches are independent:

| Direct logging | Local logging | Result |
|---|---|---|
| `true` | `false` | Send one HTTPS request per event. This is the main example. |
| `false` | `true` | Write JSON Lines locally. A collector handles delivery. |
| `true` | `true` | Write locally and attempt direct delivery for the same event. |
| `false` | `false` | Disable logging, including file creation and startup cleanup. |

If direct delivery and collector delivery ingest the same local events into the same repository, expect duplicates. A local file is not an automatic retry queue for the direct sender.

## 2. Create logscale.json

For direct delivery, copy the direct template to `logscale.json`:

```powershell
Copy-Item .\logscale.direct.example.json .\logscale.json
```

Edit the resulting file:

```json
{
  "url": "https://YOUR-LOGSCALE-HOST.example",
  "ingest_token": "REPLACE_WITH_REPOSITORY_INGEST_TOKEN",
  "direct_logging_enabled": true,
  "local_logging_enabled": false,
  "timeout_seconds": 5,
  "log_directory": "logs",
  "retention_days": 14
}
```

Use your Cloud ingest origin, including `https://`. Do not include a repository path or API suffix. The function adds `/api/v1/ingest/humio-structured`, authenticates with the ingest token, and supplies structured attributes and an event timestamp. Use a token without an additional parser for this direct example. [Structured ingest API](https://library.humio.com/logscale-api/api-ingest-structured-data.html)

`logscale.json` contains the token in plain text. Restrict access to the account running the script and required administrators. Keep the real file out of Git, tickets, screenshots, and shared downloads. The accompanying `.gitignore` excludes it; copy that rule when integrating elsewhere. Distribute only templates with placeholders. Do not print the logger object: it holds the token in memory.

PowerShell loads the file with `Get-Content` and `ConvertFrom-Json`. Use actual JSON booleans and integers, not quoted strings. Do not add comments or trailing commas if the same file must work with Windows PowerShell 5.1. [JSON support in Windows PowerShell 5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-5.1)

The sample timeout is five seconds, configurable from 1 to 60. Direct calls are synchronous and do not retry. This is not a hard five-second wall-clock guarantee: DNS resolution can exceed a short timeout, especially in Windows PowerShell 5.1. PowerShell 7.4 and later also receive an operation timeout. Prefer file delivery when script execution must avoid waiting on a network request. [Windows PowerShell timeout behavior](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod?view=powershell-5.1), [PowerShell 7 timeout parameters](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod?view=powershell-7.6)

## 3. Add the functions to an existing script

Copy both functions from [Logging.ps1](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/powershell/Logging.ps1) into your script, after its `param` block and before its main work. Alternatively, keep the file alongside the script and load it:

```powershell
. (Join-Path $PSScriptRoot 'Logging.ps1')
```

Initialize once, before your main work:

```powershell
$logger = Initialize-LogScale `
    -ConfigPath (Join-Path $PSScriptRoot 'logscale.json') `
    -ScriptName ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath))
```

Add explicit calls where useful:

```powershell
Write-LogScale $logger INFO 'Backup started' @{ job = 'daily-backup' }
# Existing backup work stays here, with its existing error handling.
Write-LogScale $logger INFO 'Backup completed' @{ duration_ms = 1200 }
```

The duration above is an illustrative value. Supply a measured value in your real script. Logging an `ERROR` records an event; it does not throw an exception or decide whether your business operation should continue.

Use a unique script name within the log directory: up to 100 ASCII letters, digits, dots, underscores or hyphens, starting with a letter or digit. For a script with spaces in its filename, pass an explicit name such as `daily-backup`. Scripts with the same name and directory share files and the cleanup namespace.

Extra fields accept strings, booleans, null, and supported finite numeric values. Use flat names such as `computer`, `job`, and `duration_ms`. Nested objects and arrays are outside this first version. Attempting to replace a reserved field, including a different capitalization such as `LEVEL`, rejects the event with a warning.

An unreadable or malformed configuration warns once and disables logging. Invalid settings for one output disable that output while allowing the other to initialize. Event and delivery errors warn without adding objects to the success pipeline, even when the caller has set `$WarningPreference = 'Stop'`. The functions do not change that preference globally.

## 4. Run the complete direct example

After configuring your Cloud destination, run:

```powershell
.\Example.ps1 -ConfigPath .\logscale.json
```

The example calculates `6 * 7`, emits five demonstration events and prints `Main script result: 42`. All five events share one `run_id`. Each is sent in its own request. An unavailable endpoint produces warnings, but the calculation still completes. A failed request is not retried; no delivery confirmation is implied by the main script's success.

Do not use this synchronous example for high-volume event streams. It intentionally has no batching or background sender.

## 5. Enable local logging and retention

For file delivery, either copy the collector template to `logscale.json` or pass the template path directly:

```powershell
Copy-Item .\logscale.collector.example.json .\logscale.json
.\Example.ps1 -ConfigPath .\logscale.json
```

```powershell
.\Example.ps1 -ConfigPath .\logscale.collector.example.json
```

Both disable direct delivery and enable local logging. No ingest token is required in the script configuration; the collector keeps its own destination settings.

Relative log paths are resolved against the configuration file's directory. The example writes `logs\Example-YYYY-MM-DD.jsonl`, using the UTC date. Each physical line contains one JSON event, encoded as UTF-8 without a byte-order mark. Embedded message newlines are escaped. Runs that cross UTC midnight switch to the next day's file.

At initialization, `retention_days: 14` keeps the current UTC date and the preceding 13 dates. For example, on September 13, files dated August 31 or later remain; files dated August 30 or earlier are eligible for deletion.

Cleanup examines only regular files matching this script's exact `script_name-YYYY-MM-DD.jsonl` pattern in the configured directory. It validates the date, skips symbolic links, and does not recurse. Other file names remain untouched. A deletion error warns and processing continues. If local logging is disabled, existing files remain untouched.

Use a dedicated directory with controlled permissions and one writer per script name. This small example does not coordinate overlapping processes, enforce a size limit, or run cleanup in the background. A script that stops running also stops cleaning up. The retention limit is based on the filename date, not the last-write time.

**Cleanup does not check whether the collector has delivered a file.** Set retention long enough for expected outages. Local retention does not change the repository's retention policy.

## 6. Configure collector delivery

Work through these steps in order. Install the collector first if it is not already running: [[howto:Install LogScale Collector on Windows]].

1. In the destination repository, create a parser named `powershell-jsonl` from [parser.logscale](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/powershell/parser.logscale). It runs `parseJson()` and `parseTimestamp(field=timestamp)`. LogScale accepts this ISO 8601 timestamp format directly. [Timestamp parser reference](https://library.humio.com/crowdstrike-query-language/functions-parsetimestamp.html)

2. Copy [collector.example.yaml](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/powershell/collector.example.yaml) to `collector.local.yaml`. Replace the sink URL, collector ingest token, and file path. Keep the real YAML private. Merge the named `sources` and `sinks` entries into your existing collector configuration; do not wipe unrelated sources.

3. Point the file source at your log directory and keep the `Example-*.jsonl` include pattern for this demo. Change the prefix when your script name differs. Set `encoding: UTF-8`. The collector account needs read access to the directory and files. [Collector file source](https://library.humio.com/falcon-logscale-collector/log-collector-config-common-source-file.html)

4. Attach `powershell-jsonl` to the collector ingest token, or leave the token's parser unset and keep `parser: powershell-jsonl` on the source. A parser on the token wins over the source setting. Keep the direct-delivery token separate so it does not inherit this file parser. [Collector source settings](https://library.humio.com/falcon-logscale-collector/log-collector-config-common-sources.html)

5. Leave the sample 256 MB disk queue and `fullAction: pause` unless you have sized the queue for your rate and disk. A full queue does not stop the script's independent file retention. [Disk queue settings](https://library.humio.com/falcon-logscale-collector/log-collector-config-common-sink-queue-disk.html)

6. Validate and apply the collector configuration with your local or Fleet Management workflow. Confirm the file source is active before writing new events.

7. From the demo directory, write a fresh local file with either shell:

```powershell
powershell.exe -NoProfile -File .\Example.ps1 -ConfigPath .\logscale.collector.example.json
pwsh.exe -NoProfile -File .\Example.ps1 -ConfigPath .\logscale.collector.example.json
```

Expect `Main script result: 42` and a new `logs\Example-YYYY-MM-DD.jsonl` (UTC date). Wait for the collector to pick up the file, then continue with verification below.

## Verify it works

### Direct HTTPS

Prepare `logscale.json` from the direct template (section 2). Then run:

```powershell
powershell.exe -NoProfile -File .\Example.ps1 -ConfigPath .\logscale.json
pwsh.exe -NoProfile -File .\Example.ps1 -ConfigPath .\logscale.json
```

Expect `Main script result: 42` and five HTTPS events. Search the repository for `script_name=Example` in the current time window. Pick that run's `run_id`; expect five events with `timestamp`, `level`, `message`, `script_name`, and `run_id`. Confirm `@timestamp` matches the event's UTC `timestamp` and that the calculation event has `result=42`.

### Collector path

After section 6, search the same way for the new `run_id` from the collector run. Expect the same five fields and `result=42`. If the file exists but Cloud stays empty, use Troubleshooting below.

### Failure and retention checks (optional)

Optional reader checks, not part of the Windows publish matrix. Use a disposable invalid-token config for a failure check: expect warnings and still `Main script result: 42`, then restore the valid token. For cleanup experiments, use a disposable directory and synthetic dated filenames; never backdate production files just to test deletion.

### What this validation covers

On 2026-09-13 I confirmed PowerShell 5 and PowerShell 7.1 on Windows Server 2025 for both direct HTTPS and collector-to-Cloud (Falcon LogScale Collector 1.11.7). Screenshots show five events per run, distinct run IDs across runs, `result=42`, and console `Main script result: 42`. A Cloud display time two hours ahead of the UTC `timestamp` matched the local timezone offset. The same day I confirmed local retention cleanup: with logging enabled and 14-day retention, files dated 2026-01-01 and 2026-08-30 were removed while 2026-08-31 and newer matching files remained; `Exampletest-…` and `readme` stayed. With local logging disabled, existing files were left alone. Failure paths stay documented under Verify/Troubleshooting as optional checks; they were not re-run as a Windows matrix. `Example.ps1` is a functional demo, not an automated retention or failure suite.

## Troubleshooting

**Initialization warning, no events:** Check JSON syntax, boolean types, and the script name. Resolve the configuration path explicitly for scheduled tasks. Warnings intentionally omit file contents and token values.

**HTTP delivery warning:** Check the Cloud origin, repository ingest token, connectivity, certificate trust and TLS configuration. Redirects are rejected. Do not disable certificate validation to bypass the error. The warning omits raw server responses to avoid exposing secrets.

**Local write or cleanup warning:** Check the execution account's directory permissions, free space, read-only files and overlapping script instances. A failed file write does not prevent an enabled direct-delivery attempt.

**Files exist but Cloud events are missing or have the wrong timestamp:** Check the collector's active source path, read permissions, queue state, destination token and effective parser. Test a newly written event. If events appear twice, check whether direct delivery and the collector are both sending them.
