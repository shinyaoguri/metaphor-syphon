# Contributing to metaphor-syphon

This repository is the Syphon output plugin for
[metaphor](https://github.com/shinyaoguri/metaphor). The core library's
[contribution guide](https://github.com/shinyaoguri/metaphor/blob/main/CONTRIBUTING.md)
applies here as well — this page only covers what is different.

## Where to file an issue

| Topic | Repository |
|---|---|
| Publishing to Syphon (`.syphon(name:)`, `METAPHOR_SYPHON_NAME`, the server itself, this package's build / release) | here |
| Drawing, the `Sketch` API, the plugin lifecycle, Probe, Parameter Store | [metaphor](https://github.com/shinyaoguri/metaphor/issues) |
| The `metaphor` command (`run --syphon`, `watch --syphon`, the `syphon` template), Homebrew install | [metaphor-cli](https://github.com/shinyaoguri/metaphor-cli/issues) |

If you're unsure, file it here and we'll route it.

## Development setup

Requirements: macOS 14+, Apple Silicon, Xcode 15.4+ (Swift 5.10+) — the same as
the core library. Xcode (not just the Command Line Tools) is needed to build
`Syphon.xcframework` from the `Vendor/Syphon-Framework` submodule.

```bash
make setup      # submodule + Frameworks/Syphon.xcframework (first time only)
make build
make test
make ci-check   # what CI runs: build + test with -Xswiftc -warnings-as-errors
./scripts/verify.sh           # actionlint + shellcheck + Python unit tests
./scripts/check-registration.sh   # provider auto-registration in debug and release (CI: registration-matrix)
```

Without `Frameworks/Syphon.xcframework` the package resolves the framework from
the pinned Release asset instead, exactly as consumers do. `make clean-syphon`
removes the local build when you want to test that path.

## Sending a pull request

- **PR titles follow [Conventional Commits](https://www.conventionalcommits.org/)**
  (`<type>(<scope>): <summary>`). PRs are squash-merged and the title becomes the
  commit message on `main`, so CI lints it (`pr-policy`).
- One concern per PR. Note anything you spot along the way as a separate issue
  instead of fixing it in passing.
- Fill in the PR template: purpose, changes, and how to verify. If the change
  affects what a Syphon client receives, say which client you tested with and
  attach a screenshot.
- Tests use [Swift Testing](https://developer.apple.com/documentation/testing)
  (`@Suite` / `@Test`), not XCTest. Suites that create a Syphon server need a
  GPU — gate them with `.enabled(if: MTLCreateSystemDefaultDevice() != nil)`.
- `llms.txt` is written by hand. If you change the public API, update it in the
  same PR.
- Never edit the `binaryTarget` url / checksum in `Package.swift` by hand — the
  release workflow rewrites them ([docs/releasing.md](docs/releasing.md)).

## Updating Syphon-Framework

Bump the `Vendor/Syphon-Framework` submodule, run `make setup` to rebuild the
xcframework, run `make ci-check`, and open a PR. The next release builds the new
framework into its asset; nothing else to do.

## License

By contributing you agree that your contributions are licensed under the MIT
License, the same as this repository. Syphon-Framework is distributed under its
own license (see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)).
