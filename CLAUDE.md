# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**DelphiBlocks** is a CLI package manager for Delphi/RAD Studio written in Delphi (Pascal). It automates installing, compiling, and registering Delphi packages from a GitHub-hosted repository. The remote package registry lives at https://github.com/lminuti/blocks-repository.

## Documentation

`docs/` is the English documentation directory. End-user/feature docs live there (e.g. `docs/script.md` describes the manifest scripts feature). Write documentation in English.

## Build

Source code is under `Source/`. To compile any `.dproj` (the main app, the launcher, or the test project) **use the `DelphiServer` MCP server** (`mcp__DelphiServer__compile`) — do not run the `BuildRelease.bat` / `run-tests.bat` batch files. Use `mcp__DelphiServer__list_products` if you need to discover the installed Delphi version.

Example — compile the main app:

```
mcp__DelphiServer__compile(
  product="delphi13",
  projectFileName="c:\\Progetti\\DelphiBlocks\\Source\\Blocks.dproj",
  config="Release",
  platform="Win32"
)
```

The batch files (`setup\BuildRelease.bat`, `Tests\run-tests.bat`) still exist for the user to run locally and to produce the Inno Setup installer, but Claude should always go through the MCP server for compilation.

### Tests

DUnitX test project: `Tests\Blocks.Tests.Framework.dproj`. **Always compile tests in `Release` config** (Win32) via the MCP server, then run the produced executable at `Tests\Win32\Release\Blocks.Tests.Framework.exe`.

## Code Formatting

The project uses `pasfmt` with `begin_style = "always_wrap"` and `line_ending = "crlf"`. Run `pasfmt` on `.pas` files before committing.

## Architecture

`TApp.RunBlocks` (in `Blocks.CLI.App.pas`) parses the command line and dispatches to a command class. The install/uninstall pipeline lives in `TWorkspace` (`Blocks.Service.Workspace.pas`):

1. Resolve package manifest → install dependencies → download & extract GitHub zipball → compile via MSBuild (in `TProduct.BuildPackages`) → register library paths in Delphi's registry → update the local package database.

### Key modules

| Unit | Role |
|------|------|
| `Blocks.CLI.App.pas` | Top-level command dispatcher; defines all command classes (`init`, `install`, `uninstall`, `list`, `view`, `config`, `upgrade`, ...) |
| `Blocks.CLI.Command.pas` | Base command class with attribute-driven parameter parsing (`[Param]`) |
| `Blocks.Service.Workspace.pas` | Owns the install/uninstall pipeline; initialises the `.blocks/` workspace and clones the remote repository |
| `Blocks.Service.Product.pas` | Detects installed Delphi versions (registry scan), runs MSBuild to compile packages, updates Delphi library search paths in the registry |
| `Blocks.Model.Manifest.pas` | Parses `.manifest.json` files; resolves the best package-folder for the active Delphi version |
| `Blocks.Model.Package.pas` | `.dproj` loader; reads MSBuild properties (`LibSuffix`, `DCC_DcuOutput`, ...) |
| `Blocks.Model.Database.pas` | Per-workspace, per-Delphi-version JSON file (`.blocks/{version}-database.json`) tracking installed packages as `owner.pkg@version` |
| `Blocks.Model.Config.pas` | Workspace configuration (sources, target platforms, target Delphi version, registry key) persisted as `.blocks/workspace.json`. Empty `platforms` = all supported platforms; `IsPlatformEnabled` is the install/uninstall filter |
| `Blocks.Model.SysConfig.pas` | System-level configuration stored in the Windows registry |
| `Blocks.Http.pas` | Thin wrapper over `System.Net.HttpClient`; downloads with progress reporting |
| `Blocks.GitHub.pas` | GitHub API helpers (repo info, releases, ZIP URL building, ZIP download+extraction) |
| `Blocks.Console.pas` | Colored console output (stdout/stderr) and stdin reading |
| `Blocks.Consts.pas` | BDS version → internal name map (e.g. `37.0` → `delphi13`) |
| `Blocks.Core.pas` | Core utilities (`TSemVer`, version constraint matching, regex helpers) |
| `Blocks.JSON.pas` | RTTI-based JSON serialization helpers (`TJsonHelper`) |

### Data files at runtime

- `.blocks/repository/{owner}/{package}.json` — manifest files (downloaded from GitHub)
- `.blocks/{version}-database.json` — local record of what is installed

### Package manifest JSON shape

```json
{
  "id": "owner.package",
  "name": "Package Name",
  "version": "1.2.3",
  "repository": { "type": "github", "url": "https://github.com/owner/repo/tree/v1.2.3" },
  "platforms": {
    "Win32": { "sourcePath": ["Source\\Core"] }
  },
  "packages": [{ "name": "PackageName", "type": ["runtime"] }],
  "packageOptions": {
    "folders": { "delphi12+": "12.0Athens" }
  },
  "dependencies": { "owner.pkg": "^1.0.0" }
}
```

DCUs are written to `<workspace>\.blocks\lib\<name>\<Platform>\[debug]`, where `<name>` is the manifest's `name`. The path is fixed and Blocks overrides the `.dproj`'s `DCC_DcuOutput` for both Debug and Release.

### Supported Delphi versions

BDS 14.0 (XE6) through BDS 37.0 (Delphi 13 Florence). Internal names follow the pattern `delphixe6` … `delphi13`. The mapping is in `Blocks.Consts.pas`.

## CLI Reference

The CLI uses a `<command> [/option [value]] ...` syntax: subcommands are bare words, options are slash-prefixed. Run `blocks help <command>` for full per-command help.

```
blocks <command> [options]

Commands:
  install <package>        Install a package by id (vendor.name) or name (append @<constraint> for version)
  build <package>          Recompile an already-installed package without downloading it
  update <package>         Update an installed package (append @<version>) and recompile its dependents
  uninstall <package>      Remove a package from the workspace and database
  init                     Initialise the workspace and download the repository
  list                     List packages installed in the current workspace
  listproducts             List detected Delphi installations
  search [pattern]         Search the repository index by id, name, description or keywords
  config                   Read or write workspace or system configuration values
  view <id[@version]>      Show details of a package from the repository
  version                  Print the version of the blocks executable
  upgrade                  Check for a newer release and download the setup
  help [command]           Show general help, or detailed help for a command
```

Common options (per command — see `blocks help <command>` for the full list):

| Option | Used by | Effect |
|--------|---------|--------|
| `/product <version>` | init | Target Delphi version (e.g. `delphi13`) |
| `/platforms <list>` | init | Comma-separated platforms to target (empty/prompt = all) |
| `/registrykey <key>` | init | Registry profile key (default: `BDS`); for `bds.exe -r <key>` |
| `/overwrite` | install | Overwrite the project directory if it already exists |
| `/silent` | install, build, update, version | Skip non-critical interactive prompts |
| `/force` | install, update, upgrade | Continue past version conflicts / re-install when up to date |
| `/add` | config | Append to a list value instead of replacing |
| `/system` | config | Target system-level config (registry) instead of workspace |
| `/raw` | view | Print raw manifest JSON instead of formatted summary |
| `/versions` | view | List all available versions of the package |
| `/all` | listproducts | Show all supported Delphi versions, not just installed |
| `/check` | upgrade | Only check for a newer version; do not download |
