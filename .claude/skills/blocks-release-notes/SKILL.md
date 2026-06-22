---
name: blocks-release-notes
description: Generate the release notes for the latest tag of this project. Use after a release tag has just been created to produce a CHANGELOG-<version>.md file describing the changes since the previous tag, written from the user's point of view.
---

# Release notes

Generate a release-notes file for the most recent release tag of this repository.

## When to use

Run this after creating the tag for a new release (e.g. `v0.7.0`). The skill
diffs the new tag against the previous one and writes the notes to a file.

## Steps

1. **Find the two tags.** Do not hardcode any version — always resolve them from git.
   - Latest tag (the one just created): the most recent tag by creation date.
   - Previous tag: the tag immediately before it.
   ```bash
   LATEST=$(git tag --sort=-creatordate | head -1)
   PREV=$(git tag --sort=-creatordate | sed -n '2p')
   ```
   If there is no previous tag, use the repository's first commit as the lower bound.

2. **Collect the changes** between the two tags. Read the commit messages and,
   when a message is not self-explanatory, the diff stat to understand what
   actually changed.
   ```bash
   git log --stat "$PREV".."$LATEST"
   ```

3. **Write the notes** to a file named `CHANGELOG-<version>.md` in the `docs`
   directory, where `<version>` is the latest tag **without the leading `v`**
   (e.g. tag `v0.7.0` → file `docs/CHANGELOG-0.7.0.md`).

## Output file format

- The top heading states the range, using the **previous and the latest tag**:
  `# Changes from <PREV> to <LATEST>` (e.g. `# Changes from v0.6.1 to v0.7.0`).
- Group entries under the sections that apply — omit a section if it is empty:
  - `## New Features`
  - `## Improvements`
  - `## Bug Fixes`
- Each entry is a bullet. Start a feature/improvement with a short **bold lead-in**,
  followed by an em dash and the description.

## Writing style

- **English.**
- **User's point of view.** Describe what the change does for the person using
  the tool, not how it is implemented. Avoid internal details such as source-file
  names, JSON keys, class names or config file names unless they are part of the
  CLI the user actually types.
- **Impersonal voice.** Do not address the reader with "you can …"; phrase things
  impersonally (e.g. "the selection can be changed with …", "a workspace can now
  target …").
- Keep it concise: one bullet per user-visible change. Merge a release/version-bump
  commit into the others — it is not a change on its own.

## Example

A well-formed result. Note how implementation-only changes are dropped (a commit
that only refactors internals into a typed class is not a user-visible change),
and how internal names are replaced with what the user perceives:

```markdown
# Changes from v0.6.1 to v0.7.0

## New Features

- **IDE experts from scripts** — manifest scripts gain two new commands:
  `compile`, to build an additional project, and `expert`, which compiles a
  package and registers it as a design-time IDE expert. Experts are unregistered
  automatically on uninstall.
- **POSIX & Apple platforms** — multi-platform packages now build, install and
  uninstall cleanly on POSIX targets (including OSX64) and on Apple platforms
  (macOS/iOS), where the correct platform binary is produced.
- **Custom package location** — a package can declare the folder it lives in, so
  it no longer has to sit at the repository root.
- **`$(VAR)` macro syntax** — script arguments support the new `$(VAR)` macro
  form; the older `%VAR%` syntax keeps working for backward compatibility.

## Improvements

- **Per-platform library paths** — the package's `.dcp` search path is now
  registered for every configured platform, not just Win32/Win64.
- **Cleaner uninstall** — uninstall now skips platforms that cannot be built and
  removes the package's compiled output.

## Bug Fixes

- Corrected the list of POSIX platforms (OSX64 is now included).
- POSIX packages are now uninstalled correctly.
- Packages without a description no longer fail to register; they show as
  `(Untitled)`.
```
