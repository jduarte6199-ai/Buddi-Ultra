#!/bin/bash
#
# One-time setup: create a stable local code-signing certificate for Buddi.
#
# Why: ad-hoc signatures change on every rebuild, so macOS treats each build
# as a different app and re-asks for Keychain permission (the password prompt
# for "Claude Code-credentials") after every update. Signing every build with
# ONE local certificate keeps the identity stable, so "Always Allow" sticks
# forever. install.sh picks this identity up automatically once it exists.
#
# macOS will ask for your login password once or twice during this script
# (trusting the certificate and unlocking the key for codesign). That is the
# last time; after this, updates never prompt again.
#
set -euo pipefail

NAME="Buddi Local Signing"
KEYCHAIN=~/Library/Keychains/login.keychain-db

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "Identity '$NAME' already exists. Nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Creating certificate '$NAME'..."
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null

# -legacy first: OpenSSL 3 default ciphers are unreadable by `security import`.
openssl pkcs12 -export -legacy -out "$TMP/id.p12" -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" -passout pass:buddi-setup 2>/dev/null \
    || openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" \
        -in "$TMP/cert.pem" -passout pass:buddi-setup

echo "Importing into your login keychain..."
security import "$TMP/id.p12" -k "$KEYCHAIN" -P buddi-setup -T /usr/bin/codesign

echo "Trusting it for code signing (macOS asks for your password here)..."
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Allowing codesign to use the key without per-build prompts"
echo "(enter your login password if asked)..."
security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN" >/dev/null

echo
echo "Done. Run ./install.sh now; the next app launch will ask for Keychain"
echo "access ONE last time. Click 'Always Allow' and it never asks again."
