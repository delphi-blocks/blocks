# DelphiBlocks

> **Early preview — work in progress.**

A command-line package manager for Delphi / RAD Studio. DelphiBlocks automates downloading, compiling, and registering third-party Delphi packages sourced from a GitHub-hosted registry.

## How it works

1. Reads a JSON manifest from the [blocks-repository](https://github.com/delphi-blocks/blocks-repository).
2. Downloads the package source as a ZIP from GitHub.
3. Compiles it with MSBuild against the selected Delphi version.
4. Registers the library paths in the Delphi registry and records the installation in a local database (`.blocks/`).
5. Supports multiple Delphi IDE profiles via the `registrykey` workspace setting. Delphi allows launching with an alternative registry profile using the `-r` flag (e.g. `bds.exe -r MyProfile`).
6. Supports custom package repositories. In addition to the default registry, you can add your own GitHub-hosted repositories as package sources.

## Requirements

- Windows
- Delphi / RAD Studio XE6 or later (BDS 14.0 – 37.0)
- MSBuild (bundled with RAD Studio)

## Usage

```
Commands:
  install <source>       Install a package from a file path, URL, or registry ID.
  uninstall <source>     Remove a package from the workspace and database.
  init                   Initialise the workspace and download the package repository.
  list                   List packages installed in the current workspace.
  listproducts           List detected Delphi installations.
  config                 Read or write workspace or system configuration values.
  view <id@version>      Show details of a package from the repository.
  version                Print the version of the blocks executable.
  upgrade                Check for a newer release and download the setup if available.
  help [command]         Show this message, or detailed help for a specific command.
```

### Quick start

```bat
REM Install DelphiBlocks
winget install DelphiBlocks.Blocks

REM Initialise the workspace in the current directory (prompts for Delphi version)
blocks init

REM Install a package
blocks install owner.package

REM Install a specific version
blocks install owner.package@1.2.0

REM Uninstall
blocks uninstall owner.package

REM List installed packages
blocks list

REM View package info
blocks view owner.package@1.2.0
blocks view owner.package /versions

REM Manage repository sources
blocks config sources
blocks config /add sources=https://github.com/owner/my-repo
```

### Version constraints

Append `@<constraint>` to a package ID to pin or restrict the version:

| Syntax | Meaning |
|--------|---------|
| `@1.2.0` | Exact version |
| `@^1.2.0` | Same major (`>=1.2.0 <2.0.0`) |
| `@~1.2.0` | Same minor (`>=1.2.0 <1.3.0`) |
| `@>=1.0.0` | At least 1.0.0 |
| `@>=1.0.0 <2.0.0` | Explicit range |

> **Note:** In `cmd.exe` the `^` character must be escaped as `^^` (e.g. `owner.package@^^1.2.0`). In PowerShell no escaping is needed.

## Canonical mode

When you run `blocks init` you are asked whether to use **canonical mode**. This setting is stored in the workspace configuration and applied to every subsequent `install` and `uninstall` in that workspace.

### The problem canonical mode solves

A Delphi package project (`.dproj`) declares its own output directories for `.dcu`, `.bpl`, and `.dcp` files. Those paths are usually relative, version-specific, or even hardcoded by the package author, and they vary widely across third-party libraries. When the same Delphi installation is used under different IDE registry profiles (created with `bds.exe -r <key>`), compiled artefacts from different profiles can collide or overwrite each other.

### What canonical mode does

In canonical mode **Blocks ignores the output paths declared inside the `.dproj`** and instead redirects all compiler output to a well-known directory tree under the workspace's `.blocks/` folder, regardless of what the package author has written:

| Artefact | Output path |
|----------|-------------|
| Release DCUs | `<project>\lib\<Platform>\` |
| Debug DCUs | `<project>\lib\<Platform>\debug\` |
| BPL files | `.blocks\bpl\` |
| DCP files | `.blocks\dcp\` |

These paths are passed to MSBuild via `/p:DCC_DcuOutput`, `/p:DCC_BplOutput`, and `/p:DCC_DcpOutput`, so the package source itself never needs to be modified.

Both the **debug** and **release** configurations are compiled for every package; the Delphi library registry entries point at the canonical paths above rather than at whatever the `.dproj` specifies.

### When to use it

Canonical mode (the default) makes the compiled output of every package homogeneous and predictable, regardless of how each package author configured the `.dproj`. This is especially useful when you need to install the same package — possibly in different versions — against the same Delphi installation but under different IDE registry profiles (created with `bds.exe -r <key>`): because each profile gets its own `.blocks\bpl\` and `.blocks\dcp\` trees, the artefacts do not collide.

To enable or disable canonical mode after initialisation:

```bat
blocks config canonical=True
blocks config canonical=False
```

> **Warning:** changing this setting in a workspace that already has packages installed is dangerous: Blocks uses the flag to locate BPL/DCU files and registry paths during uninstall. Uninstall all packages before toggling it.

## Package manifest

Each package in the repository is described by a JSON manifest file (`<vendor>.<name>.manifest.json`). Below is an annotated example.

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

  // Platforms declare the source paths to add to the Delphi library search paths.
  // In canonical mode the DCU output paths are ignored and overridden by Blocks.
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

| Field | Description |
|-------|-------------|
| `id` | Unique package identifier in `vendor.name` form. |
| `repository.url` | GitHub tree URL pinned to a tag or commit; Blocks downloads the ZIP from this ref. |
| `platforms` | Per-platform source and DCU paths added to the Delphi library registry. |
| `packages` | List of `.dproj` files to compile; type can be `runtime`, `designtime`, or both. |
| `packageOptions.folders` | Maps Delphi version keys to the subfolder under `packages\` containing the `.dproj` files. A `+` suffix means "this version or newer". |
| `dependencies` | Other packages that must be installed first, with their version constraints. |

## Application manifest

The executable embeds `Source\blocks.manifest`, which declares:

- **Execution level** — `asInvoker` (no UAC elevation required).
- **Supported OS** — Windows 10 and Windows 11.

## Building from source

All source files are under `Source/`. The project has no external dependencies: open `Source\Blocks.dproj` in Delphi / RAD Studio and compile. The compiled executable (`Blocks.exe`) is placed in the project root.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
