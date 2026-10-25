#!/usr/bin/env bash
# editors/gedit/install.sh
# Installs Ridgun syntax highlighting (ridgun.lang) for gedit and GNOME Text Editor,
# and installs the canonical formatter tool (ridgun-format) for gedit External Tools.
# @implements FR-TOOL-001

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for ver in libgedit-gtksourceview-300 gtksourceview-3.0 gtksourceview-4 gtksourceview-5; do
  dest_dir="$HOME/.local/share/$ver/language-specs"
  mkdir -p "$dest_dir"
  cp "$SCRIPT_DIR/ridgun.lang" "$dest_dir/ridgun.lang"
  echo "[installed] $dest_dir/ridgun.lang"
done

GEDIT_TOOLS_DIR="$HOME/.config/gedit/tools"
mkdir -p "$GEDIT_TOOLS_DIR"
cp "$SCRIPT_DIR/ridgun-format" "$GEDIT_TOOLS_DIR/ridgun-format"
chmod +x "$GEDIT_TOOLS_DIR/ridgun-format"
echo "[installed] $GEDIT_TOOLS_DIR/ridgun-format"
