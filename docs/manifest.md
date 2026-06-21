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
  // DCUs are written by Blocks to <workspace>\.blocks\lib\<name>\<Platform>[\debug].
  "platforms": {
    "Win32": {
      "sourcePath":     ["Source\\Core", "Source\\Client"],
      "releaseDCUPath": ["lib\\Win32\\release"],
      "debugDCUPath":   ["lib\\Win32\\debug"]
    },
    // On a runtime-only platform, design-time packages are skipped on install.
    "Win64": {
      "sourcePath":  ["Source\\Core", "Source\\Client"],
      "runtimeOnly": true
    }
  },

  // Each entry maps to a .dproj file under packages\<folder>\
  // "products" is optional; when omitted the package targets every Delphi version.
  "packages": [
    { "name": "WiRL",       "type": ["runtime"] },
    { "name": "WiRLDesign", "type": ["designtime"], "products": ["delphi103+"] }
  ],

  // "rootFolder" is the directory (relative to the project root) that holds the
  // package folders; it defaults to "packages" and can be overridden here.
  // "folders" maps Delphi version names to the subfolder under rootFolder that
  // contains the .dproj files for that version. A trailing + means "this version
  // or newer".
  "packageOptions": {
    "rootFolder": "packages",
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
| `repository.type` | Source repository type: `github`, `bitbucket`, or `local`. |
| `repository.url` | Repository URL pinned to a tag or commit; Blocks downloads the ZIP from this ref. For `github` use a tree URL (`https://github.com/owner/repo/tree/<ref>`), for `bitbucket` a src URL (`https://bitbucket.org/owner/repo/src/<ref>`), for `local` a filesystem path. |
| `platforms` | Per-platform `sourcePath` (registered in the Delphi "Browsing Path") and optional `releaseDCUPath` / `debugDCUPath`. Set `runtimeOnly: true` to skip design-time packages when installing that platform. A key may list several platform names separated by commas (e.g. `"Win64,Linux64"`) as shorthand for declaring the same settings on each of them — available since v0.6.3. |
| `packages` | List of `.dproj` files to compile; `type` can be `runtime`, `designtime`, or both. A `name` may contain the `$(PACKAGE_VERSION)` placeholder — see below. An optional `products` list restricts the package to specific Delphi versions — see below. |
| `packageOptions.rootFolder` | Directory (relative to the project root) that contains the package folders. Defaults to `packages`. |
| `packageOptions.folders` | Maps Delphi version keys to the subfolder under `rootFolder` containing the `.dproj` files. A `+` suffix means "this version or newer". An entry of `.` (or an empty/absent `folders` map) means the `.dproj` files live directly under `rootFolder`, with no per-version subfolder. |
| `dependencies` | Other packages that must be installed first, with their version constraints. See [versioning.md](versioning.md). |
| `scripts` | Optional built-in commands run at lifecycle events (e.g. `afterCompile`). See [script.md](script.md). |

## Shared platform settings

*Available since v0.6.3.*

When two or more platforms share the same `sourcePath` (and other settings),
the `platforms` key can list their names separated by commas instead of
repeating the same block:

```jsonc
"platforms": {
  "Win64,Linux64": {
    "sourcePath": ["Source\\Core"]
  }
}
```

This is equivalent to declaring `"Win64"` and `"Linux64"` separately with
identical settings.

## Package name placeholder

Some libraries name their `.dproj` files with the Delphi **package-version suffix**
(e.g. `Trysil290.dproj` for Delphi 12, `Trysil370.dproj` for Delphi 13). Because a
`packages[].name` is a single fixed string, you would otherwise need one manifest
per Delphi version.

To cover them all with a single manifest, a package `name` may contain the
`$(PACKAGE_VERSION)` placeholder. When compiling, Blocks replaces it with the
package-version suffix of the **active** Delphi version before locating the
`.dproj`:

| Delphi version | `$(PACKAGE_VERSION)` |
|----------------|----------------------|
| `delphixe6`    | `200` |
| `delphixe7`    | `210` |
| `delphixe8`    | `220` |
| `delphi10`     | `230` |
| `delphi101`    | `240` |
| `delphi102`    | `250` |
| `delphi103`    | `260` |
| `delphi104`    | `270` |
| `delphi11`     | `280` |
| `delphi12`     | `290` |
| `delphi13`     | `370` |

```jsonc
"packages": [
  { "name": "Trysil$(PACKAGE_VERSION)",       "type": ["runtime"] },
  { "name": "Trysil.JSon$(PACKAGE_VERSION)",  "type": ["runtime"] }
],
"packageOptions": {
  "folders": {
    "delphi12": "290",   // packages\290\Trysil290.dproj
    "delphi13": "370"    // packages\370\Trysil370.dproj
  }
}
```

The placeholder is case-insensitive and follows the same `$(NAME)` convention used
by [manifest scripts](script.md). It only affects how the `.dproj` is located: the
compiled `.bpl` / `.dcp` names come from the `.dproj` itself and are unchanged.

## Per-package Delphi versions

Some libraries ship different `.dproj` files for different Delphi versions — for
example a design-time package that only exists since a certain release, or a
package that was dropped in newer versions. The optional `products` field on a
`packages[]` entry restricts that package to the Delphi versions it supports:

```jsonc
"packages": [
  // Compiled on every Delphi version (no "products" field).
  { "name": "SVGIconImageList",        "type": ["runtime"] },

  // Compiled only on Delphi 10.3 and newer.
  { "name": "SVGIconImageListFMX",     "type": ["runtime", "FMX"], "products": ["delphi103+"] },

  // Compiled only on these two specific versions.
  { "name": "dclSVGIconImageList",     "type": ["designtime"], "products": ["delphixe6", "delphixe7"] }
]
```

Rules:

- **Omitted or empty** — the package is compatible with every Delphi version.
- **Exact name** (e.g. `delphixe7`) — the package targets *only* that version.
- **`+` suffix** (e.g. `delphi103+`) — the package targets that version *and every
  newer one*.

Version names are the internal `delphi*` identifiers listed in the
`$(PACKAGE_VERSION)` table above. When a package does not support the Delphi version
being installed, Blocks skips it everywhere in the pipeline: it is not compiled, no
design-time package is registered, and no library paths are added (or removed on
uninstall).

## Related guides

- [Versioning and dependencies](versioning.md) — version constraint syntax and how
  `dependencies` are resolved.
- [Manifest scripts](script.md) — the `scripts` array, lifecycle events and built-in
  commands.
