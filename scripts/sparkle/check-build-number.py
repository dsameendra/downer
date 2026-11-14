#!/usr/bin/env python3
"""Usage: check-build-number.py <published appcast.xml> <new CFBundleVersion>

Exits 0 when the new build number is greater than every sparkle:version in the appcast (element or
attribute form, single or double quotes), 1 when it is not, 2 when the appcast cannot be understood
(an <item> without any parsable sparkle:version, or a non-numeric version). Sparkle never downgrades
and compares these numbers, so a release whose number is not higher would never be offered to anyone.
"""
import re
import sys


def fail(msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(2)


def key(v):
    parts = re.split(r"[.\-]", v.strip())
    if not v.strip() or not all(p.isdigit() for p in parts):
        fail("non-numeric build number %r (in the appcast or the new build)" % v)
    return [int(p) for p in parts]


text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
new = sys.argv[2]
# unwrap CDATA so versions inside it are seen too
flat = re.sub(r"<!\[CDATA\[(.*?)\]\]>", r"\1", text, flags=re.S)
found = re.findall(r"<sparkle:version>\s*([^<]*?)\s*</sparkle:version>", flat)
found += [a or b for a, b in re.findall(r"""sparkle:version\s*=\s*(?:"([^"]*)"|'([^']*)')""", flat)]

if re.search(r"<item[\s>]", flat) and not found:
    fail("the appcast has <item> entries but no sparkle:version could be read from it; refusing to guess.")

newk = key(new)
bad = [v for v in found if newk <= key(v)]
if bad:
    print("build %s is not greater than published build(s): %s" % (new, ", ".join(bad)), file=sys.stderr)
    sys.exit(1)
print("published builds: %s" % (", ".join(found) or "none"))
