# Add logging to an existing Python script with LogScale

## Goal

Add explicit `INFO`, `WARN`, and `ERROR` events to an existing Python script. Send each event directly to LogScale Cloud, write it to a daily local file for collector delivery, or enable both outputs. Logging failures produce a warning while the main script continues.

The implementation consists of two functions and a JSON configuration file. Each execution gets one `run_id`. Events include `timestamp`, `level`, `message`, and `script_name`, plus optional custom fields.

## Prerequisites

- Python 3.8 or later. No third-party packages.
- A LogScale Cloud repository and permission to create an ingest token for direct delivery.
- Outbound HTTPS access to your Cloud ingest host, with a trusted certificate and a working TLS configuration.
- For local logging: a dedicated log directory writable by the script account. For collector delivery, the collector account also needs read access.
- The companion files from [ITrunsDE/mylogscale-script-logging](https://github.com/ITrunsDE/mylogscale-script-logging), used from the `python/` folder (for example under `/opt/logscale-demo` or `C:\Scripts\LogScaleDemo` after clone or copy).

Clone or download the package, then work inside `python/`:

```bash
git clone https://github.com/ITrunsDE/mylogscale-script-logging.git
cd mylogscale-script-logging/python
```

Files in that folder:

- [Logging functions](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/python/logscale.py)
- [Complete example script](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/python/example.py)
- [Direct-delivery configuration](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/python/logscale.direct.example.json)
- [Collector-delivery configuration](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/python/logscale.collector.example.json)
- [Collector file source example](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/python/collector.example.yaml)
- [JSON Lines parser](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/python/parser.logscale)

Install the Falcon LogScale Collector on the host that reads the files. Linux walkthrough: [[howto:Build a Multi-Repository Syslog Server with LogScale Collector]]. Windows: [[howto:Install LogScale Collector on Windows]].

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

```bash
cp ./logscale.direct.example.json ./logscale.json
```

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

`json.load` requires real JSON booleans and integers, not quoted strings. Do not add comments or trailing commas.

The sample timeout is five seconds, configurable from 1 to 60. Direct calls use `urllib.request` with that timeout (including `http(s)_proxy` from the environment, like `curl`), are synchronous, and do not retry. Redirects are rejected. Prefer file delivery when script execution must avoid waiting on a network request.

## 3. Add the functions to an existing script

Copy both functions from [logscale.py](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/python/logscale.py) into your script, or keep the file alongside the script and import it:

```python
from pathlib import Path
from logscale import initialize_logscale, write_logscale

logger = initialize_logscale(str(Path(__file__).with_name("logscale.json")), Path(__file__).stem)
```

Add explicit calls where useful:

```python
write_logscale(logger, "INFO", "Backup started", {"job": "daily-backup"})
# Existing backup work stays here, with its existing error handling.
write_logscale(logger, "INFO", "Backup completed", {"duration_ms": 1200})
```

The duration above is illustrative. Supply a measured value in your real script. Logging an `ERROR` records an event; it does not raise or decide whether your business operation should continue.

Use a unique script name within the log directory: up to 100 ASCII letters, digits, dots, underscores or hyphens, starting with a letter or digit. Scripts with the same name and directory share files and the cleanup namespace.

Extra fields are an optional `dict`. Accept strings, booleans, `None`, and finite numbers. Use flat names such as `computer`, `job`, and `duration_ms`. Nested objects and arrays are outside this first version. Attempting to replace a reserved field, including a different capitalization such as `LEVEL`, rejects the event with a warning.

An unreadable or malformed configuration warns once and disables logging (`initialize_logscale` returns `None`). Invalid settings for one output disable that output while allowing the other to initialize. Event and delivery errors warn on stderr without stopping later main-script work.

## 4. Run the complete direct example

After configuring your Cloud destination, run:

```bash
python3 example.py ./logscale.json
```

```powershell
py -3 .\example.py .\logscale.json
```

The example calculates `6 * 7`, emits five demonstration events and prints `Main script result: 42`. All five events share one `run_id`. Each direct event is sent in its own request. An unavailable endpoint produces warnings, but the calculation still completes. A failed request is not retried; no delivery confirmation is implied by the main script's success.

Do not use this synchronous example for high-volume event streams. It intentionally has no batching or background sender.

## 5. Enable local logging and retention

For file delivery, either copy the collector template to `logscale.json` or pass the template path directly:

```bash
cp ./logscale.collector.example.json ./logscale.json
python3 example.py ./logscale.json
```

```bash
python3 example.py ./logscale.collector.example.json
```

Both disable direct delivery and enable local logging. No ingest token is required in the script configuration; the collector keeps its own destination settings.

Relative log paths are resolved against the configuration file's directory. The example writes `logs/example-YYYY-MM-DD.jsonl`, using the UTC date. Each physical line contains one JSON event, encoded as UTF-8 without a byte-order mark. Embedded message newlines are escaped by `json.dumps`. Runs that cross UTC midnight switch to the next day's file.

At initialization, `retention_days: 14` keeps the current UTC date and the preceding 13 dates. For example, on September 13, files dated August 31 or later remain; files dated August 30 or earlier are eligible for deletion.

Cleanup examines only regular files matching this script's exact `script_name-YYYY-MM-DD.jsonl` pattern in the configured directory. It validates the date, skips symbolic links, and does not recurse. Other file names remain untouched. A deletion error warns and processing continues. If local logging is disabled, existing files remain untouched.

Use a dedicated directory with controlled permissions and one writer per script name. This small example does not coordinate overlapping processes, enforce a size limit, or run cleanup in the background. A script that stops running also stops cleaning up. The retention limit is based on the filename date, not the last-write time.

**Cleanup does not check whether the collector has delivered a file.** Set retention long enough for expected outages. Local retention does not change the repository's retention policy.

## 6. Configure collector delivery

Work through these steps in order after the collector is installed on the host that reads the files.

1. In the destination repository, create a parser named `python-jsonl` from [parser.logscale](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/python/parser.logscale). It runs `parseJson()` and `parseTimestamp(field=timestamp)`. LogScale accepts this ISO 8601 timestamp format directly. [Timestamp parser reference](https://library.humio.com/crowdstrike-query-language/functions-parsetimestamp.html)

2. Copy [collector.example.yaml](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/python/collector.example.yaml) to `collector.local.yaml`. Replace the sink URL, collector ingest token, and file path. Keep the real YAML private. Merge the named `sources` and `sinks` entries into your existing collector configuration; do not wipe unrelated sources.

3. Point the file source at your log directory and keep the `example-*.jsonl` include pattern for this demo. Change the prefix when your script name differs. Set `encoding: UTF-8`. The collector account needs read access to the directory and files. [Collector file source](https://library.humio.com/falcon-logscale-collector/log-collector-config-common-source-file.html)

4. Attach `python-jsonl` to the collector ingest token, or leave the token's parser unset and keep `parser: python-jsonl` on the source. A parser on the token wins over the source setting. Keep the direct-delivery token separate so it does not inherit this file parser. [Collector source settings](https://library.humio.com/falcon-logscale-collector/log-collector-config-common-sources.html)

5. Leave the sample 256 MB disk queue and `fullAction: pause` unless you have sized the queue for your rate and disk. A full queue does not stop the script's independent file retention. [Disk queue settings](https://library.humio.com/falcon-logscale-collector/log-collector-config-common-sink-queue-disk.html)

6. Validate and apply the collector configuration with your local or Fleet Management workflow. Confirm the file source is active before writing new events.

7. From the demo directory, write a fresh local file:

```bash
python3 example.py ./logscale.collector.example.json
```

Expect `Main script result: 42` and a new `logs/example-YYYY-MM-DD.jsonl` (UTC date). Wait for the collector to pick up the file, then continue with verification below.

## Verify it works

### Direct HTTPS

Prepare `logscale.json` from the direct template (section 2). Then run:

```bash
python3 example.py ./logscale.json
```

Expect `Main script result: 42` and five HTTPS events. Search the repository for `script_name=example` in the current time window. Pick that run's `run_id`; expect five events with `timestamp`, `level`, `message`, `script_name`, and `run_id`. Confirm `@timestamp` matches the event's UTC `timestamp` and that the calculation event has `result=42`.

### Collector path

After section 6, search the same way for the new `run_id` from the collector run. Expect the same five fields and `result=42`. If the file exists but Cloud stays empty, use Troubleshooting below.

### Failure and retention checks (optional)

Optional reader checks. Use a disposable invalid-token config for a failure check: expect warnings and still `Main script result: 42`, then restore the valid token. For cleanup experiments, use a disposable directory and synthetic dated filenames; never backdate production files just to test deletion.

### What this validation covers

On 2026-09-13 I confirmed direct HTTPS and collector-to-Cloud for Python, using the same config pattern as PowerShell and Bash. Local file behavior, cleanup, and bad-token handling were smoke-tested. The helper loads a system CA bundle when the Python default CA file is missing (seen with python.org-style installs where `curl` still worked). Failure paths stay documented under Verify/Troubleshooting as optional checks.

## Troubleshooting

**Initialization warning, no events:** Check JSON syntax, boolean types, Python 3.8+, and the script name. Resolve the configuration path explicitly for scheduled tasks. Warnings intentionally omit file contents and token values.

**HTTP delivery warning:** Check the Cloud origin, repository ingest token, connectivity, certificate trust and TLS configuration. The warning includes an exception type and optional HTTP status (for example `HTTPError 401` or `URLError/SSLCertVerificationError`) without response bodies. Redirects are rejected. `urllib` uses `http_proxy` / `https_proxy` like `curl`. On some Python installs (especially python.org on macOS) the default CA file is missing while `curl` still works; this helper loads a system CA bundle when needed. Do not disable certificate validation to bypass the error.

**Local write or cleanup warning:** Check the execution account's directory permissions, free space, read-only files and overlapping script instances. A failed file write does not prevent an enabled direct-delivery attempt.

**Files exist but Cloud events are missing or have the wrong timestamp:** Check the collector's active source path, read permissions, queue state, destination token and effective parser. Test a newly written event. If events appear twice, check whether direct delivery and the collector are both sending them.

**`ModuleNotFoundError: logging` / wrong logging module:** Import `logscale`, not a file named `logging.py`. The stdlib already owns that name.
