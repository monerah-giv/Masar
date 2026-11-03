#!/usr/bin/env python3
"""Move the site and business email to another domain in one step.

    python3 tools/set_domain.py masar-metro.com

Reads the current domain from data/app.json (siteUrl), replaces it in every tracked text file
that names it (data, iOS links, store metadata, docs, DNS zone), renames docs/<old>.zone,
then rebuilds so the sitemap, canonical links, QR stickers and bundled ad feed follow.
"""
import json
import pathlib
import re
import subprocess
import sys
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKIP = ("dist/", ".git/")
TEXT = {".json", ".md", ".swift", ".yml", ".yaml", ".zone", ".html", ".py", ".sh", ".txt"}


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r"[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9-]+)+", sys.argv[1].lower()):
        sys.exit("usage: python3 tools/set_domain.py <domain>   e.g. masarmetro.com")
    new = sys.argv[1].lower()
    app = json.loads((ROOT / "data/app.json").read_text(encoding="utf-8"))
    old = urlparse(app["siteUrl"]).hostname or ""
    if old.endswith("github.io"):
        sys.exit(f"siteUrl is still {app['siteUrl']}: set data/app.json siteUrl to https://<domain>/ once by hand")
    if old == new:
        print(f"already {new}")
        return
    pat = re.compile(r"(?<![\w-])" + re.escape(old) + r"(?![\w-])")
    files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
    changed = []
    for rel in files:
        p = ROOT / rel
        if rel.startswith(SKIP) or p.suffix not in TEXT or rel == "tools/set_domain.py" or not p.is_file():
            continue
        s = p.read_text(encoding="utf-8")
        t = pat.sub(new, s)
        if t != s:
            p.write_text(t, encoding="utf-8")
            changed.append(rel)
    zone = ROOT / f"docs/{old}.zone"
    if zone.exists():
        subprocess.run(["git", "mv", str(zone), str(ROOT / f"docs/{new}.zone")], cwd=ROOT, check=True)
        changed.append(f"docs/{old}.zone -> docs/{new}.zone")
    print(f"{old} -> {new}")
    for c in changed:
        print("  " + c)
    subprocess.run([sys.executable, str(ROOT / "tools/build.py")], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
