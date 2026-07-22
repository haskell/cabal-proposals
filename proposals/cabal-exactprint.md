# Cabal Exactprint


## Summary

blah blah

## Motivation

blah blah

## Proposed Change

We propose to leverage the existing `Field ann` data type, as well as the `Parsec` and `Pretty` instances to implement
Cabal Exactprint.

Here are two tasks that complement each other and can be worked on somewhat independently:
- Implement exact printing `[Field ann]`. That is, `exactRenderFields . readField = id` should hold.

- Implement a modification/addition/removal algebra. A notable wish in the original meta thread <!-- TODO: quote it -->
  is about being able to programmatically modify cabal files.
  With this mechanism, we expose a typed way to modify cabal files that only changes the part that has been touched.
  Unmodified parts of the file stayes the same thanks to exaprint.

## Alternatives Considered

<!-- TODO: list the four approaches we have considered -->

TriviaTree

Barbie / TTG

TypedFields


## Backwards Compatibility / Migration

<!-- Does this change affect backwards compatibility? What migration path is needed? -->

Some types need to be extended in TTG style (c.f. Depedency)

## Interested parties

<!-- Who are the interested parties in the broader Haskell community? Have you contacted them? -->

Users of cabal, cabal-add, etc.

## Implementation Notes

<!-- Are you willing to implement this yourself? What is the expected timeline? -->


## Open Questions

<!-- Are there any unresolved questions or areas needing further input? -->

Desired API.

## References

<!-- Links to related issues, discussions, or previous work. -->

Link to
- cabal-add
- cabal-fmt
- cabal-gild

- my four attempts
