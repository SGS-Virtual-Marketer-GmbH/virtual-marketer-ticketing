#!/usr/bin/env python3
"""Rebrand the product name in the shipped translations.

    python3 contrib/branding/rebrand_strings.py [--check]

Like contrib/branding/generate.py, this is a generator rather than a patch:
re-run it after merging upstream and the rebranding is reapplied to whatever
the new strings happen to be. Editing the .po files by hand would guarantee a
conflict on every merge.

Why the .po files and not the source strings
--------------------------------------------
Every user-facing string in the application goes through gettext. The English
source strings live scattered across .eco templates, .vue components, Ruby
models and setting seeds -- rewriting those would be a patch across hundreds of
upstream files. The translation catalogue is one file per language, and it is
what this instance actually renders: DentaTec runs in German.

Consequence worth knowing: switching a user's language to English shows
upstream's product name again, because en-us is the source language and has no
catalogue to rewrite.

What is deliberately NOT rebranded
----------------------------------
KEEP_MARKERS below. Three kinds:

  * Legal identity -- the Zammad Foundation and Zammad GmbH are real
    organisations. Renaming them would be misattribution, and the AGPL notice
    requires the upstream project stay identifiable.
  * Upstream's own services -- the translation portal, the BETA-UI research
    programme. These strings ask the reader to contribute to *Zammad*; pointing
    them at a product name that project has never heard of helps nobody.
  * Literal technical tokens -- the `X-Zammad-*` mail headers, the
    `zammad-attachment` array key, the `/opt/zammad` filesystem path and the
    `ZammadForm` JavaScript widget. These are identifiers, not prose; renaming
    them in the UI would document something that does not exist.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PRODUCT = "Virtual Marketer Ticketing"
PRODUCT_SHORT = "Virtual Marketer"

# Catalogues to rewrite. Only the languages this deployment offers -- rewriting
# all 40+ would be churn nobody reads.
CATALOGUES = ["i18n/zammad.de-de.po"]

# A msgid containing any of these keeps upstream's name untouched.
KEEP_MARKERS = (
    "Zammad Foundation",
    "Zammad GmbH",
    "zammad-attachment",
    "X-Zammad",
    "Filepath to Zammad directory",
    "Zammad Forms requires jQuery",
    "Zammad User Agent",
    # Upstream's translation portal and BETA-UI research programme.
    "help translating",
    "Help to improve Zammad",
    "Help us shape the future of Zammad",
    "of this language is already translated",
    "BETA research",
    "tracked usage time of the new UI",
)

# Applied in order, so the longer German compounds win before the bare name.
# The trailing-hyphen forms matter: German wraps "Zammad-" onto its own line and
# a naive replacement would produce "Virtual Marketer Ticketing-Konto".
SUBSTITUTIONS = [
    ("Zammad-Stiftung", "Zammad-Stiftung"),          # explicit no-op, see KEEP
    ("Zammad-Konto", f"{PRODUCT_SHORT}-Konto"),
    ("Zammad-Agenten-Konten", f"{PRODUCT_SHORT}-Agenten-Konten"),
    ("Zammad-Prozesse", "Serverprozesse"),
    ("Zammad-Verzeichnis", "Installationsverzeichnis"),
    ("Zammad-Dokumentation", "Dokumentation"),
    ("Zammad-API", f"{PRODUCT_SHORT}-API"),
    ("Zammad API", f"{PRODUCT_SHORT}-API"),
    ("Zammad-Endpunkte", f"{PRODUCT_SHORT}-Endpunkte"),
    ("Zammad-Wartungsmodus", "Wartungsmodus"),
    ("Zammad-Version", "Version"),
    ("Zammad-Instanz", "Instanz"),
    ("Zammad-Anhangs", "Anhangs"),
    ("Zammad-Benutzeroberfläche", "Benutzeroberfläche"),
    ("Zammad-Systems", f"{PRODUCT_SHORT}-Systems"),
    ("Zammad-", f"{PRODUCT_SHORT}-"),
    ("Zammad", PRODUCT),
]


def split_entries(lines):
    """Yield (start, msgid_text, msgstr_start, msgstr_end) for every entry.

    Hand-rolled rather than using polib: this repository has no Python
    dependencies of its own, and the subset of PO syntax in these catalogues is
    small enough that a parser is not worth an install step.
    """
    i = 0
    while i < len(lines):
        if not lines[i].startswith('msgid "'):
            i += 1
            continue
        mid = [lines[i]]
        j = i + 1
        while j < len(lines) and lines[j].startswith('"'):
            mid.append(lines[j])
            j += 1
        if j >= len(lines) or not lines[j].startswith("msgstr"):
            i = j
            continue
        # msgstr, or the msgstr[0]/msgstr[1] plural forms.
        k = j
        while k < len(lines) and (lines[k].startswith("msgstr") or lines[k].startswith('"')):
            k += 1
        yield ("".join(mid), j, k)
        i = k


def rebrand(text):
    for old, new in SUBSTITUTIONS:
        text = text.replace(old, new)
    return text


def process(path, check):
    lines = Path(path).read_text(encoding="utf-8").split("\n")
    changed = 0
    kept = 0

    for msgid, start, end in list(split_entries(lines)):
        if any(marker in msgid for marker in KEEP_MARKERS):
            if "Zammad" in "".join(lines[start:end]):
                kept += 1
            continue
        for n in range(start, end):
            if "Zammad" not in lines[n]:
                continue
            new = rebrand(lines[n])
            if new != lines[n]:
                lines[n] = new
                changed += 1

    remaining = sum(1 for n in lines if n.startswith(('msgstr', '"')) and "Zammad" in n)
    print(f"{path}: {changed} line(s) rebranded, {kept} entrie(s) kept on purpose")

    if check:
        return changed

    Path(path).write_text("\n".join(lines), encoding="utf-8")
    return changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="report without writing")
    args = ap.parse_args()

    total = 0
    for rel in CATALOGUES:
        p = ROOT / rel
        if not p.exists():
            print(f"missing: {rel}", file=sys.stderr)
            return 1
        total += process(p, args.check)

    if args.check and total:
        print("catalogues are out of date -- re-run without --check", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
