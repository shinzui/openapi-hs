---
name: release
description: Release the openapi-hs package to Hackage following PVP
argument-hint: "[major|minor|patch]"
disable-model-invocation: true
allowed-tools: Read, Bash, Edit, Glob, Grep, Write, AskUserQuestion
---

# openapi-hs Release Skill

Release the **`openapi-hs`** package to Hackage following the Haskell PVP.

This is a **single-package** repository: `openapi-hs.cabal` at the repo root.
The `example` executable and the `spec` test-suite are components of that same
package — they ride along inside the sdist and are **not** published separately.
Nothing else is uploaded to Hackage.

## Versioning Strategy

The Haskell PVP version format is `A.B.C.D`:

- `A.B` is the **major** version — bump for breaking API changes (removed or
  renamed exports, changed types, changed semantics).
- `C` is the **minor** version — bump for backwards-compatible API additions
  (new exports, new modules, new instances).
- `D` is the **patch** version — bump for bug fixes, docs, internal-only
  changes, and performance improvements.

A single git tag — the **bare version number** (e.g. `4.0.0`), with **no `v`
prefix** — marks each release. This matches the fork's 3.x/4.x convention; the
older `v*` tags predate the fork and are not the pattern to follow.

## Arguments

`$ARGUMENTS` is optional:

- `major`, `minor`, or `patch` — forces the bump level.
- If omitted, infer the bump level from the changes (see step 2).

## Steps

### 1. Determine what changed since the last release

- Read the current version from `openapi-hs.cabal` (the `version:` field).
- Find the latest fork release tag. The current series uses bare version tags;
  resolve the most recent one with:
  `git tag --list | grep -E '^[0-9]' | sort -V | tail -1`.
- Run `git log --oneline <last-tag>..HEAD` to list commits since the last
  release. (If that tag was never created — e.g. the current cabal version was
  bumped in a prep commit but never tagged — use the previous released tag.)
- If there are no releasable commits since the last tag, tell the user there is
  nothing to release and stop.

Present a summary showing:

- Current cabal version
- Last release tag (or "none")
- Number of commits since the last release
- A short digest of those commits

### 2. Determine the next version using PVP

Rules:

- If `$ARGUMENTS` is `major`, `minor`, or `patch`, use that bump level.
- Otherwise analyze the commits to choose the bump:
  - "breaking", "remove", "rename", "change type", a `!`/`BREAKING CHANGE` →
    **major**
  - "add", "new", "feat", "export" → **minor**
  - "fix", "docs", "refactor", "chore", "internal", "perf" → **patch**
- Present the proposed bump to the user and ask for confirmation before
  proceeding.

Increment the version (`A.B.C.D`):

- **major**: increment `B`, reset `C` and `D` to 0 (e.g. `4.0.0` → `4.1.0`,
  written as `4.1.0` or `4.1.0.0` to match the existing field's arity).
- **minor**: increment `C`, reset `D` to 0 (e.g. `4.0.0` → `4.0.1`).
- **patch**: increment `D` (e.g. `4.0.0` → `4.0.0.1`).

> Keep the version arity consistent with how the cabal file currently writes it
> (the current `version:` is `4.0.0`). PVP treats a trailing `.0` as equal, so
> `4.1.0` and `4.1.0.0` are equivalent — just be consistent across the cabal
> file, the tag, and the changelog.

### 3. Update the version and changelog

#### Version update

- Edit `openapi-hs.cabal` to set the new `version:`.

#### Changelog update

`CHANGELOG.md` (repo root) uses a header-underline format with **no dates** and
**no "Unreleased" section** — each entry is the version on its own line, an
underline of dashes, then a bullet list. Match that exactly. For example:

```
4.1.0
-----

- Added foo to `Data.OpenApi.Bar`.
- Fixed quux roundtripping [#NN](https://github.com/shinzui/openapi-hs/pull/NN).

4.0.0
-----
...
```

- Add the new version section **above** the previous top entry.
- Summarize the commits since the last release as bullets. Lead with
  **Breaking** changes (prefix with `**Breaking:**`) when the bump is major,
  then new features, then fixes, then other changes. Only include what applies.
- Keep the existing entries untouched below the new section.

Show the user **all** changes (the version bump and the changelog entry) for
review before committing.

### 4. Verify (mandatory gates)

Run these and **stop on the first failure** — do not proceed to commit or
publish if any gate fails:

- `nix fmt` — format with treefmt (fourmolu + cabal-fmt + nixpkgs-fmt). Run
  this before `nix flake check`, since the treefmt check will fail on
  unformatted files.
- `nix flake check` — runs the treefmt and pre-commit gates.
  - `nix` evaluates the **git tree**, so any newly created/edited files must be
    `git add`-ed before they are visible to the check.
  - The flake exposes `checks` / `devShells` / `formatter` (no
    `packages.default`), so `nix flake check` is the right gate here.
- `cabal build all` — verify the library, the `example` executable, and the
  `spec` test-suite all compile.
- `cabal test` — run the `spec` suite; it must pass.

### 5. Commit, tag, and push

- Stage `openapi-hs.cabal` and `CHANGELOG.md`.
- Create a single commit using a Conventional Commits message:
  `chore(release): <new-version>`. The body should summarize what's in the
  release and justify the chosen bump.
- Create an **annotated** tag with the **bare version** (no `v`):
  `git tag -a <version> -m "Release <version>"`.
- Push the commit and the tag: `git push && git push --tags`.

### 6. Publish to Hackage

`cabal check` is a mandatory gate here — run it first and stop on failure.

1. `cabal check` — verify there are no packaging issues.
2. `cabal sdist` — build the source distribution tarball.
3. `cabal upload --publish <tarball-path>` — publish the sdist to Hackage.
   (Run `cabal upload <tarball-path>` first for a candidate dry-run if you want
   to inspect it on Hackage before the irreversible `--publish`.)
4. `cabal haddock --haddock-for-hackage --haddock-hyperlink-source --haddock-quickjump`
   then `cabal upload --publish --documentation <docs-tarball-path>` — publish
   the Haddock documentation.
5. Report the Hackage URL:
   `https://hackage.haskell.org/package/openapi-hs-<version>`.

### 7. Create the GitHub release

After the Hackage upload succeeds, create a GitHub release for the tag:

```bash
gh release create <version> --title "<version>" --notes "$(cat <<'EOF'
## Hackage

https://hackage.haskell.org/package/openapi-hs-<version>

## What's Changed

<the new section's bullets from CHANGELOG.md>
EOF
)"
```

- Use the new `CHANGELOG.md` section for the notes body.
- Include the Hackage link so the package is easy to find.
- Report the GitHub release URL when done.

## Important

- Always ask the user to confirm the version bump and the changelog entry
  **before** committing. The commit and tag are created only after approval.
- Run `nix fmt` before committing so `nix flake check` passes.
- Never skip the gates: `nix flake check`, `cabal build all`, `cabal test`, and
  `cabal check`. If any fails, **stop** and report the error rather than
  continuing.
- Publishing to Hackage with `cabal upload --publish` is **irreversible** —
  confirm the tarball and version before running it.
- Tag with the bare version number (no `v` prefix), annotated.
