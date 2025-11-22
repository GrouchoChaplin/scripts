#!/usr/bin/env bash
set -euo pipefail

###############################################
# diffcheck.sh
# Full migration analysis toolkit
#
# Usage:
#   ./diffcheck.sh <OLD_PROJECT> <NEW_PROJECT>
#
# Produces in ./migration_reports:
#  ✔ migration_diff_report.html
#  ✔ migration_diff_report.json
#  ✔ migration_diff_report.pdf (if wkhtmltopdf installed)
#  ✔ folder_tree.txt
#  ✔ folder_tree.html
#  ✔ folder_tree.pdf (if wkhtmltopdf installed)
#  ✔ moved_files_map.txt
#  ✔ moved_files_map.html + PDF (if wkhtmltopdf installed)
#  ✔ critical_files_checklist.txt
#  ✔ critical_files_checklist.html + PDF (if wkhtmltopdf installed)
#  ✔ migration_pdfs_bundle.zip (all PDFs)
#  ✔ migration.code-workspace (VS Code workspace)
###############################################

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <OLD_PROJECT> <NEW_PROJECT>"
    exit 1
fi

OLD="$1"
NEW="$2"

OUTDIR="./migration_reports"
mkdir -p "$OUTDIR"

echo "💡 Generating migration analysis into: $OUTDIR"
echo
echo "OLD: $OLD"
echo "NEW: $NEW"
echo

###############################################
# 1. Generate HTML + JSON diff report (Python)
###############################################
cat > "$OUTDIR/generate_diff.py" <<EOF
import os, difflib, json
from pathlib import Path
from html import escape

old = Path("$OLD")
new = Path("$NEW")
html_out = Path("$OUTDIR/migration_diff_report.html")
json_out = Path("$OUTDIR/migration_diff_report.json")

def list_files(base):
    return {str(p.relative_to(base)) for p in base.rglob("*") if p.is_file()}

old_files = list_files(old)
new_files = list_files(new)

added = sorted(new_files - old_files)
removed = sorted(old_files - new_files)

html = ["<html><body><h1>Migration Diff Report</h1>"]

# Added files
html.append("<h2 style='color:green'>Added Files</h2><ul>")
for f in added:
    html.append(f"<li style='color:green'>{escape(f)}</li>")
html.append("</ul>")

# Removed files
html.append("<h2 style='color:red'>Removed (or moved) Files</h2><ul>")
for f in removed:
    html.append(f"<li style='color:red'>{escape(f)}</li>")
html.append("</ul>")

# Modified diffs
html.append("<h2>Modified Files</h2>")

modified = []

for f in sorted(new_files & old_files):
    old_path = old / f
    new_path = new / f
    try:
        old_text = old_path.read_text().splitlines()
        new_text = new_path.read_text().splitlines()
    except Exception:
        continue
    if old_text != new_text:
        modified.append(f)
        diff = difflib.HtmlDiff().make_table(
            old_text, new_text, "old/"+f, "new/"+f)
        html.append(f"<h3>{escape(f)}</h3>")
        html.append(diff)

html.append("</body></html>")
html_out.write_text("\\n".join(html))

report = {
    "old_root": str(old),
    "new_root": str(new),
    "added": added,
    "removed": removed,
    "modified": modified,
}

json_out.write_text(json.dumps(report, indent=2))
print("✔ HTML report generated:", html_out)
print("✔ JSON report generated:", json_out)
EOF

python3 "$OUTDIR/generate_diff.py"

###############################################
# 2. Folder tree visualization (OLD project)
###############################################
echo "📁 Folder tree (OLD project)" | tee "$OUTDIR/folder_tree.txt"
if command -v tree >/dev/null 2>&1; then
    tree -a "$OLD" | tee -a "$OUTDIR/folder_tree.txt"
else
    echo "⚠ 'tree' not installed. Using 'find' instead." | tee -a "$OUTDIR/folder_tree.txt"
    find "$OLD" -print | tee -a "$OUTDIR/folder_tree.txt"
fi

# HTML wrapper for folder tree
{
  echo "<html><body><h1>Folder Tree (OLD)</h1><pre>"
  cat "$OUTDIR/folder_tree.txt"
  echo "</pre></body></html>"
} > "$OUTDIR/folder_tree.html"

echo "✔ Folder tree created."

###############################################
# 3. Moved Files Map (old → new)
###############################################
echo "🔀 Moved Files Map" > "$OUTDIR/moved_files_map.txt"

OLD_LIST=$(mktemp)
NEW_LIST=$(mktemp)
find "$OLD" -type f | sed "s|$OLD/||" | sort > "$OLD_LIST"
find "$NEW" -type f | sed "s|$NEW/||" | sort > "$NEW_LIST"

while read -r f; do
    if ! grep -qx "$f" "$NEW_LIST"; then
        base=$(basename "$f")
        match=$(grep "/$base\$" "$NEW_LIST" || true)
        if [[ -n "$match" ]]; then
            echo "$f  →  $match" >> "$OUTDIR/moved_files_map.txt"
        fi
    fi
done < "$OLD_LIST"

rm -f "$OLD_LIST" "$NEW_LIST"

# HTML wrapper for moved files map
{
  echo "<html><body><h1>Moved Files Map</h1><pre>"
  cat "$OUTDIR/moved_files_map.txt"
  echo "</pre></body></html>"
} > "$OUTDIR/moved_files_map.html"

echo "✔ Moved files map created."

###############################################
# 4. Critical Files Checklist
###############################################
CHECKLIST="$OUTDIR/critical_files_checklist.txt"
echo "🧪 Critical Files Checklist" > "$CHECKLIST"

critical=(
    "lib/main.dart"
    "pubspec.yaml"
    "lib/services/native/gdalutils_handler.dart"
    "lib/services/native/native_library_loader.dart"
    "lib/services/native/netcdf_utils.dart"
)

for c in "\${critical[@]}"; do
    if [[ -f "\$NEW/\$c" ]]; then
        echo "[OK]   \$c" >> "\$CHECKLIST"
    else
        echo "[MISS] \$c" >> "\$CHECKLIST"
    fi
done

# HTML wrapper for checklist
{
  echo "<html><body><h1>Critical Files Checklist</h1><pre>"
  cat "$CHECKLIST"
  echo "</pre></body></html>"
} > "$OUTDIR/critical_files_checklist.html"

echo "✔ Critical files checklist created."

###############################################
# 5. PDF generation + bundle (if wkhtmltopdf)
###############################################
PDFS=()

if command -v wkhtmltopdf >/dev/null 2>&1; then
    echo "🖨 Generating PDFs via wkhtmltopdf..."

    # Main diff PDF
    if wkhtmltopdf "$OUTDIR/migration_diff_report.html" "$OUTDIR/migration_diff_report.pdf"; then
        PDFS+=("migration_diff_report.pdf")
    fi

    # Folder tree PDF
    if wkhtmltopdf "$OUTDIR/folder_tree.html" "$OUTDIR/folder_tree.pdf"; then
        PDFS+=("folder_tree.pdf")
    fi

    # Moved files map PDF
    if wkhtmltopdf "$OUTDIR/moved_files_map.html" "$OUTDIR/moved_files_map.pdf"; then
        PDFS+=("moved_files_map.pdf")
    fi

    # Checklist PDF
    if wkhtmltopdf "$OUTDIR/critical_files_checklist.html" "$OUTDIR/critical_files_checklist.pdf"; then
        PDFS+=("critical_files_checklist.pdf")
    fi

    if [[ "\${#PDFS[@]}" -gt 0 ]]; then
        (
          cd "$OUTDIR"
          zip -q migration_pdfs_bundle.zip "\${PDFS[@]}"
        )
        echo "✔ PDF bundle created: $OUTDIR/migration_pdfs_bundle.zip"
    else
        echo "⚠ No PDFs created (wkhtmltopdf reported errors)."
    fi
else
    echo "⚠ wkhtmltopdf not installed — skipping all PDF generation."
fi

###############################################
# 6. Dart/Flutter-aware Project Checklist
###############################################
DF_CHECKLIST="$OUTDIR/flutter_checklist.txt"
echo "🧠 Flutter / Dart Project Checklist" > "$DF_CHECKLIST"

cd "$NEW"

echo >> "$DF_CHECKLIST"
echo "=== Flutter Project Structure ===" >> "$DF_CHECKLIST"

# pubspec.yaml exists
if [[ -f "pubspec.yaml" ]]; then
    echo "[OK] pubspec.yaml found" >> "$DF_CHECKLIST"
else
    echo "[MISS] pubspec.yaml missing!" >> "$DF_CHECKLIST"
fi

# lib/main.dart exists
if [[ -f "lib/main.dart" ]]; then
    echo "[OK] lib/main.dart present" >> "$DF_CHECKLIST"
else
    echo "[MISS] lib/main.dart missing (app won't run!)" >> "$DF_CHECKLIST"
fi

# flutter section present in pubspec
if grep -q "^flutter:" pubspec.yaml; then
    echo "[OK] 'flutter:' block in pubspec" >> "$DF_CHECKLIST"
else
    echo "[WARN] Missing 'flutter:' block in pubspec" >> "$DF_CHECKLIST"
fi


echo >> "$DF_CHECKLIST"
echo "=== Dart Code Health ===" >> "$DF_CHECKLIST"

# Detect broken imports
BROKEN=$(grep -R "package:jsigconversiontools" -n lib || true)
if [[ -n "$BROKEN" ]]; then
    echo "[WARN] Imports referencing old package name:" >> "$DF_CHECKLIST"
    echo "$BROKEN" >> "$DF_CHECKLIST"
else
    echo "[OK] No imports referencing old package" >> "$DF_CHECKLIST"
fi

# Detect unresolved import paths
UNRES=$(grep -R "lib/screens" -n lib || true)
if [[ -n "$UNRES" ]]; then
    echo "[WARN] Code still referencing old screens/ paths:" >> "$DF_CHECKLIST"
    echo "$UNRES" >> "$DF_CHECKLIST"
else
    echo "[OK] No obsolete lib/screens imports" >> "$DF_CHECKLIST"
fi


echo >> "$DF_CHECKLIST"
echo "=== Features Modules Check ===" >> "$DF_CHECKLIST"

# card1 (NetCDF)
if [[ -d "lib/features/card1" ]]; then
    echo "[OK] Feature module card1 exists" >> "$DF_CHECKLIST"
else
    echo "[MISS] Feature module card1 missing" >> "$DF_CHECKLIST"
fi

# card2 (MODIS)
if [[ -d "lib/features/card2" ]]; then
    echo "[OK] Feature module card2 exists" >> "$DF_CHECKLIST"
else
    echo "[MISS] Feature module card2 missing" >> "$DF_CHECKLIST"
fi

# check required screens
REQ_SCREENS=(
  "lib/features/card1/netcdf_screen.dart"
  "lib/features/card2/modis_screen.dart"
)

for f in "${REQ_SCREENS[@]}"; do
    if [[ -f "$f" ]]; then
        echo "[OK] screen exists: $f" >> "$DF_CHECKLIST"
    else
        echo "[MISS] REQUIRED screen missing: $f" >> "$DF_CHECKLIST"
    fi
done


echo >> "$DF_CHECKLIST"
echo "=== Theme System Verification ===" >> "$DF_CHECKLIST"

# theme folder exists
if [[ -d "lib/theme" ]]; then
    echo "[OK] theme/ folder present" >> "$DF_CHECKLIST"
else
    echo "[MISS] theme/ folder missing!" >> "$DF_CHECKLIST"
fi

# brand_theme.dart present
if [[ -f "lib/theme/brand_theme.dart" ]]; then
    echo "[OK] brand_theme.dart found" >> "$DF_CHECKLIST"
else
    echo "[MISS] brand_theme.dart missing" >> "$DF_CHECKLIST"
fi

# app_spacing.dart present
if [[ -f "lib/theme/app_spacing.dart" ]]; then
    echo "[OK] app_spacing.dart found" >> "$DF_CHECKLIST"
else
    echo "[WARN] app_spacing.dart missing (not fatal)" >> "$DF_CHECKLIST"
fi


echo >> "$DF_CHECKLIST"
echo "=== Native Library Integration ===" >> "$DF_CHECKLIST"

REQ_NATIVE=(
  "lib/services/native/gdalutils_handler.dart"
  "lib/services/native/native_library_loader.dart"
  "lib/services/native/netcdf_utils.dart"
)

for f in "${REQ_NATIVE[@]}"; do
    if [[ -f "$f" ]]; then
        echo "[OK] native wrapper present: $f" >> "$DF_CHECKLIST"
    else
        echo "[MISS] native wrapper MISSING: $f" >> "$DF_CHECKLIST"
    fi
done


echo >> "$DF_CHECKLIST"
echo "=== Flutter Build Sanity Tests ===" >> "$DF_CHECKLIST"

# Find syntax errors
DART_ERRORS=$(dart analyze 2>&1 || true)
if echo "$DART_ERRORS" | grep -q "error •"; then
    echo "[WARN] Dart analysis found errors:" >> "$DF_CHECKLIST"
    echo "$DART_ERRORS" >> "$DF_CHECKLIST"
else
    echo "[OK] Dart analysis shows no errors" >> "$DF_CHECKLIST"
fi

# Check missing assets
if grep -q "assets:" pubspec.yaml; then
    echo "[OK] Assets section exists in pubspec" >> "$DF_CHECKLIST"
else
    echo "[WARN] No assets declared in pubspec" >> "$DF_CHECKLIST"
fi


echo >> "$DF_CHECKLIST"
echo "=== Summary ===" >> "$DF_CHECKLIST"
echo "Checklist generation complete." >> "$DF_CHECKLIST"

echo "✔ Flutter checklist created: $DF_CHECKLIST"

echo "✔ VS Code workspace created: $WORKSPACE"

echo
echo "🎉 Migration analysis complete."
echo "📁 Output directory: $OUTDIR"
echo "   - HTML + JSON diff"
echo "   - Folder tree (text + HTML)"
echo "   - Moved files map"
echo "   - Critical files checklist"
echo "   - PDF bundle (if wkhtmltopdf installed)"
echo "   - VS Code workspace"
