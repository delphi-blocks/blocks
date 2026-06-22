# Command-line reference

This page lists every Blocks command and its options. The text below is the output of `blocks help` and `blocks help <command>`.

Run `blocks help <command>` at any time to get the same information from the command line.

## Overview

Delphi package manager: download, compile and register packages from a GitHub-hosted repository into your Delphi/RAD Studio installation.

```
Usage: Blocks <command> [options]

Commands:
  install <package>      Install a package by id (vendor.name) or name.
  build <package>        Recompile an already-installed package without downloading it.
  update <package>       Update an installed package and recompile its dependents.
  uninstall <package>    Remove a package from the workspace and database.
  init                   Initialise the workspace and download the package repository.
  list                   List packages installed in the current workspace.
  product [name...]      Show Delphi installations. Pass names to filter and get details.
  search [pattern]       Search the repository index by id, name, description or keywords.
  config                 Read or write workspace or system configuration values.
  view <id[@version]>    Show details of a package from the repository.
  version                Print the version of the blocks executable.
  upgrade                Check for a newer release and download the setup if available.
  help [command]         Show this message, or detailed help for a specific command.

Examples:
  Blocks init /product delphi13
  Blocks install owner.package
  Blocks install package /silent
  Blocks uninstall owner.package
  Blocks search json
  Blocks list
  Blocks help install
```

## Common commands

```bat
REM Initialise the workspace in the current directory (prompts for Delphi version)
blocks init

REM Install a package (latest, or a specific version)
blocks install owner.package
blocks install owner.package@1.2.0

REM Update a package (proposes the latest within the installed major, or pick one)
blocks update owner.package
blocks update owner.package@2.0.0

REM Uninstall a package
blocks uninstall owner.package

REM List installed packages
blocks list

REM Show detected Delphi installations
blocks product

REM Show all properties for each installation (active platforms, search paths, running status)
blocks product /detail

REM Show details for a specific version (optionally with a registry profile)
blocks product delphi13
blocks product delphi13:blocks

REM Show details for multiple versions at once
blocks product delphi12 delphi13

REM View package info
blocks view owner.package@1.2.0
blocks view owner.package /versions

REM Manage repository sources
blocks config sources
blocks config /add sources=https://github.com/owner/my-repo
```

## Install

Downloads, compiles and registers a Delphi package into the active
Delphi installation. The package can be specified by id (`vendor.name`)
or by name; ambiguous names prompt for selection.

```
Usage: Blocks install <package> [options]

Arguments:
  <package>              Package id (vendor.name) or package name.
                         Append @<constraint> to specify a version constraint (e.g. owner.pkg@1.2.0,
                         owner.pkg@^1.2.0, owner.pkg@>=1.0.0).

Options:
  /overwrite             Overwrite the project directory if it already exists.
  /silent                Skip non-critical interactive prompts (use defaults).
  /force                 Skip dependencies that conflict with the requested constraint
                         instead of raising an error, using the already-installed version.

Examples:
  Blocks install owner.package
  Blocks install owner.package@1.2.0
  Blocks install owner.package@^1.2.0 /force
  Blocks install package /silent
```

## Build

Recompiles and re-registers a package that is already installed, reusing the
sources already present in the workspace (no download). The package must have
been installed first with `blocks install`.

```
Usage: Blocks build <package> [options]

Arguments:
  <package>              Package id (vendor.name) or package name.

Options:
  /silent                Skip non-critical interactive prompts (use defaults).

Examples:
  Blocks build owner.package
  Blocks build package /silent
```

## Update

Updates an already-installed package to a newer version and recompiles the
packages that depend on it — directly **and transitively** (in Delphi their DCUs
are tied to the version they were compiled against). With no version it proposes
the highest release within the installed major version (interactively, unless
`/silent`); append `@<version>` to target a specific one — a downgrade is allowed
too.

Before updating, two compatibility checks run and report **all** problems found:

- **Downward** — the new version's dependencies against what is installed. A
  missing dependency is fine (it will be installed); a present-but-incompatible one
  is a problem.
- **Upward** — the installed packages that depend on this one, against the new
  version's number.

If any problem is found the update is **refused** and the workspace is left
untouched: uninstall or update the conflicting packages listed first, then retry.
This guarantees the workspace never ends up in an invalid state.

Once the checks pass, the currently installed version is **uninstalled first**
(so version-suffixed artifacts, the IDE design-time registration and the DCU
folder of the old version are not left behind), then the new version is installed
and every dependent is recompiled in dependency order.

```
Usage: Blocks update <package> [options]

Arguments:
  <package>              Package id (vendor.name) or package name.
                         Append @<version> to target a specific version.

Options:
  /silent                Skip the version prompt, taking the proposed version.

Examples:
  Blocks update owner.package
  Blocks update owner.package@2.0.0
```

## Uninstall

Removes a previously installed package: deletes its project directory
and the corresponding entry from the local database.

```
Usage: Blocks uninstall <package> [options]

Arguments:
  <package>              Package id (vendor.name) or package name.

Example:
  Blocks uninstall owner.package
```

## Init

Creates the `.blocks\` directory in the current folder, selects the target
Delphi version, and downloads the remote package repository.
Run this once per workspace before using install.

```
Usage: Blocks init [options]

Options:
  /product <version>     Target Delphi version (e.g. delphi12, delphi13).
                         If omitted, you will be prompted to choose.
                         Run "Blocks product" to see valid values.
  /registrykey <key>     Registry profile key (default: BDS).
                         Use this when Delphi is started with -r <key>.
  /source <url>          Package source(s) to use instead of the default.
  /sources <url>         Alias of /source. Separate multiple sources with commas.
  /platforms <list>      Comma-separated platforms to target (e.g. Win32,Win64).
                         If omitted, you will be prompted to choose; selecting
                         none targets all platforms supported by the version.

Examples:
  Blocks init
  Blocks init /source https://github.com/owner/repo
  Blocks init /sources https://github.com/a/r1,https://github.com/b/r2
  Blocks init /product delphi13 /platforms Win32,Win64
```

## List

Lists all packages installed in the current workspace. The Delphi version is read from the workspace configuration (set during init).

```
Usage: Blocks list

Example:
  Blocks list
```

## Product

Shows Delphi/RAD Studio installations detected in the Windows registry. Use the version name shown here as the `/product` argument for other commands.

```
Usage: Blocks product [name[:regkey]...] [options]

Options:
  /all                   Show all supported Delphi versions instead of installed ones.
  /detail                Show all properties for each installed product.

Examples:
  Blocks product
  Blocks product /all
  Blocks product /detail
  Blocks product delphi12
  Blocks product delphi12:blocks
  Blocks product delphi12 delphi13
```

The **running status** checks the actual `bds.exe` command line: a profile opened with `bds.exe -r blocks` is only shown as running for the `blocks` registry key, not for `BDS` or any other profile.

With `/detail` (or when filtering by name), only **active platforms** are listed — those for which a platform SDK is configured (`Win32` and `Win64` are always active; others require a matching SDK entry under `PlatformSDKs` in the registry).

## Search

Searches the local repository index by id, name, description and keywords. The match is case insensitive and looks for any substring.

```
Usage: Blocks search [pattern]

Arguments:
  [pattern]              Substring to look for; omit to list all packages.

Examples:
  Blocks search json
  Blocks search
```

## Config

Reads or writes workspace or system configuration values. See
[Configuration](config.md) for a detailed description of every key.

```
Usage: Blocks config [/add | /delete] [/system] [<key>[=<value>] ...]

Arguments:
  <key>                  Print the current value of the given key.
  <key>=<value>          Set the key to the given value.

Options:
  /add                   Append the value instead of replacing it (for list keys).
  /delete                Remove the value from a list key (for list keys).
  /system                Read or write system-level config (Windows registry) instead of
                         workspace config.

Workspace keys:
  sources                Comma-separated list of repository URLs used by "init".
                         After changing this key, run "Blocks init" to refresh
                         the local repository.
  platforms              Comma-separated platforms this workspace targets (e.g.
                         Win32,Win64). Empty means all platforms supported by the
                         Delphi version. Supports /add and /delete.
  product                Target Delphi version name (e.g. delphi12, delphi13).
  registrykey            Registry profile key for the target Delphi IDE (default: BDS).
  updatedcpsearchpath    When true, "init" adds the blocks DCP output directory to the
                         Delphi library Search Path (true/false, default: false).
                         After changing this key, run "Blocks init" to apply.
  toolarchitecture       Compiler tools architecture MSBuild uses (Delphi 13+):
                         default (don't pass the flag), x32 (32-bit tools) or
                         x64 (64-bit tools, more memory). Default: default.
                         Does not change the produced binary.

System keys:
  InstallPath            Specifies the directory containing the blocks.exe to launch
                         when multiple installations are present. This key is only
                         available when Blocks was installed using the setup package
                         and requires the launcher to function.

Examples:
  Blocks config
  Blocks config sources
  Blocks config sources=https://github.com/owner/my-repo
  Blocks config /add sources=https://github.com/owner/other-repo
  Blocks config /delete sources=https://github.com/owner/other-repo
  Blocks config product
  Blocks config platforms=Win32,Win64
  Blocks config /add platforms=Win64
  Blocks config /delete platforms=Win64
  Blocks config registrykey=myprofile
  Blocks config updatedcpsearchpath=true
  Blocks config toolarchitecture=x64
  Blocks config /system InstallPath
  Blocks config /system InstallPath=C:\Tools\Blocks
```

## View

Shows details of a package from the local repository.

```
Usage: Blocks view <id[@version]> [options]

Arguments:
  <id[@version]>         Package id; optional @version selects a specific version
                         (latest is used when omitted, e.g. owner.package or owner.package@1.2.0).

Options:
  /raw                   Print the raw manifest JSON instead of the formatted summary.
  /versions              List all available versions of the package.

Examples:
  Blocks view owner.package
  Blocks view owner.package@1.2.0
  Blocks view owner.package@1.2.0 /raw
  Blocks view owner.package /versions
```

## Version

Prints the version number of the blocks executable.

```
Usage: Blocks version

Options:
  /silent                Show only the version number.

Example:
  Blocks version
  Blocks version /silent
```

## Upgrade

Checks GitHub for a newer release of blocks and, if one is found,
downloads and launches the setup package.

```
Usage: Blocks upgrade [options]

Options:
  /check                 Only check whether a newer version is available; do not download.
  /force                 Download and install even if the current version is already up to date.

Examples:
  Blocks upgrade
  Blocks upgrade /check
  Blocks upgrade /force
```

## Help

`blocks help` prints the [Overview](#overview) shown at the top of this page. Pass a command name to get the detailed help for that command, e.g. `blocks help install`.
