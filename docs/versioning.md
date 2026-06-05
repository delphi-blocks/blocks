# Versioning and Dependencies

Blocks keeps **every published version** of a package in the repository and uses
[Semantic Versioning](https://semver.org/) to decide which one to install and to
resolve dependencies between packages.

## Multiple versions

In the repository each package is stored under one folder per version:

```
.blocks/repository/<vendor>/<name>/
  1.0.0/
  1.2.0/
  2.0.0/
```

You can list the versions available for a package with:

```
blocks view owner.package /versions
```

When you install a package, Blocks selects the **highest version that satisfies
the given constraint**. If no constraint is given, the highest available version
is used.

```bat
REM Highest available version
blocks install owner.package

REM Highest version that satisfies the constraint
blocks install owner.package@^1.2.0
```

## Version format

Versions are `MAJOR.MINOR.PATCH` integers (e.g. `1.4.2`). Shorter forms are
accepted and the missing parts default to `0` — so `1` means `1.0.0` and `1.2`
means `1.2.0`.

> A fourth `BUILD` field (e.g. `1.4.2.7`) is also **supported but discouraged**.

Versions are compared field by field: `MAJOR` first, then `MINOR`, then `PATCH`,
then `BUILD`.

## Version constraints

Append `@<constraint>` to a package id to pin or restrict the version. The
supported syntaxes are:

| Constraint        | Meaning                                            | Matches (example)              |
|-------------------|----------------------------------------------------|--------------------------------|
| `@1.2.0`          | Exact version.                                     | only `1.2.0`                   |
| `@^1.2.0`         | Compatible: `>=1.2.0 <2.0.0`.                      | `1.2.0`, `1.9.9` — not `2.0.0` |
| `@~1.2.0`         | Same minor: `>=1.2.0 <1.3.0`.                      | `1.2.0`, `1.2.7` — not `1.3.0` |
| `@>=1.0.0`        | At least `1.0.0`.                                  | `1.0.0`, `2.5.1`               |
| `@<2.0.0`         | Below `2.0.0`.                                     | `1.9.9` — not `2.0.0`          |
| `@>1.0.0` / `@<=1.0.0` | Strictly greater / less-or-equal.             | —                              |
| `@>=1.0.0 <2.0.0` | Explicit range (space = logical AND).              | `1.4.0` — not `2.0.0`          |
| `@1.*` / `@1.2.*` | Wildcard: any patch (or any minor) of the prefix.  | `1.*` → `1.7.3`                |
| `@*` or empty     | Any version.                                       | anything                       |

Notes:

- An exact constraint matches the **full** version, so `@1.2` matches only
  `1.2.0` (use `@1.2.*` for any `1.2.x`).
- The caret allows changes that do not modify the left-most non-zero field. For
  `0.x` versions this means the minor (or patch) takes the role normally played
  by the major, because `0.x` releases are considered unstable: `@^0.2.0`
  resolves to `>=0.2.0 <0.3.0`, and `@^0.0.3` to `>=0.0.3 <0.0.4`.

> **`cmd.exe` caret escaping** — In `cmd.exe` the `^` character must be doubled
> (e.g. `owner.package@^^1.2.0`). In PowerShell no escaping is needed.

## Dependencies

A manifest can declare other packages it needs in the `dependencies` map, each
with its own version constraint:

```jsonc
"dependencies": {
  "paolo-rossi.delphi-neon": "^3.1.0",
  "owner.other":             ">=1.0.0 <2.0.0"
}
```

When you install a package, Blocks resolves its dependencies **first**,
recursively: every dependency is installed (and its own dependencies in turn),
each resolved to the highest version matching its constraint, before the package
itself is compiled. Every manifest in the dependency tree is therefore installed
in its own right.

### Conflicts and already-installed packages

For each package Blocks checks what is already recorded in the local database
(`.blocks/<version>-database.json`):

- **Already installed and the version satisfies the constraint** → the install
  is skipped (nothing to do).
- **Installed version does not satisfy the constraint** → Blocks reports a
  *version conflict* and stops, so it never silently replaces a version another
  package may depend on. Pass `/force` to log a warning and continue instead.

This keeps a workspace consistent: a single version of each package is shared by
everything that depends on it.
