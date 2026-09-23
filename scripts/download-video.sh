#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/download-video.sh URL OUTPUT" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

url="$1"
out="$2"

if [[ ! "$url" =~ ^https:// ]]; then
  echo "Only https:// URLs are accepted." >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"
rm -f "$out"

case "$url" in
  *photos.app.goo.gl/*|*photos.google.com/*)
    echo "Resolving Google Photos share link..."
    video_url="$(node tools/google-photos-video-url.mjs "$url")"
    if [[ -z "$video_url" ]]; then
      echo "Google Photos resolver returned an empty video URL." >&2
      exit 1
    fi
    echo "Downloading video from Google Photos..."
    curl       --fail       --location       --retry 3       --retry-delay 2       --connect-timeout 30       --user-agent "Mozilla/5.0"       "$video_url"       --output "$out"
    ;;
  *drive.google.com/*)
    echo "Downloading from Google Drive..."
    python3 -m pip install --quiet gdown
    python3 -m gdown --fuzzy "$url" -O "$out"
    ;;
  *dropbox.com/*)
    echo "Downloading from Dropbox..."
    if [[ "$url" == *"dl=0"* ]]; then
      url="${url/dl=0/dl=1}"
    elif [[ "$url" != *"dl=1"* ]]; then
      if [[ "$url" == *"?"* ]]; then
        url="$url&dl=1"
      else
        url="$url?dl=1"
      fi
    fi
    curl --fail --location --retry 3 --retry-delay 2 --connect-timeout 30 "$url" --output "$out"
    ;;
  *)
    echo "Downloading source video..."
    curl --fail --location --retry 3 --retry-delay 2 --connect-timeout 30 "$url" --output "$out"
    ;;
esac

if [[ ! -s "$out" ]]; then
  echo "Downloaded file is empty." >&2
  exit 1
fi

size_bytes="$(stat -f%z "$out" 2>/dev/null || stat -c%s "$out")"
max_bytes=$((750 * 1024 * 1024))
if (( size_bytes > max_bytes )); then
  echo "Input is larger than 750 MB." >&2
  exit 1
fi

if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$out" | grep -qx "video"; then
  echo "The downloaded file does not contain a readable video stream." >&2
  exit 1
fi

echo "Downloaded $size_bytes bytes."
