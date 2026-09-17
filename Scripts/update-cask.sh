#!/bin/zsh
# Rewrites version and sha256 in a Homebrew cask file.
#   Scripts/update-cask.sh <cask.rb> <version> <sha256>
set -euo pipefail
CASK="$1"; VERSION="$2"; SHA="$3"
sed -i '' -E "s/^  version \".*\"$/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" "$CASK"
grep -E '^  (version|sha256) ' "$CASK"
