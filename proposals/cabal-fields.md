# Extract a `Cabal-fields` package for the `.cabal` field-parsing layer

## Summary

Split the low-level cabal-file-format layer — lexing and parsing a byte string
into `[Field Position]` — out of `Cabal-syntax` into a new, focused, lower-layer
package `Cabal-fields`. `Cabal-syntax` depends on `Cabal-fields` and re-exports
the moved modules, so its public API is unchanged and no downstream package
needs edits.

## Motivation

`Cabal-syntax` bundles the raw field-format lexer/parser together with the
much heavier value parser, the `GenericPackageDescription` type system, and
the pretty-printing machinery. Tools that only need to read the *structure*
of a `.cabal` (or `cabal.project`) file — formatters, linters, editor/IDE
integrations, project-file readers — must today depend on all of `Cabal-syntax`
and its full dependency closure.

A focused `Cabal-fields` package:

- lowers the dependency footprint for consumers that only need field parsing
- makes the field-format parser reusable independently of the Cabal type system
- clarifies the layering (a clean lower layer with a small, well-defined surface)
- removes `Distribution.Compat.Prelude` from that layer

## Proposed Change

Create a new package `Cabal-fields` containing the field-format layer. The
natural seam is

```haskell
readFields  :: ByteString -> Either ParseError [Field Position]
readFields' :: ByteString -> Either ParseError ([Field Position], [LexWarning])
```

which are pure and independent of the higher-level parse monad.

- **Moves into `Cabal-fields`:** the field AST, lexer, parser and pretty-printer
  (`Distribution.Fields.{Field, Lexer, LexerMonad, Parser, Pretty}`) and
  the supporting position/source/warning types, which are renamed into the
  same namespace — `Distribution.Parsec.{Position, Source, Warning}` become
  `Distribution.Fields.{Position, Source, Warning}` so the whole package
  lives under `Distribution.Fields.*`. It also includes a small non-exposed
  helper module (verbatim copies of `showToken`/`showTokenStr`/`fromUTF8BS`)
  so the package avoids depending on the heavy `Distribution.Pretty` /
  `Distribution.Utils.Generic`.
- **`Cabal-fields` drops `Distribution.Compat.Prelude`** in favour of explicit
  imports and depends only on `base, bytestring, containers, array, binary,
  deepseq, parsec, pretty, text, filepath`.
- **`Cabal-syntax` depends on `Cabal-fields`** and re-exports the eight moved
  modules via `reexported-modules`, so every existing import path keeps working.
- **Stays in `Cabal-syntax`:** the `Distribution.Fields` umbrella,
  `Distribution.Fields.ParseResult`, `Distribution.Fields.ConfVar`,
  `Distribution.Parsec.Error`, `Distribution.Parsec.FieldLineStream`, and the
  `Parsec` class — these depend on `Version`, which transitively pulls in the
  `Parsec` class and `Distribution.Pretty`, and so cannot move into a *focused*
  lower layer.
- **Consumer entry point:** `Distribution.Fields.Parser` (which re-exports the
  AST types and `readFields`/`readFields'`). A dedicated `Distribution.Fields`
  umbrella is intentionally *not* added to `Cabal-fields`, because that module
  name is occupied by `Cabal-syntax`'s richer umbrella (which also bundles
  `ParseResult`/`PError`); reclaiming it would require changing `Cabal-syntax`.

## Alternatives Considered

- **Move the whole `Distribution.Fields.*` hierarchy** (including `ParseResult`
  and `ConfVar`): rejected — those need `Version`, which would drag the
  value-parsing and pretty machinery into the new package and defeat the
  "focused" goal.
- **Clean break (no re-exports; migrate all in-tree consumers to import from
  `Cabal-fields`):** more churn for no immediate benefit. Re-exports preserve
  compatibility now; consumers can migrate to `Cabal-fields` directly later.
- **Do nothing:** leaves the dependency footprint and layering unchanged.

## Backwards Compatibility / Migration

Fully backwards compatible. `Cabal-syntax` re-exports all moved modules —
including the renamed `Distribution.Fields.{Position, Source, Warning}` under
their former `Distribution.Parsec.{Position, Source, Warning}` names (via
`reexported-modules ... as ...`) — so existing imports compile unchanged;
`Cabal`, `cabal-install`, and the test suites build with no source edits. The
change requires adding the new package to the build/release tooling (project
package lists, `cabal.bootstrap.project`) and publishing it to Hackage.
Consumers that want only field parsing can optionally depend on `Cabal-fields`
directly in future.

## Interested parties

- Cabal / cabal-install maintainers and contributors.
- Authors of `.cabal` tooling that only needs field parsing (formatters such
  as `cabal-fmt` / `stylish-cabal`, linters, HLS and other editor integrations,
  project-file readers).

These parties have not yet been contacted; this would happen during the
discussion period.

## Implementation Notes

A working implementation already exists. It is essentially a pure code move:
`Cabal-fields` builds standalone (with no dependency on `Cabal-syntax`),
and `Cabal-syntax`, `Cabal`, and `cabal-install` all build with no source
edits, the `Cabal-tests` parser suite passing (190/190). Alongside the move
it also drops the dead `CABAL_PARSEC_DEBUG` lexer/parser code, ships an
implementation-independent grammar reference (`GRAMMAR.md`) plus module-level
Haddock with doctests, and registers the package for the bootstrap build. I
am willing to submit the PR; the remaining work is mostly release coordination
(versioning and Hackage upload of the new package).

## Open Questions

- **Naming:** `Cabal-fields` vs alternatives (`Cabal-syntax-fields`,
  `cabal-file-parser`, …)?
- **Shared helpers:** keep the small UTF8/token helpers duplicated internally
  (current approach), or factor them into a shared low-level utility package?
- **Versioning/release policy** for the new package (track `Cabal-syntax`'s
  version line?).

## References

- Design spec: https://github.com/andreabedini/cabal/blob/4e1fcc2c72b3756e7b30912d48d052923fe75cf6/docs/superpowers/specs/2026-06-15-cabal-fields-extraction-design.md
- Implementation plan: https://github.com/andreabedini/cabal/blob/4e1fcc2c72b3756e7b30912d48d052923fe75cf6/docs/superpowers/plans/2026-06-15-cabal-fields-extraction.md
- Implementation: https://github.com/andreabedini/cabal/tree/extract-cabal-fields
