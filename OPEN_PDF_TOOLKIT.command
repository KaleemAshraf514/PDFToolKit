#!/bin/zsh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$HERE/PDFToolkit.xcworkspace" ]; then
  open -a Xcode "$HERE/PDFToolkit.xcworkspace"
elif [ -d "$HERE/PDFToolkit.xcodeproj" ]; then
  open -a Xcode "$HERE/PDFToolkit.xcodeproj"
else
  echo "PDFToolkit Xcode workspace/project was not found next to this opener."
  read -k 1 "?Press any key to close..."
fi
