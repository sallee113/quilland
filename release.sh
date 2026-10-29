#!/bin/zsh
# Makes a release: checks, version, tag.   Usage: ./release.sh 0.2.0 [--no-checks]
# Before it, put the section `## 0.2.0 — date` at the top of CHANGELOG.md (python3 make-changelog.py prints a draft).
# It commits VERSION and CHANGELOG.md as "Release X.Y.Z" and tags vX.Y.Z. It never pushes: push with  git push origin main vX.Y.Z
set -e
cd "$(dirname "$0")"
V="$1"
[[ "$V" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "usage: ./release.sh X.Y.Z [--no-checks]"; exit 1 }
[ "$(git branch --show-current)" = main ] || { echo "release from main"; exit 1 }
git diff --quiet HEAD -- . ':!VERSION' ':!CHANGELOG.md' || { echo "commit or stash your changes first"; exit 1 }
git tag -l "v$V" | grep -q . && { echo "v$V already exists"; exit 1 }
grep -q "^## $V — " CHANGELOG.md || { echo "CHANGELOG.md has no section '## $V — date'. A draft:"; python3 make-changelog.py; exit 1 }
if [ "$2" != "--no-checks" ]; then
  swift test
  swift build -c release
  .build/release/Quilland --selftest-app | tail -1 | grep -q " 0 failed" || { echo "the application's self-test failed"; exit 1 }
  .build/release/Quilland --selftest-lab | tail -1 | grep -q " 0 failed" || { echo "the Lab's self-test failed"; exit 1 }
fi
echo "$V" > VERSION
git add VERSION CHANGELOG.md
git diff --cached --quiet || git commit -q -m "Release $V"
git tag -a "v$V" -m "Quilland $V"
echo "Tagged v$V. Push with: git push origin main v$V"
