#!/usr/bin/env bash
# Fails the commit/recording if a real identifier leaked into the repo.
# Run before every phase is marked done — see PRODUCTION-GUIDE.md §2 and §6.
#
# Usage: ./scripts/redact-check.sh [path]
#   path defaults to the whole repo.

set -euo pipefail
TARGET="${1:-.}"

# 12-digit AWS account ID pattern, excluding the literal placeholder token
PATTERN='\b[0-9]{12}\b'
PLACEHOLDER='\$\{ACCOUNT_ID\}'

echo "Scanning ${TARGET} for un-redacted account IDs..."
MATCHES=$(grep -rEn "$PATTERN" "$TARGET" \
  --include='*.md' --include='*.sh' --include='*.yaml' --include='*.yml' \
  --include='*.tf' --include='*.txt' \
  | grep -Ev "$PLACEHOLDER" || true)

if [ -n "$MATCHES" ]; then
  echo "FAIL: possible real account ID or identifier found:"
  echo "$MATCHES"
  exit 1
fi

echo "OK — no un-redacted 12-digit identifiers found."

# Extend this list as other identifier patterns are learned during the
# engagement (VPC IDs, subnet IDs, real cluster ARNs, etc.)
