# Changes from v0.6.1 to v0.6.2

## New Features

- **`toolarchitecture` setting** — a workspace can choose which build of the
  Delphi command-line compiler MSBuild runs (Delphi 13+): `default`, `x32`
  (32-bit tools) or `x64` (64-bit tools, giving the compiler more memory for large
  packages). It only affects which tools run, not the produced binary, and is set
  with `blocks config toolarchitecture=x64`.

## Improvements

- **Smarter upgrade** — `upgrade` now downloads the installer that matches the
  current platform automatically, falling back to asking only when it cannot tell.
- **Version in the banner** — the banner now shows the version of the blocks
  executable.
- **More reliable compilation** — the build environment is detected from the
  installed Delphi rather than from hardcoded paths, so package compilation works
  with non-default Delphi install locations.
- **New app icon** — refreshed application icon and logo.

## Experimental (not distributed in this release)

- **Win64 setup** — preliminary 64-bit build alongside the 32-bit one, with a
  separate installer per architecture and the version embedded in the setup
  filename. Still experimental and not shipped in this release.
