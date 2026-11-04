#!/usr/bin/env python3
# skyHAB Project <src@lispm.net>
# Copyright (c) 2026 I. Finder
# SPDX-License-Identifier: MIT

"""Create, list, and revoke skyHAB client tokens in a mode-0600 auth file."""
import argparse, hashlib, json, os, secrets
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("file", type=Path)
sub = parser.add_subparsers(dest="command", required=True)
create = sub.add_parser("create"); create.add_argument("client"); create.add_argument("--role", choices=("viewer","operator","admin"), default="viewer"); create.add_argument("--output", type=Path)
sub.add_parser("list")
revoke = sub.add_parser("revoke"); revoke.add_argument("client")
args = parser.parse_args()
data = json.loads(args.file.read_text()) if args.file.exists() else {"version": 1, "clients": []}
if args.command == "create":
    if any(c["id"] == args.client and not c.get("revoked", False) for c in data["clients"]): raise SystemExit("active client already exists")
    token = secrets.token_urlsafe(32)
    data["clients"].append({"id": args.client, "role": args.role, "token_sha256": hashlib.sha256(token.encode()).hexdigest(), "revoked": False})
    args.file.parent.mkdir(parents=True, exist_ok=True); args.file.write_text(json.dumps(data, indent=2) + "\n"); os.chmod(args.file, 0o600)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(token + "\n")
        os.chmod(args.output, 0o600)
    else:
        print(token)
elif args.command == "revoke":
    found = False
    for client in data["clients"]:
        if client["id"] == args.client and not client.get("revoked", False): client["revoked"] = True; found = True
    if not found: raise SystemExit("active client not found")
    args.file.write_text(json.dumps(data, indent=2) + "\n"); os.chmod(args.file, 0o600)
else:
    for client in data["clients"]: print(f"{client['id']}\t{client['role']}\t{'revoked' if client.get('revoked') else 'active'}")
