#!/bin/bash

set -euo pipefail

# Download a publicly shared file from Google Drive.
# Usage: ./scripts/gdrive-download.sh <file_id> [output_file]
# Example: ./scripts/gdrive-download.sh 1A2B3C4D mymodel.bin

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <file_id> [output_file]" >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required" >&2
    exit 1
fi

file_id="$1"
output_file="${2:-$file_id}"

cookie_file="$(mktemp)"
response_file="$(mktemp)"
cleanup() {
    rm -f "$cookie_file" "$response_file"
}
trap cleanup EXIT

base_url="https://drive.google.com/uc?export=download&id=${file_id}"

# First request: fetch potential confirmation token + cookies.
curl --fail --location --silent --show-error \
    --cookie-jar "$cookie_file" \
    "$base_url" \
    -o "$response_file"

# Most small files download immediately (no confirm token needed).
if grep -q "Google Drive - Virus scan warning" "$response_file"; then
    confirm_token="$(sed -n 's/.*confirm=\([0-9A-Za-z_\-]*\).*/\1/p' "$response_file" | head -n 1)"

    if [ -z "$confirm_token" ]; then
        echo "Error: unable to extract Google Drive confirmation token" >&2
        exit 1
    fi

    curl --fail --location --silent --show-error \
        --cookie "$cookie_file" \
        "https://drive.google.com/uc?export=download&confirm=${confirm_token}&id=${file_id}" \
        -o "$output_file"
else
    mv "$response_file" "$output_file"
    response_file=""
fi

echo "Downloaded Google Drive file ${file_id} -> ${output_file}"
