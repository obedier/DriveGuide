#!/usr/bin/env python3
"""
App Store Connect API JWT Token Generator for Roamly
Generates a signed JWT token for authenticating with the App Store Connect API.

Usage:
    python3 generate_jwt.py

Requirements:
    pip3 install PyJWT cryptography --break-system-packages

IMPORTANT: The ISSUER_ID below is NOT the Team ID.
Get your Issuer ID from:
  App Store Connect > Users and Access > Integrations > App Store Connect API
  It's a UUID displayed at the top of that page (e.g. "57246542-96fe-1a63-e053-0824d011072a")
"""

import jwt
import time
import sys
import os

# ============================================================
# CONFIGURATION - UPDATE ISSUER_ID before running
# ============================================================
KEY_ID = "V42G2XP7LB"
ISSUER_ID = "REPLACE_WITH_ISSUER_ID_UUID"   # <-- GET FROM App Store Connect UI
KEY_FILE = os.path.expanduser("~/.private_keys/AuthKey_V42G2XP7LB.p8")
TOKEN_EXPIRY_SECONDS = 1200  # 20 minutes (Apple's maximum)
# ============================================================


def generate_token() -> str:
    if not os.path.exists(KEY_FILE):
        print(f"ERROR: Key file not found at {KEY_FILE}", file=sys.stderr)
        sys.exit(1)

    if ISSUER_ID == "REPLACE_WITH_ISSUER_ID_UUID":
        print("ERROR: You must set ISSUER_ID to your actual Issuer ID UUID.", file=sys.stderr)
        print("Find it at: App Store Connect > Users and Access > Integrations > App Store Connect API", file=sys.stderr)
        sys.exit(1)

    with open(KEY_FILE, "r") as f:
        private_key = f.read()

    now = int(time.time())
    payload = {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + TOKEN_EXPIRY_SECONDS,
        "aud": "appstoreconnect-v1",
    }
    headers = {
        "alg": "ES256",
        "kid": KEY_ID,
        "typ": "JWT",
    }

    token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
    return token


if __name__ == "__main__":
    token = generate_token()
    print(token)
