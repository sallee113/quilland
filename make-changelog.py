#!/usr/bin/env python3
"""Prints a draft of the next changelog section: the subjects of the commits since the last tag (or all of them), grouped by the area each begins with.

Usage: python3 make-changelog.py            (draft since the last tag)
The draft is a start, not the text: tidy it into what an author of a book would want to read, then put it at the top of CHANGELOG.md under `## X.Y.Z — date`."""
import re, subprocess, sys

def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout.strip()

try:
    last = git("describe", "--tags", "--abbrev=0")
    log = git("log", f"{last}..HEAD", "--format=%s")
except subprocess.CalledProcessError:
    last, log = None, git("log", "--format=%s")

skip = re.compile(r"^(Merge |Release |fixup|Initial commit)", re.I)
groups = {}
for subject in log.splitlines():
    if not subject or skip.match(subject):
        continue
    m = re.match(r"^([^:]{2,40}):\s+(.*)$", subject)
    area, text = (m.group(1), m.group(2)) if m else ("Other", subject)
    # (A subject that begins with a verb before its colon, "Add Research: …", is a sentence, not an area.)
    if re.match(r"^(Add|Show|Keep|Replace|Move|Make|Fix|Learn|Check)\b", area):
        area, text = ("Added" if area.startswith("Add") else "Other"), subject
    groups.setdefault(area, []).append(text)

print(f"<!-- draft since {last or 'the beginning'} -->")
for area in sorted(groups, key=lambda a: (a == "Other", a.lower())):
    print(f"### {area}")
    for text in reversed(groups[area]):
        print(f"- {text}")
    print()
