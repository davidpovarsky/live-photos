#!/usr/bin/env bash
set -euo pipefail

mkdir -p Samples

ffmpeg -y \
  -f lavfi -i "color=c=#0b1020:s=1080x1920:d=1" \
  -vf "drawtext=text='Live Photo Spike':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2,drawtext=text='Still frame':fontcolor=#80eaff:fontsize=42:x=(w-text_w)/2:y=(h-text_h)/2+96" \
  -frames:v 1 Samples/sample.jpg

ffmpeg -y \
  -f lavfi -i "testsrc2=size=1080x1920:rate=30:duration=3" \
  -vf "drawtext=text='Live Photo Spike':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart Samples/sample.mov
