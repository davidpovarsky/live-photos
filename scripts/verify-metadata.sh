#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 live-photo.jpg live-photo.mov" >&2
  exit 1
fi

photo="$1"
video="$2"

echo "JPEG MakerApple metadata:"
swift -e "import Foundation; import ImageIO; let url=URL(fileURLWithPath:\"$photo\"); guard let src=CGImageSourceCreateWithURL(url as CFURL,nil), let props=CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [String:Any] else { fatalError(\"Cannot read image metadata\") }; print(props[\"{MakerApple}\"] ?? \"Missing {MakerApple}\")"

echo
echo "MOV format tags:"
ffprobe -v error -show_entries format_tags -of json "$video"

echo
echo "MOV data streams:"
ffprobe -v error -show_streams -select_streams d -of json "$video"
