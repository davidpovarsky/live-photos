#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/make-livp.sh input-video output.livp

Creates a wallpaper-capable .livp candidate using a compatible neutral
mebx template supplied by the user.

Fixed MVP output:
  - 1080x1920
  - 1 second
  - 60 fps
  - HEVC hvc1 MOV
  - silent AAC audio
  - cover frame at 0.5s
USAGE
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

input_video="$1"
output_livp="$2"

if [[ ! -f "$input_video" ]]; then
  echo "Input video not found: $input_video" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
output_livp="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output_livp")"
template_photo="${LIVEPHOTO_TEMPLATE_PHOTO:-$repo_dir/vendor-livp/IMB_ZyUbrU.HEIC.heic}"
template_video="${LIVEPHOTO_TEMPLATE_VIDEO:-$repo_dir/vendor-livp/IMB_ZyUbrU.HEIC.mov}"

if [[ ! -f "$template_photo" || ! -f "$template_video" ]]; then
  echo "Missing neutral Live Photo template assets." >&2
  echo "Provide assets you have the right to use by either:" >&2
  echo "  1. placing them at:" >&2
  echo "     $repo_dir/vendor-livp/IMB_ZyUbrU.HEIC.heic" >&2
  echo "     $repo_dir/vendor-livp/IMB_ZyUbrU.HEIC.mov" >&2
  echo "  2. or setting:" >&2
  echo "     LIVEPHOTO_TEMPLATE_PHOTO=/path/to/template.heic" >&2
  echo "     LIVEPHOTO_TEMPLATE_VIDEO=/path/to/template.mov" >&2
  echo "See docs/template-assets.md for details." >&2
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/make-livp.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

normalized_mov="$tmp_dir/normalized.mov"
cover_jpg="$tmp_dir/cover.jpg"
pair_dir="$tmp_dir/pair"
zip_dir="$tmp_dir/zip"
mkdir -p "$pair_dir" "$zip_dir"

echo "Normalizing video..."
ffmpeg -y \
  -stream_loop -1 -i "$input_video" \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -t 1 \
  -map 0:v:0 -map 1:a:0 \
  -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,fps=60,setsar=1,format=yuv420p" \
  -c:v hevc_videotoolbox \
  -tag:v hvc1 \
  -c:a aac \
  -b:a 2k \
  -shortest \
  -movflags +faststart \
  "$normalized_mov"

echo "Extracting cover frame..."
ffmpeg -y \
  -ss 0.5 \
  -i "$normalized_mov" \
  -frames:v 1 \
  "$cover_jpg"

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
  echo "Packager did not produce expected Live Photo pair." >&2
  exit 1
fi

echo "Packaging .livp..."
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

echo "Created $output_livp"
