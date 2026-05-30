# Package Manifest

Each package in the repository is described by a JSON manifest file
(`<vendor>.<name>.manifest.json`). The manifest tells Blocks where to fetch the
sources, which `.dproj` files to compile, where to register library paths, and
which other packages are required.

## Annotated example

```jsonc
{
  "$schema": "https://delphi-blocks.dev/schema/package.v1.json",
  "id": "delphi-blocks.wirl",       // vendor.name identifier
  "name": "WiRL",                    // human-readable name
  "version": "4.6.0",
  "description": "RESTful Library for Delphi",
  "license": "Apache-2.0",
  "homepage": "https://wirl.delphi-blocks.dev",
  "author": "Paolo Rossi, Luca Minuti <info@lucaminuti.it>",
  "keywords": ["rest", "http", "api"],

  "repository": {
    "type": "github",
    "url": "https://github.com/delphi-blocks/WiRL/tree/v4.6.0"
  },

  // "sourcePath" entries are registered in the Delphi library "Browsing Path".
  // DCU output locations come from the .dproj itself; Blocks does not override them.
  "platforms": {
    "Win32": {
      "sourcePath":     ["Source\\Core", "Source\\Client"],
      "releaseDCUPath": ["lib\\Win32\\release"],
      "debugDCUPath":   ["lib\\Win32\\debug"]
    }
  },

  // Each entry maps to a .dproj file under packages\<folder>\
  "packages": [
    { "name": "WiRL",       "type": ["runtime"] },
    { "name": "WiRLDesign", "type": ["designtime"] }
  ],

  // Maps Delphi version names to the subfolder under packages\ that contains
  // the .dproj files for that version. A trailing + means "this version or newer".
  "packageOptions": {
    "folders": {
      "delphi11":  "11.0Alexandria",
      "delphi12+": "12.0Athens"
    }
  },

  // version constraints follow semver syntax (@^x.y.z, @>=x.y.z, etc.)
  "dependencies": {
    "paolo-rossi.delphi-neon": "^3.1.0"
  }
}
```

## Field reference

| Field | Description |
|-------|-------------|
| `id` | Unique package identifier in `vendor.name` form. |
| `name` | Human-readable package name. Used by `search` and as the extracted project folder name. |
| `version` | Package version in `MAJOR.MINOR.PATCH` form. |
| `description` | Short description, shown by `search` and `view`. |
| `license` | SPDX license identifier (e.g. `Apache-2.0`). |
| `homepage` | Project homepage URL. |
| `author` | Author(s); free-form, optionally with an email. |
| `keywords` | List of keywords used by `search`. |
| `repository.type` | Source repository type. Currently `github`. |
| `repository.url` | GitHub tree URL pinned to a tag or commit; Blocks downloads the ZIP from this ref. |
| `platforms` | Per-platform `sourcePath` (registered in the Delphi "Browsing Path") and optional `releaseDCUPath` / `debugDCUPath`. |
| `packages` | List of `.dproj` files to compile; `type` can be `runtime`, `designtime`, or both. |
| `packageOptions.folders` | Maps Delphi version keys to the subfolder under `packages\` containing the `.dproj` files. A `+` suffix means "this version or newer". |
| `packageOptions.keepProjectDcuPaths` | Optional; defaults to `false`. When `true`, DCU output paths are taken from the `.dproj` instead of Blocks' default `<project>\lib\<Platform>\`. Should not be used unless preserving the DCU layout declared by the `.dproj` is strictly necessary. |
| `dependencies` | Other packages that must be installed first, with their version constraints. See [versioning.md](versioning.md). |
| `scripts` | Optional built-in commands run at lifecycle events (e.g. `afterCompile`). See [script.md](script.md). |

## Related guides

- [Versioning and dependencies](versioning.md) — version constraint syntax and how
  `dependencies` are resolved.
- [Manifest scripts](script.md) — the `scripts` array, lifecycle events and built-in
  commands.
