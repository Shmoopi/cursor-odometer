#!/bin/bash
#
# setup-signing-secrets.sh
# Collects macOS code signing credentials and uploads them as GitHub secrets
# for the Cursor Odometer release workflow.
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth status)
#   - A "Developer ID Application" certificate in your login keychain
#   - An app-specific password from https://account.apple.com
#     (Sign-In and Security > App-Specific Passwords)
#
# Usage:
#   ./Scripts/setup-signing-secrets.sh
#

set -euo pipefail

REPO="Shmoopi/cursor-odometer"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# ── Helpers ──────────────────────────────────────────────────────────────────

bold()  { printf "\033[1m%s\033[0m" "$1"; }
green() { printf "\033[32m%s\033[0m" "$1"; }
red()   { printf "\033[31m%s\033[0m" "$1"; }

prompt_secret() {
    local var_name="$1"
    local prompt_msg="$2"
    local value=""
    printf "\n%s\n> " "$prompt_msg"
    read -rs value
    printf "\n"
    if [[ -z "$value" ]]; then
        echo "$(red "Error:") Value cannot be empty."
        exit 1
    fi
    eval "$var_name=\$value"
}

prompt_visible() {
    local var_name="$1"
    local prompt_msg="$2"
    local value=""
    printf "\n%s\n> " "$prompt_msg"
    read -r value
    if [[ -z "$value" ]]; then
        echo "$(red "Error:") Value cannot be empty."
        exit 1
    fi
    eval "$var_name=\$value"
}

# ── Preflight Checks ────────────────────────────────────────────────────────

echo ""
echo "$(bold "Cursor Odometer Code Signing Secrets Setup")"
echo "============================================"
echo ""

# Check gh CLI
if ! command -v gh &>/dev/null; then
    echo "$(red "Error:") gh CLI not found. Install with: brew install gh"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "$(red "Error:") gh CLI not authenticated. Run: gh auth login"
    exit 1
fi

echo "$(green "✓") gh CLI authenticated"

# Confirm target repo exists
if ! gh repo view "$REPO" &>/dev/null; then
    echo "$(red "Error:") Repo $REPO not found or not accessible."
    echo "Create it first with: gh repo create $REPO --public"
    exit 1
fi

echo "$(green "✓") Target repo: $REPO"

# Check for Developer ID Application certificates
echo ""
echo "$(bold "Available signing identities:")"
echo ""
security find-identity -v -p codesigning | grep "Developer ID Application" || {
    echo ""
    echo "$(red "Error:") No 'Developer ID Application' certificate found in keychain."
    echo "Create one at: https://developer.apple.com/account/resources/certificates/list"
    exit 1
}

# ── Step 1: Select Signing Identity ──────────────────────────────────────────

echo ""
IDENTITIES=$(security find-identity -v -p codesigning | grep "Developer ID Application")
IDENTITY_COUNT=$(echo "$IDENTITIES" | wc -l | tr -d ' ')

if [[ "$IDENTITY_COUNT" -eq 1 ]]; then
    CODE_SIGN_IDENTITY=$(echo "$IDENTITIES" | sed 's/.*"\(.*\)".*/\1/')
    echo "Using identity: $(bold "$CODE_SIGN_IDENTITY")"
else
    echo "Multiple identities found. Please enter the full identity string"
    echo "(e.g., Developer ID Application: XXX-XXX (XXXXXXXXXX))"
    prompt_visible CODE_SIGN_IDENTITY "Signing identity:"
fi

# Extract Team ID from the identity string (the 10-char code in parentheses)
DEVELOPMENT_TEAM=$(echo "$CODE_SIGN_IDENTITY" | grep -oE '\([A-Z0-9]{10}\)' | tr -d '()')
if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    prompt_visible DEVELOPMENT_TEAM "Could not extract Team ID. Enter your 10-character Apple Team ID:"
else
    echo "Extracted Team ID: $(bold "$DEVELOPMENT_TEAM")"
fi

# ── Step 2: Export Certificate as .p12 ───────────────────────────────────────

echo ""
echo "$(bold "Exporting certificate...")"
echo ""

prompt_secret P12_PASSWORD "Enter a password to protect the .p12 export (new password, you choose it):"

P12_PATH="$TEMP_DIR/certificate.p12"

# Find the SHA-1 hash matching our identity
CERT_HASH=$(security find-identity -v -p codesigning | grep "$CODE_SIGN_IDENTITY" | head -1 | awk '{print $2}')

if [[ -z "$CERT_HASH" ]]; then
    echo "$(red "Error:") Could not find certificate hash."
    exit 1
fi

# Export the identity (cert + private key) as PKCS12
security export -k ~/Library/Keychains/login.keychain-db \
    -t identities -f pkcs12 \
    -o "$P12_PATH" \
    -P "$P12_PASSWORD" 2>/dev/null || {
    echo ""
    echo "$(red "Automatic export failed.") Please export manually:"
    echo "  1. Open Keychain Access"
    echo "  2. Right-click '$CODE_SIGN_IDENTITY' > Export"
    echo "  3. Save as .p12 to: $P12_PATH"
    echo "  4. Use the password you just entered"
    echo ""
    read -rp "Press Enter when done..."
    if [[ ! -f "$P12_PATH" ]]; then
        echo "$(red "Error:") File not found at $P12_PATH"
        exit 1
    fi
}

echo "$(green "✓") Certificate exported"

# ── Step 3: Base64 Encode ────────────────────────────────────────────────────

BUILD_CERTIFICATE_BASE64=$(base64 -i "$P12_PATH" | tr -d '\n')
echo "$(green "✓") Certificate base64-encoded (${#BUILD_CERTIFICATE_BASE64} chars)"

# ── Step 4: Generate Keychain Password ───────────────────────────────────────

KEYCHAIN_PASSWORD=$(openssl rand -base64 24)
echo "$(green "✓") Generated CI keychain password"

# ── Step 5: Collect Apple ID Credentials ─────────────────────────────────────

echo ""
prompt_visible APPLE_ID "Enter your Apple ID email (used for notarization):"
prompt_secret APPLE_ID_PASSWORD "Enter your app-specific password (from https://account.apple.com > App-Specific Passwords):"

# ── Step 6: Confirm and Upload ───────────────────────────────────────────────

echo ""
echo "$(bold "Summary of secrets to upload to $REPO:")"
echo ""
echo "  BUILD_CERTIFICATE_BASE64  ${#BUILD_CERTIFICATE_BASE64} chars (base64)"
echo "  P12_PASSWORD              ********"
echo "  KEYCHAIN_PASSWORD         (auto-generated)"
echo "  CODE_SIGN_IDENTITY        $CODE_SIGN_IDENTITY"
echo "  DEVELOPMENT_TEAM          $DEVELOPMENT_TEAM"
echo "  APPLE_ID                  $APPLE_ID"
echo "  APPLE_ID_PASSWORD         ********"
echo ""
read -rp "Upload these secrets to GitHub? [y/N] " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Uploading secrets..."

echo -n "$BUILD_CERTIFICATE_BASE64" | gh secret set BUILD_CERTIFICATE_BASE64 --repo "$REPO"
echo "  $(green "✓") BUILD_CERTIFICATE_BASE64"

gh secret set P12_PASSWORD --repo "$REPO" --body "$P12_PASSWORD"
echo "  $(green "✓") P12_PASSWORD"

gh secret set KEYCHAIN_PASSWORD --repo "$REPO" --body "$KEYCHAIN_PASSWORD"
echo "  $(green "✓") KEYCHAIN_PASSWORD"

gh secret set CODE_SIGN_IDENTITY --repo "$REPO" --body "$CODE_SIGN_IDENTITY"
echo "  $(green "✓") CODE_SIGN_IDENTITY"

gh secret set DEVELOPMENT_TEAM --repo "$REPO" --body "$DEVELOPMENT_TEAM"
echo "  $(green "✓") DEVELOPMENT_TEAM"

gh secret set APPLE_ID --repo "$REPO" --body "$APPLE_ID"
echo "  $(green "✓") APPLE_ID"

gh secret set APPLE_ID_PASSWORD --repo "$REPO" --body "$APPLE_ID_PASSWORD"
echo "  $(green "✓") APPLE_ID_PASSWORD"

# ── Step 7: Verify ───────────────────────────────────────────────────────────

echo ""
echo "$(bold "Verifying secrets...")"
echo ""
gh secret list --repo "$REPO"

echo ""
echo "$(green "✓") All done! Push a tag (git tag v1.0.1 && git push origin v1.0.1) to trigger a release build."
