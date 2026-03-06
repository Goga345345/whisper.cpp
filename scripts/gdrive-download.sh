#!/bin/bash

# Simple helper script to download publicly shared files from Google Drive
# Usage: ./scripts/gdrive-download.sh <file_id> [output_file]
# Example: ./scripts/gdrive-download.sh 1A2B3C4D mymodel.bin

if [ -z "$1" ]; then
    echo "Usage: $0 <file_id> [output_file]"
    exit 1
fi

FILEID="$1"
FILENAME="${2:-$FILEID}"

# temporary cookie file
COOKIE=$(mktemp)

# first request obtains the confirm code for large files
CONFIRM=$(curl -sc "$COOKIE" "https://drive.google.com/uc?export=download&id=${FILEID}" | sed -n 's/.*confirm=\(.*\)&amp;.*/\1\n/p')

# second request downloads the file using the confirm code
curl -Lb "$COOKIE" "https://drive.google.com/uc?export=download&confirm=${CONFIRM}&id=${FILEID}" -o "$FILENAME"

rm -f "$COOKIE"
