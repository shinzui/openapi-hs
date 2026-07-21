# ADR 0001: Use lens and own the ordered-container implementation

- Status: Accepted
- Date: 2026-07-21

## Context

`openapi-hs` historically exposed accessors for both `lens` and `optics`. Its insertion-ordered
maps and sets came from `insert-ordered-containers`, which itself depended on `optics`. That
made the optics stack part of every user's build plan even when users consumed only the lens
API.

Insertion order is observable package behavior: it keeps generated OpenAPI documents
deterministic. The ordered map also has package-specific JSON object encoding, and both
containers participate in the public API. Replacing them with ordinary hash containers would
therefore change behavior rather than merely remove dependencies.

## Decision

`Data.OpenApi.Lens` is the only accessor API. `Data.OpenApi.Optics` is removed, and surviving
indexed container instances use the classes exported by `Control.Lens`. The supported lens
line is `lens >=5.3.3 && <5.4`. The lower bound is verified with GHC 9.12.4; on GHC 9.14.1,
upstream `template-haskell` bounds make `lens-5.3.6` the first release in that range that
resolves.

The three required ordered-container modules are maintained in this repository, derived from
the released `insert-ordered-containers-0.3.0` source:

- `Data.HashMap.InsOrd.Compat.Internal` and
  `Data.HashMap.Strict.InsOrd.Compat.Impl` are hidden implementation modules behind the existing
  public `Data.HashMap.Strict.InsOrd.Compat` wrapper.
- `Data.HashSet.InsOrd.Compat` is public because OpenAPI record types expose its
  `InsOrdHashSet` type.

Vendored code retains provenance comments. The complete upstream BSD-3-Clause notice is kept
verbatim in `LICENSES/insert-ordered-containers-BSD-3-Clause.txt` and is included in source
distributions.

Vendoring is behavior-preserving. In particular, the released set `union` implementation's
index-bound behavior is retained even though a union that adds a right-hand member can make
`valid` return `False`. A separate change may fix that behavior after compatibility impact is
reviewed; callers can normalize today with `fromHashSet . toHashSet`.

## Consequences

The dependency plan no longer contains `optics-core`, `optics-extra`, `optics-th`,
`indexed-profunctors`, or `insert-ordered-containers`. Ordered iteration and JSON output remain
deterministic and are covered by direct characterization tests.

This is a source-breaking change released as `openapi-hs-5.0.0`. Optics users must migrate to
the lens accessors. Code importing the upstream ordered-map or ordered-set modules must import
the corresponding `.Compat` module instead. Reverse-dependent rehearsals are release gates so
these package-boundary changes are verified before publication.

Owning the implementation also means future upstream fixes are not inherited automatically.
Any synchronization must compare against an authoritative release, preserve the license, and
run the ordered-container behavior suite before changing the vendored code.

## Alternatives considered

- Keeping both accessor libraries would preserve source compatibility but would not achieve an
  optics-free dependency plan.
- Replacing insertion-ordered containers with `HashMap` and `HashSet` would lose deterministic
  traversal and encoding.
- Continuing to depend on `insert-ordered-containers` would leave the unwanted transitive
  dependencies in place; Cabal cannot select only the package's non-optics modules.
