# Quilland

> **Under construction.** Quilland is still being built. Things change often and some parts are unfinished or may not work as expected. Back up your books before using it.

A local-first workspace for writers, for macOS. Your book is a folder of plain files: prose in Markdown, everything else in JSON, ready for Git. A native editor shows the text as you write it, and an optional local AI (through [LM Studio](https://lmstudio.ai)) can help with proofreading, continuing a scene, finding characters and places, checking consistency and answering questions about your book. Nothing leaves your computer.

## Building

Requires macOS 14 or later and Swift 6.

```bash
swift build -c release   # the app and the core library
swift test               # the unit tests
./make-app.sh            # makes Quilland.app
```

`.build/release/Quilland --selftest-app` runs the application's automatic checks.

The application has no third-party dependencies, only Apple's frameworks.

## Versions

The version is in the [`VERSION`](VERSION) file, and what changed in each release is in the [changelog](CHANGELOG.md); `Quilland --version` prints the version, and *Help ▸ What's New in Quilland* shows the changelog. A release is a git tag `vX.Y.Z`, made by `./release.sh X.Y.Z` after the changelog has its section (`python3 make-changelog.py` prints a draft from the git log).

## Documentation

See the [user guide](docs/user-guide.md) ([en français](docs/user-guide.fr.md)).

## License

Quilland is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE). You are welcome to read it, run it, change it and fork it for any noncommercial purpose. You may not sell it or its modified versions, or use it in a commercial product or service, without the author's permission. It is not open source in the sense of the Open Source Initiative, because commercial use is not allowed.

Contributions to this repository are accepted under the same license.

Copyright 2026 Vadim Soluyanov.
