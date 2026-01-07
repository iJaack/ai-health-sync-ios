#!/bin/bash
# package-clawdhub.sh - Package healthkit-sync skill for ClawdHub publishing
# Usage: ./scripts/package-clawdhub.sh [version]
# Example: ./scripts/package-clawdhub.sh 1.0.0

set -euo pipefail

# Configuration
SKILL_NAME="healthkit-sync"
SKILL_DIR="skills/${SKILL_NAME}"
OUTPUT_DIR="dist"

# Get version from argument or default
VERSION="${1:-1.0.0}"

# Validate semver format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid version format. Use semver (e.g., 1.0.0)"
    exit 1
fi

# Output filename
OUTPUT_FILE="${OUTPUT_DIR}/${SKILL_NAME}-${VERSION}.zip"

echo "Packaging ${SKILL_NAME} v${VERSION} for ClawdHub..."

# Verify skill directory exists
if [[ ! -d "$SKILL_DIR" ]]; then
    echo "Error: Skill directory not found: ${SKILL_DIR}"
    exit 1
fi

# Verify SKILL.md exists (required by ClawdHub)
if [[ ! -f "${SKILL_DIR}/SKILL.md" ]]; then
    echo "Error: SKILL.md not found in ${SKILL_DIR}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Remove existing zip if present
rm -f "$OUTPUT_FILE"

# Create zip excluding unnecessary files
cd "$SKILL_DIR"
zip -r "../../${OUTPUT_FILE}" . \
    -x "HOWTO_CLAWDHUB.md" \
    -x "*.DS_Store" \
    -x "__MACOSX/*" \
    -x "*.zip" \
    -x ".git/*"
cd - > /dev/null

# Verify output
if [[ -f "$OUTPUT_FILE" ]]; then
    SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    echo ""
    echo "Package created: ${OUTPUT_FILE} (${SIZE})"
    echo ""
    echo "Contents:"
    unzip -l "$OUTPUT_FILE" | grep -E "^\s+[0-9]+" | awk '{print $4}'
    echo ""
    echo "Next steps:"
    echo "  1. Go to https://clawdhub.com/publish"
    echo "  2. Fill in:"
    echo "     - Slug: ${SKILL_NAME}"
    echo "     - Display name: HealthKit Sync"
    echo "     - Version: ${VERSION}"
    echo "     - Tags: latest, healthkit, ios, macos, health"
    echo "  3. Upload: ${OUTPUT_FILE}"
    echo "  4. Click Publish"
else
    echo "Error: Failed to create package"
    exit 1
fi
