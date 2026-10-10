#!/bin/bash
# Public release configuration. Private signing keys belong in Keychain or CI secrets.
RELEASE_VERSION="${RELEASE_VERSION:-0.3.0}"
BUILD_NUMBER="${BUILD_NUMBER:-5}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-producktive}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-bvyEmRYNB3xRtLyvwQqv7QiU9HqqxNHUILQZ2TLnA/o=}"
UPDATE_BASE_URL="${UPDATE_BASE_URL:-https://updates.duck-type.com/producktive/stable}"
R2_UPDATE_REMOTE="${R2_UPDATE_REMOTE:-r2:ducktype-app-updates/producktive/stable}"
DIST_DIR="${DIST_DIR:-dist}"
export RELEASE_VERSION BUILD_NUMBER SPARKLE_PUBLIC_ED_KEY UPDATE_BASE_URL SPARKLE_KEY_ACCOUNT DIST_DIR
