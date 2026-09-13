# Ingest an existing log file with LogScale Collector

## Goal

Ship events from log files that already exist on disk into a LogScale Cloud repository. Use the Falcon LogScale Collector file source for line-based text logs and for JSON Lines. After setup, new lines appended to those files appear in the repository with usable timestamps and fields.

This path is for files you already have. If a script should create structured events, use the PowerShell, Bash, or Python articles in this series instead.

## Prerequisites

- Falcon LogScale Collector installed on the host that can read the files.
- A LogScale Cloud repository and a collector ingest token.
- Read access for the collector account to the log directory and files.
- UTF-8 line-based files (one event per line). Multiline records are not covered here.

Install or enroll the collector first:

- Windows: [[howto:Install LogScale Collector on Windows]]
- Linux (collector on a log host): [[howto:Build a Multi-Repository Syslog Server with LogScale Collector]]

Get the samples and templates from [ITrunsDE/mylogscale-script-logging](https://github.com/ITrunsDE/mylogscale-script-logging) (`file-ingest/`):

```bash
git clone https://github.com/ITrunsDE/mylogscale-script-logging.git
cd mylogscale-script-logging/file-ingest
```

```powershell
git clone https://github.com/ITrunsDE/mylogscale-script-logging.git
cd mylogscale-script-logging\file-ingest
```

Files in that folder:

- [Sample text log](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/file-ingest/samples/app-sample.log)
- [Sample JSON Lines file](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/file-ingest/samples/events-sample.jsonl)
- [Text parser](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/file-ingest/parser.text.logscale)
- [JSON Lines parser](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/file-ingest/parser.jsonl.logscale)
- [Windows collector example](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/file-ingest/collector.windows.example.yaml)
- [Linux collector example](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/file-ingest/collector.linux.example.yaml)

## 1. Choose the file shape

| File shape | Example | Parser name in this article |
|---|---|---|
| Line-based text | `2026-09-13T12:00:01.000Z INFO message` | `existing-text` |
| JSON Lines | one JSON object per line with a `timestamp` field | `existing-jsonl` |

JSON Lines from the script articles in this series already match `existing-jsonl` if each line has `timestamp`. You can reuse those files with this collector path.

Do not point both a script’s direct HTTPS sender and a collector at the same events into the same repository unless you accept duplicates.

## 2. Place the sample files (or your real ones)

Copy the samples to a dedicated directory the collector can read:

```powershell
New-Item -ItemType Directory -Force -Path C:\Logs\Demo | Out-Null
Copy-Item .\samples\app-sample.log C:\Logs\Demo\
Copy-Item .\samples\events-sample.jsonl C:\Logs\Demo\
```

```bash
sudo mkdir -p /var/log/demo
sudo cp ./samples/app-sample.log ./samples/events-sample.jsonl /var/log/demo/
sudo chown -R logscale-collector:logscale-collector /var/log/demo   # adjust user to your collector account
```

For production, point the `include` paths at your real files instead of the samples. Keep a narrow glob so unrelated files are not ingested.

## 3. Create the parsers

In the destination repository, create two parsers:

1. Name: `existing-text` — paste [parser.text.logscale](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/file-ingest/parser.text.logscale). It pulls `timestamp`, `level`, and `message` from each line, then sets event time from `timestamp`.
2. Name: `existing-jsonl` — paste [parser.jsonl.logscale](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/file-ingest/parser.jsonl.logscale). It runs `parseJson()` and `parseTimestamp(field=timestamp)`.

LogScale accepts this ISO 8601 timestamp format directly. [Timestamp parser reference](https://library.humio.com/crowdstrike-query-language/functions-parsetimestamp.html)

If your real text lines use a different layout, adjust the `regex(...)` in `existing-text` before you rely on production data. Keep one event per line.

## 4. Configure the collector

Copy the platform example to `collector.local.yaml` and merge the named `sources` and `sinks` into your existing collector configuration. Do not wipe unrelated sources.

Windows: start from [collector.windows.example.yaml](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/file-ingest/collector.windows.example.yaml).  
Linux: start from [collector.linux.example.yaml](https://github.com/ITrunsDE/mylogscale-script-logging/blob/main/file-ingest/collector.linux.example.yaml).

Replace:

- sink `url` and collector ingest `token`
- `include` paths so they match the files from step 2

Keep `encoding: UTF-8`. Attach `existing-text` / `existing-jsonl` on the token, or leave the token parser unset and keep the `parser` fields on the sources. A parser on the token wins over the source setting. [Collector file source](https://library.humio.com/falcon-logscale-collector/log-collector-config-common-source-file.html), [Collector source settings](https://library.humio.com/falcon-logscale-collector/log-collector-config-common-sources.html)

Leave the sample 256 MB disk queue and `fullAction: pause` unless you have sized the queue for your rate and disk. [Disk queue settings](https://library.humio.com/falcon-logscale-collector/log-collector-config-common-sink-queue-disk.html)

Validate and apply the configuration with your local or Fleet Management workflow. Confirm both file sources are active.

## 5. Force a fresh read for the samples

Collectors often track file offsets. For a first test with the static samples, append a new line after the source is active so the collector has something new to ship:

```powershell
Add-Content -Path C:\Logs\Demo\app-sample.log -Value "2026-09-13T12:00:06.000Z INFO verification line from windows"
Add-Content -Path C:\Logs\Demo\events-sample.jsonl -Value '{"timestamp":"2026-09-13T12:00:06.000Z","level":"INFO","message":"verification line from windows","service":"demo"}'
```

```bash
echo '2026-09-13T12:00:06.000Z INFO verification line from linux' >> /var/log/demo/app-sample.log
echo '{"timestamp":"2026-09-13T12:00:06.000Z","level":"INFO","message":"verification line from linux","service":"demo"}' >> /var/log/demo/events-sample.jsonl
```

Expect the collector to pick up the new lines within your normal shipping interval.

## Verify it works

In the repository, search a short time window:

- Text: `level=INFO message="verification line"` (or the Linux/Windows wording you appended)
- JSON Lines: `service=demo message="verification line"`

Confirm `@timestamp` matches the line’s `timestamp`, and that text events expose `level` and `message`. The sample files contain five baseline lines each; after the append you should see the verification line as well.

For a permission check, temporarily remove read access for the collector account, append another line, and expect no new Cloud event until access is restored.

## Troubleshooting

**No events after append:** Check the active `include` path, filename glob, collector read permissions, and that the source is enabled. Static files already fully read need a new line (step 5) or a new file matching the glob.

**Events arrive with the wrong time:** Check `parseTimestamp(field=timestamp)` and the line/JSON timestamp format. Text lines must match the `existing-text` regex or you must adapt the parser.

**JSON fields missing:** Confirm the file is JSON Lines (one object per line), UTF-8, and that `existing-jsonl` is the effective parser (token parser overrides source parser).

**Duplicates:** The same path may already be covered by another file source, or a script may also send the same events with direct HTTPS.

**Only part of a line appears / broken fields:** You may have multiline records. This article does not cover multiline; split to one event per line or use a dedicated multiline guide later.

## Related articles in this series

- [Add logging to an existing PowerShell script with LogScale](../powershell/README.md)
- [Add logging to an existing Bash script with LogScale](../bash/README.md)
- [Add logging to an existing Python script with LogScale](../python/README.md)
