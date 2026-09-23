#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/make-livp-template-matched.sh INPUT_VIDEO OUTPUT.livp TEMPLATE_IMAGE TEMPLATE.mov

Creates a .livp while matching the video dimensions, frame rate, duration,
and audio presence of the supplied neutral Live Photo template.
USAGE
}

if [[ $# -ne 4 ]]; then
  usage
  exit 2
fi

input_video="$1"
output_livp="$2"
template_photo="$3"
template_video="$4"

for f in "$input_video" "$template_photo" "$template_video"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing file: $f" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
output_livp="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output_livp")"

width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$template_video" | head -n 1)"
height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$template_video" | head -n 1)"
fps="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$template_video" | head -n 1)"
duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$template_video" | head -n 1)"
audio_index="$(ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$template_video" | head -n 1 || true)"

if [[ -z "$width" || -z "$height" || -z "$fps" || -z "$duration" || "$fps" == "0/0" ]]; then
  echo "Could not determine template video geometry/timing." >&2
  exit 1
fi

cover_time="$(python3 - "$duration" <<'PY'
import sys
duration=float(sys.argv[1])
print(f"{duration/2:.6f}")
PY
)"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/make-livp-template.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

normalized_mov="$tmp_dir/normalized.mov"
cover_jpg="$tmp_dir/cover.jpg"
pair_dir="$tmp_dir/pair"
zip_dir="$tmp_dir/zip"
mkdir -p "$pair_dir" "$zip_dir"

echo "Template: ${width}x${height}, duration=${duration}s, fps=${fps}, audio=$([[ -n "$audio_index" ]] && echo yes || echo no)"

vf="scale=${width}:${height}:force_original_aspect_ratio=increase,crop=${width}:${height},fps=${fps},setsar=1,format=yuv420p"

echo "Normalizing source video..."
if [[ -n "$audio_index" ]]; then
  ffmpeg -y \
    -stream_loop -1 -i "$input_video" \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -t "$duration" \
    -map 0:v:0 -map 1:a:0 \
    -vf "$vf" \
    -c:v hevc_videotoolbox \
    -tag:v hvc1 \
    -c:a aac \
    -b:a 64k \
    -shortest \
    -movflags +faststart \
    "$normalized_mov"
else
  ffmpeg -y \
    -stream_loop -1 -i "$input_video" \
    -t "$duration" \
    -map 0:v:0 \
    -an \
    -vf "$vf" \
    -c:v hevc_videotoolbox \
    -tag:v hvc1 \
    -movflags +faststart \
    "$normalized_mov"
fi

echo "Extracting cover at ${cover_time}s..."
ffmpeg -y \
  -ss "$cover_time" \
  -i "$normalized_mov" \
  -frames:v 1 \
  "$cover_jpg"

echo "Building Swift packager..."
(
  cd "$repo_dir"
  swift build
)

echo "Writing Live Photo metadata..."
(
  cd "$repo_dir"
  swift run livephoto-packager \
    --photo "$cover_jpg" \
    --template-photo-metadata "$template_photo" \
    --video "$normalized_mov" \
    --template-video "$template_video" \
    --out "$pair_dir" \
    --photo-format heic \
    --preserve-input-metadata-tracks
)

photo_path="$pair_dir/live-photo.heic"
video_path="$pair_dir/live-photo.mov"

if [[ ! -f "$photo_path" || ! -f "$video_path" ]]; then
  echo "Packager did not produce the expected HEIC + MOV pair." >&2
  exit 1
fi

echo "Inspecting copied metadata tracks..."
node "$repo_dir/tools/dump-mebx-samples.js" "$video_path" > "$tmp_dir/mebx.txt"
if ! grep -q '^TRACK ' "$tmp_dir/mebx.txt"; then
  echo "No metadata tracks were found in generated MOV." >&2
  cat "$tmp_dir/mebx.txt" >&2
  exit 1
fi
cat "$tmp_dir/mebx.txt"

echo "Packaging compatible .livp..."
base_name="IMB_$(uuidgen | tr -d '-' | cut -c1-8).HEIC"
cp "$photo_path" "$zip_dir/$base_name.heic"
cp "$video_path" "$zip_dir/$base_name.mov"

mkdir -p "$(dirname "$output_livp")"
rm -f "$output_livp"
(
  cd "$zip_dir"
  zip -0 -X -q "$output_livp" "$base_name.heic" "$base_name.mov"
)

node "$repo_dir/tools/set-livp-zip-comment.js" "$output_livp" >/dev/null

if [[ ! -s "$output_livp" ]]; then
  echo "Failed to create output .livp." >&2
  exit 1
fi

echo "Created $output_livp"
