#!/usr/bin/env python3
"""
Roamly - App Store Connect Subscription Setup Script
Creates a subscription group with 3 tiers via the App Store Connect API.

PREREQUISITES:
1. pip3 install PyJWT cryptography --break-system-packages
2. Set ISSUER_ID below (UUID from App Store Connect > Users and Access > Integrations > App Store Connect API)
3. The app must already exist in App Store Connect (create at appstoreconnect.apple.com if not)
4. The API key must have App Manager or Admin role

WHAT THIS SCRIPT DOES:
  Step 1: Fetch the App ID for com.privatetourai.app
  Step 2: Create a subscription group called "Roamly Pro"
  Step 3: Create 3 auto-renewable subscriptions:
    - Roamly Pro Weekly  ($7.99/week)
    - Roamly Pro Monthly ($14.99/month)
    - Roamly Pro Annual  ($79.99/year)
  Step 4: Add USD pricing to each subscription
  Step 5: Print product IDs to use in your Swift code

Usage:
    python3 create_subscriptions.py
"""

import jwt
import time
import json
import sys
import os
import urllib.request
import urllib.error

# ============================================================
# CONFIGURATION
# ============================================================
KEY_ID = "V42G2XP7LB"
ISSUER_ID = "REPLACE_WITH_ISSUER_ID_UUID"   # <-- GET FROM App Store Connect UI
KEY_FILE = os.path.expanduser("~/.private_keys/AuthKey_V42G2XP7LB.p8")
BUNDLE_ID = "com.privatetourai.app"
APP_NAME = "Roamly"

SUBSCRIPTION_GROUP_NAME = "Roamly Pro"

# Subscription tiers - product IDs follow Apple convention: bundle.category.period
SUBSCRIPTIONS = [
    {
        "productId": "com.privatetourai.app.pro.weekly",
        "name": "Roamly Pro Weekly",
        "reviewNote": "Weekly subscription for full access to Roamly Pro features including unlimited AI-narrated tours.",
        "familySharable": False,
        "subscriptionPeriod": "ONE_WEEK",
        "price_usd": "7.99",
        "level": 1,  # Lower = higher priority in group (weekly = most expensive per unit)
    },
    {
        "productId": "com.privatetourai.app.pro.monthly",
        "name": "Roamly Pro Monthly",
        "reviewNote": "Monthly subscription for full access to Roamly Pro features including unlimited AI-narrated tours.",
        "familySharable": False,
        "subscriptionPeriod": "ONE_MONTH",
        "price_usd": "14.99",
        "level": 2,
    },
    {
        "productId": "com.privatetourai.app.pro.annual",
        "name": "Roamly Pro Annual",
        "reviewNote": "Annual subscription for full access to Roamly Pro features including unlimited AI-narrated tours.",
        "familySharable": False,
        "subscriptionPeriod": "ONE_YEAR",
        "price_usd": "79.99",
        "level": 3,
    },
]

BASE_URL = "https://api.appstoreconnect.apple.com/v1"
# ============================================================


def generate_token() -> str:
    if ISSUER_ID == "REPLACE_WITH_ISSUER_ID_UUID":
        print("ERROR: Set ISSUER_ID to your actual Issuer ID UUID.", file=sys.stderr)
        print("Find it at: App Store Connect > Users and Access > Integrations > App Store Connect API", file=sys.stderr)
        sys.exit(1)
    with open(KEY_FILE, "r") as f:
        private_key = f.read()
    now = int(time.time())
    payload = {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    headers = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def api_request(token: str, method: str, path: str, body: dict = None) -> dict:
    url = f"{BASE_URL}{path}"
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"\nHTTP {e.code} for {method} {path}")
        print(f"Response: {error_body}")
        raise


def get_app_id(token: str) -> str:
    print(f"Fetching app ID for {BUNDLE_ID}...")
    data = api_request(token, "GET", f"/apps?filter[bundleId]={BUNDLE_ID}")
    apps = data.get("data", [])
    if not apps:
        print(f"ERROR: No app found with bundle ID '{BUNDLE_ID}'.")
        print("Create your app first at: https://appstoreconnect.apple.com/apps")
        sys.exit(1)
    app_id = apps[0]["id"]
    app_name = apps[0]["attributes"]["name"]
    print(f"  Found: '{app_name}' (ID: {app_id})")
    return app_id


def create_subscription_group(token: str, app_id: str) -> str:
    print(f"\nCreating subscription group '{SUBSCRIPTION_GROUP_NAME}'...")
    body = {
        "data": {
            "type": "subscriptionGroups",
            "attributes": {
                "referenceName": SUBSCRIPTION_GROUP_NAME,
            },
            "relationships": {
                "app": {
                    "data": {"type": "apps", "id": app_id}
                }
            },
        }
    }
    data = api_request(token, "POST", "/subscriptionGroups", body)
    group_id = data["data"]["id"]
    print(f"  Created subscription group ID: {group_id}")
    return group_id


def create_subscription(token: str, group_id: str, sub: dict) -> str:
    print(f"\nCreating subscription '{sub['name']}' ({sub['productId']})...")
    body = {
        "data": {
            "type": "subscriptions",
            "attributes": {
                "productId": sub["productId"],
                "name": sub["name"],
                "reviewNote": sub["reviewNote"],
                "familySharable": sub["familySharable"],
                "subscriptionPeriod": sub["subscriptionPeriod"],
                "groupLevel": sub["level"],
            },
            "relationships": {
                "group": {
                    "data": {"type": "subscriptionGroups", "id": group_id}
                }
            },
        }
    }
    data = api_request(token, "POST", "/subscriptions", body)
    sub_id = data["data"]["id"]
    print(f"  Created subscription ID: {sub_id}")
    return sub_id


def add_localization(token: str, sub_id: str, sub: dict) -> None:
    """Add English localization (name shown to users in the App Store)."""
    print(f"  Adding en-US localization for '{sub['name']}'...")
    body = {
        "data": {
            "type": "subscriptionLocalizations",
            "attributes": {
                "locale": "en-US",
                "name": sub["name"],
                "description": sub["reviewNote"],
            },
            "relationships": {
                "subscription": {
                    "data": {"type": "subscriptions", "id": sub_id}
                }
            },
        }
    }
    api_request(token, "POST", "/subscriptionLocalizations", body)
    print(f"  Localization added.")


def add_price(token: str, sub_id: str, price_usd: str) -> None:
    """
    Set USD pricing for a subscription.

    NOTE: Apple's pricing API uses price point IDs, not raw dollar amounts.
    The correct approach is:
      1. GET /v1/subscriptions/{id}/pricePoints?filter[territory]=USA to list available price points
      2. Find the price point matching your target price
      3. POST /v1/subscriptionPrices to create the price

    Apple rounds to preset tiers (e.g. $7.99, $14.99, $79.99 are standard tiers).
    """
    print(f"  Fetching USD price points for ${price_usd}...")

    # Get available price points for USA territory
    price_points_data = api_request(
        token, "GET",
        f"/subscriptions/{sub_id}/pricePoints?filter[territory]=USA&limit=200"
    )

    price_points = price_points_data.get("data", [])
    target_price_cents = int(float(price_usd) * 100)

    matching_point = None
    for pp in price_points:
        attrs = pp.get("attributes", {})
        customer_price = attrs.get("customerPrice", "0")
        point_cents = int(float(customer_price) * 100)
        if point_cents == target_price_cents:
            matching_point = pp
            break

    if not matching_point:
        print(f"  WARNING: No exact price point found for ${price_usd}. Available nearby points:")
        for pp in price_points[:10]:
            print(f"    - ${pp['attributes'].get('customerPrice', '?')}")
        return

    price_point_id = matching_point["id"]
    print(f"  Found price point ID: {price_point_id} (${price_usd})")

    body = {
        "data": {
            "type": "subscriptionPrices",
            "attributes": {
                "preserveCurrentPrice": False,
                "startDate": None,  # Effective immediately
            },
            "relationships": {
                "subscription": {
                    "data": {"type": "subscriptions", "id": sub_id}
                },
                "subscriptionPricePoint": {
                    "data": {"type": "subscriptionPricePoints", "id": price_point_id}
                },
            },
        }
    }
    api_request(token, "POST", "/subscriptionPrices", body)
    print(f"  Price set to ${price_usd} USD.")


def main():
    print("=" * 60)
    print("Roamly - App Store Connect Subscription Setup")
    print("=" * 60)

    token = generate_token()
    print("JWT token generated.")

    app_id = get_app_id(token)
    group_id = create_subscription_group(token, app_id)

    created = []
    for sub in SUBSCRIPTIONS:
        sub_id = create_subscription(token, group_id, sub)
        add_localization(token, sub_id, sub)
        add_price(token, sub_id, sub["price_usd"])
        created.append({"name": sub["name"], "productId": sub["productId"], "id": sub_id})

    print("\n" + "=" * 60)
    print("SUCCESS - Subscriptions Created:")
    print("=" * 60)
    for c in created:
        print(f"  {c['name']}")
        print(f"    Product ID : {c['productId']}")
        print(f"    API ID     : {c['id']}")

    print("\nNEXT STEPS:")
    print("  1. Go to App Store Connect and review the subscription group")
    print("  2. Submit each subscription for review along with your app")
    print("  3. Use these product IDs in your Swift/RevenueCat code:")
    for sub in SUBSCRIPTIONS:
        print(f"     \"{sub['productId']}\"")


if __name__ == "__main__":
    main()
