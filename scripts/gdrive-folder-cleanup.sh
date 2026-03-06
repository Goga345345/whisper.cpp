#!/bin/bash

set -euo pipefail

# Find and optionally trash Google Drive folders by name and/or emptiness.
#
# Required auth:
#   export GDRIVE_ACCESS_TOKEN="ya29..."
#
# Usage examples:
#   ./scripts/gdrive-folder-cleanup.sh --name familyhub --empty-only
#   ./scripts/gdrive-folder-cleanup.sh --name familyhub --empty-only --delete
#   ./scripts/gdrive-folder-cleanup.sh --all-empty --delete

usage() {
    cat <<'USAGE'
Usage: gdrive-folder-cleanup.sh [options]

Options:
  --name <text>      Match folders whose names contain <text> (case-sensitive).
  --empty-only       Keep only empty folders in the candidate list.
  --all-empty        Shortcut for: no --name filter + --empty-only.
  --delete           Trash matching folders (default is dry-run).
  --help             Show this help.

Environment:
  GDRIVE_ACCESS_TOKEN   OAuth2 token for Google Drive API.

Notes:
  - Uses Drive v3 REST API with includeItemsFromAllDrives enabled.
  - "Delete" here means move to trash (trashed=true).
USAGE
}

name_filter=""
empty_only=0
do_delete=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name)
            if [ "$#" -lt 2 ]; then
                echo "Error: --name requires a value" >&2
                exit 1
            fi
            name_filter="$2"
            shift 2
            ;;
        --empty-only)
            empty_only=1
            shift
            ;;
        --all-empty)
            empty_only=1
            name_filter=""
            shift
            ;;
        --delete)
            do_delete=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option '$1'" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "${GDRIVE_ACCESS_TOKEN:-}" ]; then
    echo "Error: GDRIVE_ACCESS_TOKEN is not set" >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required" >&2
    exit 1
fi

api_base="https://www.googleapis.com/drive/v3"

urlencode() {
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

api_get() {
    local url="$1"
    curl --fail --silent --show-error \
        -H "Authorization: Bearer ${GDRIVE_ACCESS_TOKEN}" \
        "$url"
}

build_query() {
    local query="mimeType='application/vnd.google-apps.folder' and trashed=false"

    if [ -n "$name_filter" ]; then
        local escaped_name
        escaped_name=$(printf "%s" "$name_filter" | sed "s/'/\\\\'/g")
        query+=" and name contains '${escaped_name}'"
    fi

    printf "%s" "$query"
}

list_folders() {
    local query encoded_query page_token=""
    query="$(build_query)"
    encoded_query="$(urlencode "$query")"

    while :; do
        local url="${api_base}/files?pageSize=1000&fields=nextPageToken,files(id,name)&includeItemsFromAllDrives=true&supportsAllDrives=true&q=${encoded_query}"
        if [ -n "$page_token" ]; then
            url+="&pageToken=$(urlencode "$page_token")"
        fi

        local payload
        payload="$(api_get "$url")"

        printf "%s" "$payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); [print("{}\t{}".format(f.get("id", ""), f.get("name", ""))) for f in d.get("files", [])]'

        page_token="$(printf "%s" "$payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("nextPageToken", ""))')"
        [ -z "$page_token" ] && break
    done
}

folder_has_children() {
    local folder_id="$1"
    local query encoded_query url
    query="'${folder_id}' in parents and trashed=false"
    encoded_query="$(urlencode "$query")"
    url="${api_base}/files?pageSize=1&fields=files(id)&includeItemsFromAllDrives=true&supportsAllDrives=true&q=${encoded_query}"

    local count
    count="$(api_get "$url" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("files", [])))')"

    [ "$count" -gt 0 ]
}

trash_folder() {
    local folder_id="$1"
    curl --fail --silent --show-error \
        -X PATCH \
        -H "Authorization: Bearer ${GDRIVE_ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"trashed": true}' \
        "${api_base}/files/${folder_id}?supportsAllDrives=true" >/dev/null
}

matches="$(list_folders || true)"

if [ -z "$matches" ]; then
    echo "No folders matched the filter."
    exit 0
fi

result_count=0
while IFS=$'\t' read -r folder_id folder_name; do
    [ -z "$folder_id" ] && continue

    if [ "$empty_only" -eq 1 ] && folder_has_children "$folder_id"; then
        continue
    fi

    result_count=$((result_count + 1))

    if [ "$do_delete" -eq 1 ]; then
        trash_folder "$folder_id"
        echo "Trashed folder: ${folder_name} (${folder_id})"
    else
        echo "Candidate folder: ${folder_name} (${folder_id})"
    fi
done <<< "$matches"

if [ "$result_count" -eq 0 ]; then
    echo "No folders matched after applying --empty-only."
    exit 0
fi

if [ "$do_delete" -eq 1 ]; then
    echo "Done. Trashed ${result_count} folder(s)."
else
    echo "Dry run complete. ${result_count} folder(s) would be trashed with --delete."
fi
