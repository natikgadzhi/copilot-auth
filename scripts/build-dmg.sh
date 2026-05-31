#!/usr/bin/env bash
#
# Build a signed (Developer ID Application) + notarized + stapled .app inside a
# drag-to-Applications .dmg for copilot-auth.
#
# Local use (signing identity in your login keychain, notary creds stored once
# with `xcrun notarytool store-credentials`):
#
#   NOTARY_KEYCHAIN_PROFILE="copilot-auth-notary" scripts/build-dmg.sh
#
# CI use (no certs on the runner): inject the signing material as env vars —
#   APPLE_DEVELOPER_ID_P12_BASE64, APPLE_DEVELOPER_ID_P12_PASSWORD,
#   APPLE_NOTARY_API_KEY_BASE64, APPLE_NOTARY_API_KEY_ID, APPLE_NOTARY_ISSUER_ID.
# The script then builds a throwaway keychain, imports the cert + Apple
# intermediates, and deletes the keychain on exit.
#
# Notarization needs the hardened runtime (--options runtime). copilot-auth is
# NOT App-Sandboxed, so its outbound network (WKWebView → Copilot/Firebase) and
# Keychain access work with no entitlements file. Add one only if that changes.
#
# Adapted from the KindleExporter release script.
set -euo pipefail

# The Xcode project is XcodeGen output (gitignored), so regenerate it first.
SCHEME="${SCHEME:-CopilotAuth}"
PROJECT_PATH="${PROJECT_PATH:-CopilotAuth.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-build/CopilotAuth.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-build/export}"
RELEASE_DIR="${RELEASE_DIR:-build/release}"
DMG_STAGING_DIR="${DMG_STAGING_DIR:-build/dmg}"
# The archived product is named after the target (PRODUCT_NAME = CopilotAuth).
APP_NAME="${APP_NAME:-CopilotAuth.app}"
DMG_BASENAME="${DMG_BASENAME:-${APP_NAME%.app}}"
DMG_VERSION="${DMG_VERSION:-}"
DMG_NAME="${DMG_NAME:-}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/copilot-auth-release.XXXXXX")"
TEMP_KEYCHAIN_PATH="${TEMP_DIR}/release-signing.keychain-db"
TEMP_KEYCHAIN_PASSWORD="${TEMP_KEYCHAIN_PASSWORD:-$(uuidgen)}"
TEMP_NOTARY_KEY_PATH="${TEMP_DIR}/AuthKey.p8"
KEYCHAIN_CREATED=0

cleanup() {
  if [[ "${KEYCHAIN_CREATED}" == "1" && -f "${TEMP_KEYCHAIN_PATH}" ]]; then
    security delete-keychain "${TEMP_KEYCHAIN_PATH}" >/dev/null 2>&1 || true
  fi
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command xcodegen
require_command xcodebuild
require_command codesign
require_command xcrun
require_command hdiutil
require_command ditto
require_command mktemp
require_command security
require_command base64
require_command curl

mkdir -p "${EXPORT_DIR}" "${RELEASE_DIR}" "${DMG_STAGING_DIR}"

decode_base64_to_file() {
  local input="$1"
  local output="$2"

  if base64 --help 2>&1 | grep -q -- '--decode'; then
    printf '%s' "${input}" | base64 --decode > "${output}"
  else
    printf '%s' "${input}" | base64 -D > "${output}"
  fi
}

import_signing_certificate_if_needed() {
  if [[ -z "${APPLE_DEVELOPER_ID_P12_BASE64:-}" ]]; then
    return
  fi

  if [[ -z "${APPLE_DEVELOPER_ID_P12_PASSWORD:-}" ]]; then
    echo "APPLE_DEVELOPER_ID_P12_PASSWORD is required when APPLE_DEVELOPER_ID_P12_BASE64 is set." >&2
    exit 1
  fi

  local cert_path="${TEMP_DIR}/developer-id.p12"
  decode_base64_to_file "${APPLE_DEVELOPER_ID_P12_BASE64}" "${cert_path}"

  security create-keychain -p "${TEMP_KEYCHAIN_PASSWORD}" "${TEMP_KEYCHAIN_PATH}"
  security set-keychain-settings -lut 21600 "${TEMP_KEYCHAIN_PATH}"
  security unlock-keychain -p "${TEMP_KEYCHAIN_PASSWORD}" "${TEMP_KEYCHAIN_PATH}"
  KEYCHAIN_CREATED=1

  local existing_keychains
  existing_keychains="$(security list-keychains -d user | tr -d '"')"
  # shellcheck disable=SC2086
  security list-keychains -d user -s "${TEMP_KEYCHAIN_PATH}" ${existing_keychains}
  security default-keychain -d user -s "${TEMP_KEYCHAIN_PATH}"

  security import "${cert_path}" \
    -k "${TEMP_KEYCHAIN_PATH}" \
    -P "${APPLE_DEVELOPER_ID_P12_PASSWORD}" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -T /usr/bin/xcodebuild

  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "${TEMP_KEYCHAIN_PASSWORD}" \
    "${TEMP_KEYCHAIN_PATH}" >/dev/null
}

install_apple_intermediates_if_needed() {
  # Only needed in CI, where the temp keychain has no Apple intermediates and
  # the .p12 may not have shipped them. Without the intermediate, the leaf
  # cert fails chain validation and `security find-identity -v` hides it.
  if [[ "${KEYCHAIN_CREATED}" != "1" ]]; then
    return
  fi

  local intermediates=(
    "https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer"
    "https://www.apple.com/certificateauthority/DeveloperIDCA.cer"
    "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer"
  )

  local url cert_path
  for url in "${intermediates[@]}"; do
    cert_path="${TEMP_DIR}/$(basename "${url}")"
    if curl -fsSL --retry 3 -o "${cert_path}" "${url}"; then
      security import "${cert_path}" -k "${TEMP_KEYCHAIN_PATH}" -T /usr/bin/codesign >/dev/null 2>&1 || true
    else
      echo "Warning: failed to download ${url}" >&2
    fi
  done
}

resolve_app_sign_identity() {
  if [[ -n "${APP_SIGN_IDENTITY}" ]]; then
    return
  fi

  # Pass the temp keychain explicitly in CI and skip `-v`. A fresh CI keychain
  # may lack Apple's Developer ID intermediate, which makes `-v` filter the
  # identity out even when codesign would happily use it.
  local find_identity_args=(-p codesigning)
  if [[ "${KEYCHAIN_CREATED}" == "1" ]]; then
    find_identity_args+=("${TEMP_KEYCHAIN_PATH}")
  fi

  APP_SIGN_IDENTITY="$(
    security find-identity "${find_identity_args[@]}" 2>/dev/null |
      sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
      head -n 1
  )"

  if [[ -z "${APP_SIGN_IDENTITY}" ]]; then
    echo "Could not find a Developer ID Application signing identity." >&2
    echo "Set APP_SIGN_IDENTITY or import a .p12 via APPLE_DEVELOPER_ID_P12_BASE64." >&2
    exit 1
  fi
}

resolve_release_metadata() {
  local info_plist="${EXPORT_DIR}/${APP_NAME}/Contents/Info.plist"

  if [[ -z "${DMG_VERSION}" ]]; then
    DMG_VERSION="$(
      /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}" 2>/dev/null || true
    )"
  fi

  if [[ -z "${DMG_VERSION}" ]]; then
    echo "Could not determine CFBundleShortVersionString for ${APP_NAME}." >&2
    echo "Set DMG_VERSION explicitly if the bundle does not expose a marketing version." >&2
    exit 1
  fi

  if [[ -z "${DMG_NAME}" ]]; then
    DMG_NAME="${DMG_BASENAME} ${DMG_VERSION}.dmg"
  fi
}

generate_project() {
  xcodegen generate
}

archive_app() {
  rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}/${APP_NAME}" "${DMG_STAGING_DIR}" "${RELEASE_DIR}"
  mkdir -p "${EXPORT_DIR}" "${RELEASE_DIR}" "${DMG_STAGING_DIR}"

  # Archive unsigned (deterministic, and keeps an `Apple Development` identity
  # from being baked into the archive and later rejected by notarization). We
  # sign the exported .app ourselves with Developer ID below.
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination 'generic/platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    archive \
    -archivePath "${ARCHIVE_PATH}"

  ditto \
    "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}" \
    "${EXPORT_DIR}/${APP_NAME}"

  resolve_release_metadata
}

sign_and_verify_app() {
  codesign --force --deep --options runtime --timestamp \
    --sign "${APP_SIGN_IDENTITY}" \
    "${EXPORT_DIR}/${APP_NAME}"

  codesign --verify --deep --strict --verbose=2 "${EXPORT_DIR}/${APP_NAME}"
  spctl -a -vvv "${EXPORT_DIR}/${APP_NAME}" || true
}

build_dmg() {
  rm -rf "${DMG_STAGING_DIR}"
  mkdir -p "${DMG_STAGING_DIR}"

  ditto "${EXPORT_DIR}/${APP_NAME}" "${DMG_STAGING_DIR}/${APP_NAME}"
  ln -s /Applications "${DMG_STAGING_DIR}/Applications"

  hdiutil create \
    -volname "${APP_NAME%.app}" \
    -srcfolder "${DMG_STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${RELEASE_DIR}/${DMG_NAME}"
}

notarize_and_staple_dmg() {
  if [[ -n "${APPLE_NOTARY_API_KEY_BASE64:-}" ]]; then
    if [[ -z "${APPLE_NOTARY_API_KEY_ID:-}" || -z "${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
      echo "APPLE_NOTARY_API_KEY_ID and APPLE_NOTARY_ISSUER_ID are required with APPLE_NOTARY_API_KEY_BASE64." >&2
      exit 1
    fi

    decode_base64_to_file "${APPLE_NOTARY_API_KEY_BASE64}" "${TEMP_NOTARY_KEY_PATH}"

    xcrun notarytool submit "${RELEASE_DIR}/${DMG_NAME}" \
      --key "${TEMP_NOTARY_KEY_PATH}" \
      --key-id "${APPLE_NOTARY_API_KEY_ID}" \
      --issuer "${APPLE_NOTARY_ISSUER_ID}" \
      --wait
  elif [[ -n "${NOTARY_KEYCHAIN_PROFILE}" ]]; then
    xcrun notarytool submit "${RELEASE_DIR}/${DMG_NAME}" \
      --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" \
      --wait
  else
    echo "Provide notarization credentials via NOTARY_KEYCHAIN_PROFILE or APPLE_NOTARY_API_KEY_* env vars." >&2
    exit 1
  fi

  xcrun stapler staple "${RELEASE_DIR}/${DMG_NAME}"
  xcrun stapler validate "${RELEASE_DIR}/${DMG_NAME}"
  spctl -a -vvv --type open "${RELEASE_DIR}/${DMG_NAME}" || true
}

print_summary() {
  cat <<EOF
Release artifacts:
  App: ${EXPORT_DIR}/${APP_NAME}
  DMG: ${RELEASE_DIR}/${DMG_NAME}

Signing identity:
  ${APP_SIGN_IDENTITY}

Notarization:
  completed
EOF
}

import_signing_certificate_if_needed
install_apple_intermediates_if_needed
resolve_app_sign_identity
generate_project
archive_app
sign_and_verify_app
build_dmg
notarize_and_staple_dmg
print_summary
