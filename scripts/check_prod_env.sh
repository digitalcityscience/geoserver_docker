#!/bin/bash
set -e

echo "🔎 Checking PRODUCTION environment safety..."

# 1) PROD_MODE verification
if [ "$PROD_MODE" != "true" ]; then
  echo "❌ .env.prod is active BUT PROD_MODE=true is NOT set"
  echo "👉 Explicitly set PROD_MODE=true to confirm production intent"
  exit 1
fi

# 2) Weak password list
WEAK_PASSWORDS="geoserver admin password 1234 123456 postgres postgis mobilitydb"

# 3) Scan all env vars containing PASSWORD
while IFS='=' read -r name value; do
  if [[ "$name" == *PASSWORD* ]]; then
    for weak in $WEAK_PASSWORDS; do
      if [ "$value" = "$weak" ]; then
        echo "❌ Weak password detected!"
        echo "   ENV VAR : $name"
        echo "   VALUE   : $weak"
        echo "👉 Refusing to start in production"
        exit 1
      fi
    done
  fi
done < <(env)

echo "✅ Production environment validated (all passwords look sane)"