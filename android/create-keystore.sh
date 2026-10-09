#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KEYSTORE="$ROOT/app/upload-keystore.jks"
PROPS="$ROOT/key.properties"

if [[ -f "$KEYSTORE" || -f "$PROPS" ]]; then
  echo "A keystore or key.properties already exists. Refusing to overwrite."
  echo "Back up those files before creating a new key."
  exit 1
fi

PASS="$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)"
keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=Sreamart, OU=Mobile, O=Sreamart, L=Marib, ST=Marib, C=YE"

cat > "$PROPS" <<EOF
storePassword=$PASS
keyPassword=$PASS
keyAlias=upload
storeFile=app/upload-keystore.jks
EOF

echo "Created:"
echo "  $KEYSTORE"
echo "  $PROPS"
echo "Keep both files offline. Losing them means you cannot update the Play Store listing."
