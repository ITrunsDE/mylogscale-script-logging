# Copy these functions into your script, or source this file.
# Requires: bash, curl, jq. Target: Linux.

_LS_SCRIPT_NAME=
_LS_RUN_ID=
_LS_DIRECT=0
_LS_LOCAL=0
_LS_ENDPOINT=
_LS_TOKEN=
_LS_TIMEOUT=5
_LS_LOG_DIR=

_ls_warn() {
  echo "WARNING: $*" >&2
}

_ls_utc_now() {
  # GNU date on Linux prints milliseconds with %3N. Reject non-matching output
  # (macOS date prints a broken ".3NZ") and fall back to whole seconds.
  local out
  out=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || true)
  if [[ "$out" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$ ]]; then
    printf '%s\n' "$out"
  else
    date -u +%Y-%m-%dT%H:%M:%S.000Z
  fi
}

_ls_utc_today() {
  date -u +%Y-%m-%d
}

_ls_oldest_keep_day() {
  # Keep today and the previous retention_days-1 UTC dates.
  local retention=$1
  local seconds=$(( (retention - 1) * 86400 ))
  local epoch
  epoch=$(date -u +%s)
  if date -u -d "@$((epoch - seconds))" +%Y-%m-%d 2>/dev/null; then
    return 0
  fi
  date -u -r "$((epoch - seconds))" +%Y-%m-%d
}

_ls_run_id() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    tr '[:upper:]' '[:lower:]' </proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    # ponytail: rare hosts without uuid; still unique enough for demo runs
    printf '%s-%s\n' "$(date -u +%Y%m%d%H%M%S)" "$$"
  fi
}

initialize_logscale() {
  local config_path=$1 script_name=$2
  local config_dir config_json directory retention timeout url token

  _LS_SCRIPT_NAME=
  _LS_RUN_ID=
  _LS_DIRECT=0
  _LS_LOCAL=0
  _LS_ENDPOINT=
  _LS_TOKEN=
  _LS_TIMEOUT=5
  _LS_LOG_DIR=

  if [[ ! "$script_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$ ]]; then
    _ls_warn 'LogScale initialization failed. Check the JSON file and script name; logging is disabled.'
    return 0
  fi
  if [[ ! -f "$config_path" ]]; then
    _ls_warn 'LogScale initialization failed. Check the JSON file and script name; logging is disabled.'
    return 0
  fi
  config_dir=$(cd "$(dirname -- "$config_path")" && pwd) || {
    _ls_warn 'LogScale initialization failed. Check the JSON file and script name; logging is disabled.'
    return 0
  }
  config_json=$(jq -c . -- "$config_path" 2>/dev/null) || {
    _ls_warn 'LogScale initialization failed. Check the JSON file and script name; logging is disabled.'
    return 0
  }
  if ! jq -e '(.direct_logging_enabled|type)=="boolean" and (.local_logging_enabled|type)=="boolean"' >/dev/null 2>&1 <<<"$config_json"; then
    _ls_warn 'LogScale initialization failed. Check the JSON file and script name; logging is disabled.'
    return 0
  fi

  _LS_SCRIPT_NAME=$script_name
  _LS_RUN_ID=$(_ls_run_id)

  if jq -e '.direct_logging_enabled==true' >/dev/null 2>&1 <<<"$config_json"; then
    if url=$(jq -er '.url|strings' <<<"$config_json" 2>/dev/null) &&
      token=$(jq -er '.ingest_token|strings|select(test("^\\S+$"))' <<<"$config_json" 2>/dev/null) &&
      timeout=$(jq -er '.timeout_seconds|numbers|floor|select(.>=1 and .<=60)' <<<"$config_json" 2>/dev/null); then
      url=${url%/}
      if [[ "$url" =~ ^https://[A-Za-z0-9._-]+(:[0-9]+)?$ ]]; then
        _LS_ENDPOINT="${url}/api/v1/ingest/humio-structured"
        _LS_TOKEN=$token
        _LS_TIMEOUT=$timeout
        _LS_DIRECT=1
      else
        _ls_warn 'LogScale direct logging disabled. Check the HTTPS origin, ingest token and timeout_seconds (1-60).'
      fi
    else
      _ls_warn 'LogScale direct logging disabled. Check the HTTPS origin, ingest token and timeout_seconds (1-60).'
    fi
  fi

  if jq -e '.local_logging_enabled==true' >/dev/null 2>&1 <<<"$config_json"; then
    if directory=$(jq -er '.log_directory|strings|select(length>0)' <<<"$config_json" 2>/dev/null) &&
      retention=$(jq -er '.retention_days|numbers|floor|select(.>=1 and .<=36500)' <<<"$config_json" 2>/dev/null); then
      if [[ "$directory" != /* ]]; then
        directory="${config_dir}/${directory}"
      fi
      if mkdir -p -- "$directory" 2>/dev/null && [[ -d "$directory" && ! -L "$directory" ]]; then
        _LS_LOG_DIR=$(cd -- "$directory" && pwd) || directory=
        if [[ -n "$_LS_LOG_DIR" ]]; then
          _LS_LOCAL=1
        else
          _ls_warn 'LogScale local logging disabled. Check log_directory permissions and retention_days (1-36500).'
        fi
      else
        _ls_warn 'LogScale local logging disabled. Check log_directory permissions and retention_days (1-36500).'
      fi
    else
      _ls_warn 'LogScale local logging disabled. Check log_directory permissions and retention_days (1-36500).'
    fi

    if [[ $_LS_LOCAL -eq 1 ]]; then
      local oldest base datepart f
      if oldest=$(_ls_oldest_keep_day "$retention"); then
        for f in "$_LS_LOG_DIR"/*; do
          [[ -e "$f" ]] || continue
          [[ -f "$f" && ! -L "$f" ]] || continue
          base=$(basename -- "$f")
          case "$base" in
            "${_LS_SCRIPT_NAME}"-????-??-??.jsonl) ;;
            *) continue ;;
          esac
          datepart=${base#"${_LS_SCRIPT_NAME}-"}
          datepart=${datepart%.jsonl}
          [[ "$datepart" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
          if [[ "$datepart" < "$oldest" ]]; then
            rm -f -- "$f" 2>/dev/null || _ls_warn 'LogScale could not delete an expired log file; continuing.'
          fi
        done
      else
        _ls_warn 'LogScale startup cleanup failed; logging will continue.'
      fi
    fi
  fi
}

# write_logscale LEVEL "message" ['{"extra":"fields"}']
write_logscale() {
  local level=$1 message=$2 extra
  local ts today json body file http_code

  if [[ $# -ge 3 ]]; then
    extra=$3
  else
    extra='{}'
  fi

  if [[ $_LS_DIRECT -eq 0 && $_LS_LOCAL -eq 0 ]]; then
    return 0
  fi
  if [[ "$level" != INFO && "$level" != WARN && "$level" != ERROR ]]; then
    _ls_warn 'LogScale event rejected. Check level, message and scalar extra fields; do not overwrite reserved fields.'
    return 0
  fi
  if [[ -z "${message//[[:space:]]/}" ]]; then
    _ls_warn 'LogScale event rejected. Check level, message and scalar extra fields; do not overwrite reserved fields.'
    return 0
  fi

  ts=$(_ls_utc_now)
  today=${ts:0:10}
  json=$(jq -nc \
    --arg ts "$ts" \
    --arg level "$level" \
    --arg message "$message" \
    --arg script_name "$_LS_SCRIPT_NAME" \
    --arg run_id "$_LS_RUN_ID" \
    --argjson extra "$extra" '
      if ($extra | type) != "object" then error("fields")
      else
        reduce ($extra | to_entries[]) as $e (
          {
            timestamp: $ts,
            level: $level,
            message: $message,
            script_name: $script_name,
            run_id: $run_id
          };
          ($e.key | ascii_downcase) as $k
          | if ($e.key | test("^[A-Za-z][A-Za-z0-9_]*$") | not) then error("key")
            elif (["timestamp","level","message","script_name","run_id"] | index($k)) != null then error("reserved")
            elif ($e.value | type) as $t
                 | ($t != "string" and $t != "boolean" and $t != "number" and $t != "null")
              then error("type")
            elif ($e.value | type) == "number" and (($e.value | isnan) or ($e.value | isinfinite))
              then error("number")
            else . + {($e.key): $e.value}
            end
        )
      end
    ' 2>/dev/null) || {
    _ls_warn 'LogScale event rejected. Check level, message and scalar extra fields; do not overwrite reserved fields.'
    return 0
  }

  if [[ $_LS_LOCAL -eq 1 ]]; then
    file="${_LS_LOG_DIR}/${_LS_SCRIPT_NAME}-${today}.jsonl"
    if [[ -e "$file" && ( -L "$file" || ! -f "$file" ) ]]; then
      _ls_warn 'LogScale local write failed. Check the log directory, permissions and free space; continuing.'
    else
      # ponytail: one writer per script/path; use per-run files if overlapping runs are needed.
      if ! printf '%s\n' "$json" >>"$file" 2>/dev/null; then
        _ls_warn 'LogScale local write failed. Check the log directory, permissions and free space; continuing.'
      fi
    fi
  fi

  if [[ $_LS_DIRECT -eq 1 ]]; then
    body=$(jq -nc --argjson event "$json" '[{events:[{timestamp:$event.timestamp, attributes:$event}]}]' 2>/dev/null) || {
      _ls_warn 'LogScale HTTP delivery failed. Check connectivity, TLS, the Cloud URL and ingest token; event not retried.'
      return 0
    }
    http_code=$(curl -sS -o /dev/null -w '%{http_code}' \
      --max-time "$_LS_TIMEOUT" \
      --connect-timeout "$_LS_TIMEOUT" \
      --max-redirs 0 \
      -H "Authorization: Bearer ${_LS_TOKEN}" \
      -H 'Content-Type: application/json; charset=utf-8' \
      -d "$body" \
      -- "$_LS_ENDPOINT" 2>/dev/null) || http_code=000
    if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
      _ls_warn 'LogScale HTTP delivery failed. Check connectivity, TLS, the Cloud URL and ingest token; event not retried.'
    fi
  fi
}
