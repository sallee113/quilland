#!/usr/bin/env python3
"""Makes Resources/Languages/template.json: the list of interface texts to translate, found in the Swift sources as L("…") and Lp("…", "…", n).
Run it after adding or changing a text; a test fails when the template is behind the code."""
import re, json, pathlib, sys

root = pathlib.Path(__file__).parent
SKIP = {'AppSelfTest.swift', 'LabWindowController.swift', 'LabBookGenerator.swift', 'LabPlanGenerator.swift', 'LabSelfTest.swift', 'main.swift'}
LIT = r'"((?:[^"\\\n]|\\.)*)"'
single = re.compile(r'(?<![A-Za-z_])L\(\s*' + LIT)
plural = re.compile(r'(?<![A-Za-z_])Lp\(\s*' + LIT + r'\s*,\s*' + LIT)

def unescape(s):
    s = s.replace('\\"', '"').replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')
    return re.sub(r'\\u\{([0-9a-fA-F]+)\}', lambda m: chr(int(m.group(1), 16)), s)

def scan():
    strings, plurals = set(), {}
    for sub in ('Sources/Quilland', 'Sources/QuillandCore'):
        for f in sorted((root / sub).rglob('*.swift')):
            if f.name in SKIP: continue
            text = f.read_text()
            for m in plural.finditer(text):
                plurals[unescape(m.group(2))] = unescape(m.group(1))
            for m in single.finditer(text):
                s = unescape(m.group(1))
                # a plural's first argument is also matched by `Lp(` only, never by `L(`
                strings.add(s)
    return sorted(strings), plurals

if __name__ == '__main__':
    strings, plurals = scan()
    out = {"format": 1, "strings": {s: "" for s in strings}, "plurals": {other: {"one": one, "other": other} for other, one in sorted(plurals.items())}}
    path = root / 'Resources/Languages/template.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(out, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"{len(strings)} texts and {len(plurals)} plural texts in {path}")
