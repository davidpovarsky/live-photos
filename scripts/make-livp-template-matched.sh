#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/make-livp-template-matched.sh INPUT_VIDEO OUTPUT.livp NEUTRAL_METADATA_TEMPLATE.mov

Creates the fixed lock-screen-oriented MVP:
  - 1080x1920
  - 1.0 second
  - 60 fps
  - HEVC tagged hvc1
  - silent AAC audio
  - cover frame at 0.5s
  - neutral mebx metadata copied from the supplied compact template
USAGE
}

if [[ $# -ne 3 ]]; then
  usage
  exit 2
fi

input_video="$1"
output_livp="$2"
template_video="$3"

for f in "$input_video" "$template_video"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing file: $f" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
output_livp="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output_livp")"

width=1080
height=1920
fps=60
duration=1
cover_time=0.5

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

vf="scale=${width}:${height}:force_original_aspect_ratio=increase,crop=${width}:${height},fps=${fps},setsar=1,format=yuv420p"

encode_common=(
  -y
  -stream_loop -1 -i "$input_video"
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100"
  -t "$duration"
  -map 0:v:0 -map 1:a:0
  -vf "$vf"
  -tag:v hvc1
  -c:a aac
  -b:a 64k
  -shortest
  -movflags +faststart
)

echo "Normalizing source video to ${width}x${height} / ${fps}fps / ${duration}s..."

if ffmpeg "${encode_common[@]}" -c:v hevc_videotoolbox "$normalized_mov"; then
  echo "Encoded HEVC with VideoToolbox."
else
  echo "VideoToolbox encoder unavailable; falling back to libx265."
  rm -f "$normalized_mov"
  ffmpeg "${encode_common[@]}" -c:v libx265 -preset fast -pix_fmt yuv420p "$normalized_mov"
fi

ffprobe -v error   -select_streams v:0   -show_entries stream=codec_name,codec_tag_string,width,height,avg_frame_rate,nb_frames   -show_entries format=duration   -of default=noprint_wrappers=1 "$normalized_mov"

echo "Extracting cover at ${cover_time}s..."
ffmpeg -y   -ss "$cover_time"   -i "$normalized_mov"   -frames:v 1   "$cover_jpg"

echo "Building Swift packager..."
(
  cd "$repo_dir"
  swift build
)

echo "Writing Live Photo metadata..."
(
  cd "$repo_dir"
  swift run livephoto-packager     --photo "$cover_jpg"     --video "$normalized_mov"     --template-video "$template_video"     --out "$pair_dir"     --photo-format heic     --preserve-input-metadata-tracks
)

photo_path="$pair_dir/live-photo.heic"
video_path="$pair_dir/live-photo.mov"

if [[ ! -f "$photo_path" || ! -f "$video_path" ]]; then
  echo "Packager did not produce the expected HEIC + MOV pair." >&2
  exit 1
fi

echo "Verifying copied metadata tracks..."
node "$repo_dir/tools/dump-mebx-samples.js" "$video_path" > "$tmp_dir/mebx.txt"
cat "$tmp_dir/mebx.txt"

if ! grep -q 'samples=57' "$tmp_dir/mebx.txt"; then
  echo "Generated MOV is missing the 57-sample neutral live-photo-info track." >&2
  exit 1
fi

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
