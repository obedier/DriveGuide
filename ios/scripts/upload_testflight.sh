#!/usr/bin/env bash
# =============================================================================
# Roamly - TestFlight Upload Script
# Archive → Export → Upload flow via xcodebuild + xcrun altool
#
# PREREQUISITES:
#   - Xcode installed with valid signing certificates and provisioning profiles
#   - API key at ~/.private_keys/AuthKey_V42G2XP7LB.p8
#   - xcrun altool or xcrun notarytool available (Xcode 13+)
#
# USAGE:
#   chmod +x upload_testflight.sh
#   ./upload_testflight.sh
#
# To skip archive (use existing .xcarchive):
#   SKIP_ARCHIVE=1 ./upload_testflight.sh
# =============================================================================

set -euo pipefail

# ============================================================
# CONFIGURATION
# ============================================================
KEY_ID="V42G2XP7LB"
ISSUER_ID="REPLACE_WITH_ISSUER_ID_UUID"   # <-- GET FROM App Store Connect UI
KEY_FILE="${HOME}/.private_keys/AuthKey_${KEY_ID}.p8"
TEAM_ID="U3972W2GDJ"
BUNDLE_ID="com.privatetourai.app"
SCHEME="PrivateTourAi"

# Paths
IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${IOS_DIR}/build/Roamly.xcarchive"
EXPORT_PATH="${IOS_DIR}/build/RoamlyExport"
EXPORT_OPTIONS_PLIST="${IOS_DIR}/scripts/ExportOptions.plist"
PROJECT_PATH="${IOS_DIR}/PrivateTourAi.xcodeproj"

# Build configuration
CONFIGURATION="Release"
# ============================================================

echo "============================================================"
echo "Roamly - TestFlight Build & Upload"
echo "============================================================"
echo "Project   : ${PROJECT_PATH}"
echo "Scheme    : ${SCHEME}"
echo "Archive   : ${ARCHIVE_PATH}"
echo "Export to : ${EXPORT_PATH}"
echo ""

# Validate required files
if [[ ! -f "${KEY_FILE}" ]]; then
    echo "ERROR: API key not found at ${KEY_FILE}"
    exit 1
fi

if [[ "${ISSUER_ID}" == "REPLACE_WITH_ISSUER_ID_UUID" ]]; then
    echo "ERROR: Set ISSUER_ID to your actual Issuer ID UUID."
    echo "Find it at: App Store Connect > Users and Access > Integrations > App Store Connect API"
    exit 1
fi

# ============================================================
# STEP 1: ARCHIVE
# ============================================================
if [[ "${SKIP_ARCHIVE:-0}" == "1" ]]; then
    echo "STEP 1: Skipping archive (SKIP_ARCHIVE=1)"
else
    echo "STEP 1: Archiving ${SCHEME} (${CONFIGURATION})..."
    xcodebuild archive \
        -project "${PROJECT_PATH}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -archivePath "${ARCHIVE_PATH}" \
        -destination "generic/platform=iOS" \
        CODE_SIGN_STYLE="Automatic" \
        DEVELOPMENT_TEAM="${TEAM_ID}" \
        -allowProvisioningUpdates \
        | xcpretty 2>/dev/null || true

    # Fallback if xcpretty not installed
    if [[ $? -ne 0 ]]; then
        xcodebuild archive \
            -project "${PROJECT_PATH}" \
            -scheme "${SCHEME}" \
            -configuration "${CONFIGURATION}" \
            -archivePath "${ARCHIVE_PATH}" \
            -destination "generic/platform=iOS" \
            CODE_SIGN_STYLE="Automatic" \
            DEVELOPMENT_TEAM="${TEAM_ID}" \
            -allowProvisioningUpdates
    fi

    echo "Archive created at: ${ARCHIVE_PATH}"
fi

# ============================================================
# STEP 2: EXPORT (produces .ipa)
# ============================================================
echo ""
echo "STEP 2: Exporting IPA..."
mkdir -p "${EXPORT_PATH}"

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
    -allowProvisioningUpdates

IPA_PATH=$(find "${EXPORT_PATH}" -name "*.ipa" | head -1)
if [[ -z "${IPA_PATH}" ]]; then
    echo "ERROR: No .ipa file found in ${EXPORT_PATH}"
    exit 1
fi
echo "IPA created at: ${IPA_PATH}"

# ============================================================
# STEP 3: UPLOAD TO APP STORE CONNECT (TestFlight)
# Using xcrun altool (Xcode 13+, deprecated but still works)
# ============================================================
echo ""
echo "STEP 3: Uploading to App Store Connect (TestFlight)..."
echo "Using xcrun altool with API key authentication..."

xcrun altool \
    --upload-app \
    --type ios \
    --file "${IPA_PATH}" \
    --apiKey "${KEY_ID}" \
    --apiIssuer "${ISSUER_ID}" \
    --verbose

echo ""
echo "============================================================"
echo "Upload complete! Check TestFlight in App Store Connect."
echo "Build typically processes within 5-30 minutes."
echo "============================================================"

# ============================================================
# ALTERNATIVE: Upload using xcrun notarytool (for macOS apps)
# For iOS apps, altool is still the correct tool for TestFlight.
# notarytool is for macOS notarization only.
# ============================================================
# xcrun notarytool submit "${IPA_PATH}" \
#     --key "${KEY_FILE}" \
#     --key-id "${KEY_ID}" \
#     --issuer "${ISSUER_ID}" \
#     --wait
