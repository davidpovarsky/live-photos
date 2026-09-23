#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/make-livp-template-matched.sh INPUT_VIDEO OUTPUT.livp NEUTRAL_METADATA_TEMPLATE.mov [START_TIME] [DURATION]

Defaults:
  START_TIME = 0
  DURATION   = 3.0

Creates a lock-screen-oriented Live Photo using the real source-video motion:
  - 1080x1920
  - configurable duration (default 3.0s)
  - configurable source start time
  - 60 fps
  - HEVC tagged hvc1
  - silent AAC audio
  - cover frame at the middle of the output
  - neutral mebx metadata adapted to the requested duration
USAGE
}

if [[ $# -lt 3 || $# -gt 5 ]]; then
  usage
  exit 2
fi

input_video="$1"
output_livp="$2"
template_video="$3"
start_time="${4:-0}"
duration="${5:-3.0}"

for f in "$input_video" "$template_video"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing file: $f" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
output_livp="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output_livp")"

python3 - "$start_time" "$duration" <<'PY'
import sys
start=float(sys.argv[1])
duration=float(sys.argv[2])
if start < 0:
    raise SystemExit("START_TIME must be >= 0")
if duration <= 0 or duration > 5:
    raise SystemExit("DURATION must be > 0 and <= 5 seconds")
PY

width=1080
height=1920
fps=60
cover_time="$(python3 - "$duration" <<'PY'
import sys
print(f"{float(sys.argv[1]) / 2:.6f}")
PY
)"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/make-livp-template.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

normalized_mov="$tmp_dir/normalized.mov"
cover_jpg="$tmp_dir/cover.jpg"
adapted_template="$tmp_dir/adapted-template.mov"
pair_dir="$tmp_dir/pair"
zip_dir="$tmp_dir/zip"
mkdir -p "$pair_dir" "$zip_dir"

expected_samples="$(python3 - "$duration" <<'PY'
import sys
duration=float(sys.argv[1])
print(max(1, int(round((duration - 0.05) * 60))))
PY
)"

echo "Extending neutral metadata template to ${duration}s..."
python3 "$repo_dir/tools/extend-neutral-template.py" \
  "$template_video" \
  "$adapted_template" \
  "$duration" \
  "$cover_time"

node "$repo_dir/tools/dump-mebx-samples.js" "$adapted_template" > "$tmp_dir/adapted-template-mebx.txt"
cat "$tmp_dir/adapted-template-mebx.txt"

if ! grep -q "samples=${expected_samples}" "$tmp_dir/adapted-template-mebx.txt"; then
  echo "Adapted template does not contain the expected live-photo-info sample count (${expected_samples})." >&2
  exit 1
fi

vf="scale=${width}:${height}:force_original_aspect_ratio=increase,crop=${width}:${height},fps=${fps},setsar=1,format=yuv420p"

encode_common=(
  -y
  -stream_loop -1
  -ss "$start_time"
  -i "$input_video"
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

echo "Using original source motion from ${start_time}s for ${duration}s."
echo "Normalizing to ${width}x${height} / ${fps}fps; cover at ${cover_time}s..."

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
  swift run livephoto-packager     --photo "$cover_jpg"     --video "$normalized_mov"     --template-video "$adapted_template"     --out "$pair_dir"     --photo-format heic     --still-image-time "$cover_time"     --preserve-input-metadata-tracks
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

if ! grep -q "samples=${expected_samples}" "$tmp_dir/mebx.txt"; then
  echo "Generated MOV does not contain the expected adapted live-photo-info sample count (${expected_samples})." >&2
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
