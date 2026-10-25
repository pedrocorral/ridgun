# Ridgun Support for `gedit` and GNOME Text Editor

This directory provides syntax highlighting (`ridgun.lang`) and canonical formatting (`ridgun-format`) for **gedit** and **GNOME Text Editor** (`gnome-text-editor`).

## Files

- `ridgun.lang`: GtkSourceView 2.0 language specification (`*.rg`, `*.rglib`, `build.rg`). Works with GtkSourceView 3, 4, and 5.
- `ridgun-format`: External Tool script for `gedit` (and standalone CLI wrapper) that formats Ridgun buffers using `stable format` (`FR-TOOL-001`).
- `install.sh`: Copies `ridgun.lang` into `~/.local/share/{libgedit-gtksourceview-300,gtksourceview-3.0,gtksourceview-4,gtksourceview-5}/language-specs/` and `ridgun-format` into `~/.config/gedit/tools/`.

## Installation

```bash
./editors/gedit/install.sh
```

## Usage in `gedit`

1. Open any `.rg` file in `gedit` or `gnome-text-editor` — syntax highlighting is applied automatically.
2. In `gedit`, enable **Preferences → Plugins → External Tools**.
3. Press **`Ctrl+Alt+F`** (or choose **Tools → External Tools → Format Ridgun File (stable format)**) to align `fn ::` / `op ::` signatures, pattern clauses, `=>` / `=` arrows, and 2-space blocks.
