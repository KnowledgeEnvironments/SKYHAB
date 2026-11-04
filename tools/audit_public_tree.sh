#!/bin/sh
# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

failed=0
check_content() {
  label=$1
  pattern=$2
  if git grep -nE "$pattern" -- . ':(exclude)tools/audit_public_tree.sh'; then
    echo "public-tree audit: $label found" >&2
    failed=1
  fi
}

check_content "private IPv4 address" '(^|[^0-9])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)'
check_content "machine-local absolute path" "/(Users|Volumes|home)/[^[:space:]\"']+"
check_content "Apple signing team" 'DEVELOPMENT_TEAM[[:space:]]*='
check_content "private key material" 'BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE[[:space:]]KEY'

if git grep -nE 'value\("ssh_user",[[:space:]]*"[^"]+"\)' -- src include; then
  echo "public-tree audit: hard-coded SSH username default found" >&2
  failed=1
fi

if git ls-files | grep -E '(^|/)(inventory/inventory\.json|ONBOARDING\.md|\.env([^/]*)?|[^/]*\.token|[^/]*\.sqlite3(-shm|-wal)?)$'; then
  echo "public-tree audit: private runtime file is tracked" >&2
  failed=1
fi

[ "$failed" -eq 0 ] || exit 1
python3 tests/test_inventory.py .
python3 tests/test_presentation.py .
echo "public-tree privacy audit passed"
