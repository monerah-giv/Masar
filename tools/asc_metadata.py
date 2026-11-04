#!/usr/bin/env python3
"""Push the App Store text in ios/AppStore/metadata.json to App Store Connect.

    python3 tools/asc_metadata.py --dry-run          # print what would be sent, no network
    python3 tools/asc_metadata.py                    # needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8

What it sets, for each language the store accepts:
  - App Information: name, subtitle, privacy policy URL, and the two categories
  - The version being prepared: description, keywords, promotional text, support and marketing URLs,
    and its version number (MARKETING_VERSION in ios/project.yml)

Languages the store does not offer for the account are reported and skipped; the run goes on.
The app record must already exist in App Store Connect with the bundle ID below.
"""
import argparse
import json
import os
import pathlib
import re
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "app.masarmetro.ios"
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170, "description": 4000}
CATEGORIES = {"Navigation": "NAVIGATION", "Travel": "TRAVEL"}
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}


def load():
    meta = json.loads((ROOT / "ios/AppStore/metadata.json").read_text(encoding="utf-8"))
    spec = (ROOT / "ios/project.yml").read_text(encoding="utf-8")
    version = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', spec).group(1)
    return meta, version


def plan(meta, version):
    """Build every payload from metadata.json. Pure, so it is unit-tested without network."""
    urls = meta["urls"]
    info, ver, problems = {}, {}, []
    for locale, t in meta["localizations"].items():
        for field, limit in LIMITS.items():
            if len(t.get(field, "")) > limit:
                problems.append(f"{locale}.{field} is {len(t[field])} characters, limit {limit}")
        info[locale] = {"name": t["name"], "subtitle": t["subtitle"], "privacyPolicyUrl": urls["privacyPolicy"]}
        ver[locale] = {
            "description": t["description"],
            "keywords": t["keywords"],
            "promotionalText": t["promotionalText"],
            "supportUrl": urls["support"],
            "marketingUrl": urls["marketing"],
        }
    cats = {"primaryCategory": CATEGORIES[meta["primaryCategory"]],
            "secondaryCategory": CATEGORIES[meta["secondaryCategory"]]}
    return {"version": version, "info": info, "versionText": ver, "categories": cats, "problems": problems}


class Client:
    def __init__(self):
        import jwt        # PyJWT, with cryptography for ES256
        import requests
        self.requests = requests
        key_id, issuer = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"]
        key = os.environ["ASC_KEY_P8"]
        if "BEGIN PRIVATE KEY" not in key:          # accept the .p8 file pasted as is, or base64 of it
            import base64
            key = base64.b64decode(key).decode()
        now = int(time.time())
        token = jwt.encode({"iss": issuer, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                           key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})
        self.h = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    def call(self, method, path, body=None, ok=(200, 201, 204)):
        r = self.requests.request(method, API + path, headers=self.h, json=body, timeout=60)
        if r.status_code not in ok:
            detail = "; ".join(e.get("detail") or e.get("title", "") for e in r.json().get("errors", [])) if r.content else ""
            raise RuntimeError(f"{method} {path} -> {r.status_code}: {detail}")
        return r.json() if r.content else {}


def push(p, dry):
    if dry:
        print(json.dumps(p, ensure_ascii=False, indent=1))
        return 0
    c = Client()
    apps = c.call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        sys.exit(f"No app with bundle ID {BUNDLE_ID} in App Store Connect. Create the app record first (docs/APPSTORE.md).")
    app = apps[0]["id"]
    skipped = []

    # App Information (name, subtitle, privacy URL) lives on the editable appInfo.
    infos = c.call("GET", f"/apps/{app}/appInfos")["data"]
    info = next((i for i in infos if (i["attributes"].get("state") or i["attributes"].get("appStoreState"))
                 not in ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE")), infos[0])
    c.call("PATCH", f"/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        k: {"data": {"type": "appCategories", "id": v}} for k, v in p["categories"].items()}}})
    have = {l["attributes"]["locale"]: l["id"] for l in
            c.call("GET", f"/appInfos/{info['id']}/appInfoLocalizations?limit=50")["data"]}
    for locale, attrs in p["info"].items():
        try:
            if locale in have:
                c.call("PATCH", f"/appInfoLocalizations/{have[locale]}",
                       {"data": {"type": "appInfoLocalizations", "id": have[locale], "attributes": attrs}})
            else:
                c.call("POST", "/appInfoLocalizations", {"data": {"type": "appInfoLocalizations",
                       "attributes": {"locale": locale, **attrs},
                       "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
            print(f"app info  {locale}: ok")
        except RuntimeError as e:
            skipped.append(f"app info {locale}: {e}")

    # The version being prepared: create it if the app has none, then set its number and text.
    vers = c.call("GET", f"/apps/{app}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
    state = lambda v: v["attributes"].get("appVersionState") or v["attributes"].get("appStoreState")
    ver = next((v for v in vers if state(v) in EDITABLE), None)
    if ver is None:
        ver = c.call("POST", "/appStoreVersions", {"data": {"type": "appStoreVersions",
                     "attributes": {"platform": "IOS", "versionString": p["version"]},
                     "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
    elif ver["attributes"]["versionString"] != p["version"]:
        c.call("PATCH", f"/appStoreVersions/{ver['id']}", {"data": {"type": "appStoreVersions", "id": ver["id"],
               "attributes": {"versionString": p["version"]}}})
    have = {l["attributes"]["locale"]: l["id"] for l in
            c.call("GET", f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations?limit=50")["data"]}
    for locale, attrs in p["versionText"].items():
        try:
            if locale in have:
                c.call("PATCH", f"/appStoreVersionLocalizations/{have[locale]}",
                       {"data": {"type": "appStoreVersionLocalizations", "id": have[locale], "attributes": attrs}})
            else:
                c.call("POST", "/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations",
                       "attributes": {"locale": locale, **attrs},
                       "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
            print(f"version   {locale}: ok")
        except RuntimeError as e:
            skipped.append(f"version {locale}: {e}")

    for s in skipped:
        print(f"::warning::skipped {s}")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="print the payloads; no network")
    args = ap.parse_args()
    meta, version = load()
    p = plan(meta, version)
    if p["problems"]:
        sys.exit("Fix ios/AppStore/metadata.json first:\n  " + "\n  ".join(p["problems"]))
    sys.exit(push(p, args.dry_run))


if __name__ == "__main__":
    main()
