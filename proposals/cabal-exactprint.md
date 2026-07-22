# Cabal Exactprint


## Summary

blah blah

## Motivation

blah blah

## Proposed Change

We propose to leverage the existing `Field ann` data type, as well as the `Parsec` and `Pretty` classes and their instances to implement
Cabal Exactprint.

Before starting, we modify the cabal lexer and field parser's definition to retain comments.
Currently Cabal doesn't store any of the comments. This is already implemented. <!-- Cite it -->

Firstly, we implement exact printing `[Field ann]`. That is, `exactRenderFields . readFields = id` should hold.
This method is chosen for its flexibility. As long as we respect the invariants of `[Field ann]` during modification,
unchanged parts in the output should stay the same, and changed parts should be local.

Secondly, we implement a modification/addition/removal framework to facilitate building modification functions.
A notable wish in the original meta thread <!-- TODO: quote it --> is about being able to programmatically modify cabal files.
With this mechanism, we expose a typed way to modify cabal files that only changes the part that has been touched.
Unmodified parts of the file stayes the same thanks to exaprint.
We will use the `Parsec` and `Pretty` to implement the typed modification framework.
Each field in a Cabal file is represented as a field name in association with a some field lines.
Upon modification, we proceed with the following steps:
- Should the field lines be non empty, join them into a single field line `fl`.
- Run the `Parsec` instance of a desired type `τ` on the joined field lines `fl`, obtain the data `p` these field lines represent.
- Run the user's transformation function `t` on `p`, obtaining `p'`.
- Run the `Pretty` instance of `τ` to obtain a new textual representation `fl'`.
- - Should the field be multiple (e.g. `build-depends` or `license-files`),
     For each item `it`, we swap out the old textual represent with the new one, using the location of `it` provided by the parser.
     This solves the problem of in-field trivia, such as comma placement and redundant parenthesis in `build-depends`.\
  - Otherwise, we replace the entire string.
- Run modifications similar to this until no more is needed.
- Traverse all fields that has been modified to correct lines that have been mooved.
  - If a field `f` is pushed below due to addition before `f`, we increment the line number accordingly.
  - If a field `f` is pulled up due to removal before `f`, we can either do nothing (leaving empty lines before `f`) or decrement the line number accordingly.
  Modification is be a hybrid of addition and removal.

These two tasks can be implemented somewhat independently.

<!--
Do we use TTG for nested types ?
I don't think so, but if we want to be perfectionist it can be cosidered.
-->

We want to allow the user to describe a single modification (here-below named `Edit`) by specifying a focus and a transformation.
Here we add a new dependency `myNewDep` as an example.
This can be described as "within the section library with no arguments [^1], within the field `build-depends`, add (append) a `myNewDep."

In pseudo Haskell of the API we intend to build:
```haskell
addDependency :: Edit
addDependency =
  ModifySection
    -- focus on a section
    (hasSectionName "library" <> hasSectionArgument [])
    -- don't transform the section name nor arguments
    id
    -- transform nested fields or sections
    $ AddField
        -- focus on a field, creat it should it not exist
        (hasFieldName "build-depends")
        -- inject a new dependency into the list of dependencies
        (addFieldLinesListLike @Dependency myNewDep)

addFieldLinesListLike :: forall t. (Parsec t, Pretty t) => t -> ([FieldLine Position] -> [FieldLine Position])
```

Interpreting all the foci of a `Edit` tree describes a set of paths down the tree of fields.
At the leaf (in the above example, `AddField`) we help user build a function that modifies `[FieldLine Position]`
by providing `addFieldLinesListLike`.

## Alternatives Considered

<!-- TODO: list the four approaches we have considered -->

TriviaTree

Barbie / TTG

TypedFields


## Backwards Compatibility / Migration

<!-- Does this change affect backwards compatibility? What migration path is needed? -->

<!-- Do we use TTG for nested types? -->

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
