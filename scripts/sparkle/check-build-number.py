#!/usr/bin/env python3
"""Usage: check-build-number.py <published appcast.xml> <new CFBundleVersion>

Exits 0 when the new build number is greater than every sparkle:version in the appcast (element or
attribute form), 1 when it is not. Sparkle never downgrades and compares these numbers, so a release
whose number is not higher would never be offered to anyone.
"""
import re
import sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
new = sys.argv[2]
found = re.findall(r"<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>", text)
found += re.findall(r'sparkle:version="([^"]+)"', text)


def key(v):
    return [int(p) if p.isdigit() else 0 for p in re.split(r"[.\-]", v)]


bad = [v for v in found if key(new) <= key(v)]
if bad:
    print("build %s is not greater than published build(s): %s" % (new, ", ".join(bad)), file=sys.stderr)
    sys.exit(1)
print("published builds: %s" % (", ".join(found) or "none"))
