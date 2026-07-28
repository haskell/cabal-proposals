// This source file is used to generate ./cabal-exactprint.md using pandoc,
// so the references are kept in sync in a coherent format.

// Pandoc doesn't seem to support bibliography files
#let mk-smartlink(url, name) = (
  get-link: link(url)[#name],
  override-name: new-name => link(url)[#new-name],
)
#let references = (
  // implementations
  comment-parser-pr: mk-smartlink(
    "https://github.com/haskell/cabal/pull/11252",
  )[Retain comments in field parser \#11252],

  trivia-tree: mk-smartlink(
    "https://github.com/haskell/cabal/pull/11425",
  )[TriviaTree \#11425],

  barbie-trees-that-grow: mk-smartlink(
    "https://github.com/haskell/cabal/pull/11690",
  )[Barbie/Trees-that-grow \#11690],

  typed-fields: mk-smartlink(
    "https://github.com/leana8959/cabal/tree/typed-fields",
  )[Typed-fields leana8959/cabal/typed-fields],

  cabal-add-project: mk-smartlink(
    "https://github.com/Bodigrim/cabal-add",
  )[cabal-add],
  cabal-fmt-project: mk-smartlink(
    "https://github.com/phadej/cabal-fmt",
  )[cabal-fmt],
  hpack-project: mk-smartlink("https://github.com/sol/hpack")[hpack],
  autopack-project: mk-smartlink(
    "https://github.com/kowainik/autopack",
  )[autopack],
  hls-project: mk-smartlink(
    "https://github.com/haskell/haskell-language-server",
  )[haskell-language-server],

  transform-fields: mk-smartlink(
    "https://github.com/leana8959/cabal/tree/transform-fields",
  )[Transform-fields leana8959/cabal/transform-fields],

  // proposals
  jappie-original-twg-proposal: mk-smartlink(
    "https://github.com/haskellfoundation/tech-proposals/pull/65",
  )[Jappie's original Haskell Foundation Tech Proposal],

  jappie-original-cabal-proposal: mk-smartlink(
    "https://github.com/haskell/cabal-proposals/pull/5",
  )[Jappie's original Cabal Proposal],

  // misc
  exact-printer-mega-issue: mk-smartlink(
    "https://github.com/haskell/cabal/issues/7544",
  )[Exact-printer Mega-issue \#7544],

  // documentation, references, papers
  package-description-documentation: mk-smartlink(
    "https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html#package-descriptions",
  )[Cabal manual/Package Descriptions],

  project-description-documentation: mk-smartlink(
    "https://cabal.readthedocs.io/en/stable/cabal-project-description-file.html#project-description-cabal-project-file",
  )[Cabal manual/Project Descriptions],

  biparsers: mk-smartlink(
    "https://dl.acm.org/doi/full/10.1145/3704910",
  )[Biparsers: Exact Printing for Data Synchronisation],

  barbie-haskell-library: mk-smartlink(
    "https://hackage.haskell.org/package/barbies-2.1.1.0",
  )[Barbie library],

  trees-that-grow: mk-smartlink(
    "https://www.cs.tufts.edu/comp/150FP/archive/simon-peyton-jones/trees-that-grow.pdf",
  )[Trees that Grow],
)


= Cabal Exactprint

Note that this proposal builds on the earlier
#(references.jappie-original-twg-proposal.override-name)[TWG (Technical Working Group) proposal],
also succeeds #references.jappie-original-cabal-proposal.get-link to match the updates in our
approach.

== Summary

The Cabal Exactprint project aims to develop a precise parsing and printing tool for package
descriptions in the cabal library.

This will allow both cabal and other tools to introduce deltas into package descriptions through a typed API,
simplifying the modification/addition/removal of fields, without mangling the format, structure or comments of users files.

Furthermore it makes cabal authoritative on the package description format, allowing downstream
users to use the provided printing functions and get a stability guarantee.

We define the parse-print idempotency to be `print . parse == id`, which reads "parsing then
printing is as if we've done nothing". We only focus on ensuring this property to hold for valid
package descriptions, and we don't consider the braces syntax in this work.

== Motivation

Cabal builds packages by following stanzas written in #(references.package-description-documentation.override-name)[package descriptions].
These files have the extension `.cabal`. Cabal is currently unable to modify such files loselessly.

Here are some of the symptoms manifesting in different ways through out the Cabal CLI:

- `cabal format`

  It should fix the indentation of your file and canonicalize some fields.
  Instead, it also drops all your comments, all the imports are merged in-place, elif in a
  conditional will be desugared to a nested if in an else, etc.

- `cabal add`

  Cabal should be able to add a dependency to a component. The Rust language's cabal equivalent,
  `cargo`, does this just fine.
  This can't be implemented in Cabal yet because modifying a portion of the package description's in-memory representation
  mangles the entire package description, similar to `cabal format`.

- Missing module declaration

  When a module is needed but is not declared in the package description, Cabal can't add it for you.
  Again, because cabal would mangle the package description if it tries to touch it.
  It can only tell you that it's missing. Argh.

- `cabal gen-bounds`

  Cabal is very helpful and can generate dependency constraints ("bounds") for you.
  However, it just dumps them in the terminal, because it can't modify the package description.


Cabal is also not authoritative in this matter, many projects have been created to do what cabal
can't:

- #references.cabal-fmt-project.get-link, a formatter.
- #references.cabal-add-project.get-link, an non-official implementation of `cabal add` command.
- #references.hpack-project.get-link, an alternative to package description.
- #references.autopack-project.get-link, automatic module discovery.

== Proposed Change

We propose to leverage the existing `Field ann` data type, as well as
the `Parsec` and `Pretty` classes and their instances to implement Cabal Exactprint.

As a preliminary task, we modify the cabal lexer and field parser's
definition to retain comments. Currently Cabal doesn't store any of the
comments. This is already implemented in #references.comment-parser-pr.get-link which is yet to be merged.

Firstly, we implement exactprinting from `[Field ann]`. That is,
`exactRenderFields . readFields = id` should hold, serving `[Field ann]`
as the concrete syntax tree (CST). We chose it as the CST for its
flexibility. As long as we respect its invariants during modification,
unchanged parts in the output should stay the same, and changed parts
should translate to local transformation in the output string. In our
current prototype, we are already able to roundtrip 119662 out of 194557
package descriptions of hackage (\~60%) with #(references.transform-fields.override-name)[an implementation that is concise and simple] #footnote[
  To run this implementation to see for yourself:

  - Clone the branch at this commit https://github.com/haskell/cabal/commit/00a79443390c3a28c911c91b2d8c2f432e09c05c
  - Run the following in your terminal
    ```bash
    Cabal-tests:hackage-tests --test-option="field-roundtrip"
    ```
]. The review will also be easy thanks to the small diff.
To increase the percentage of successful roundtrip, we need to detect CRLF/LF and exactprint accordingly;
furthermore, we can't figure out whether a whitespace was a tab or a space yet. These will require
changes to the lexer which we have previously done in #references.comment-parser-pr.get-link.

Secondly, we implement a modification/addition/removal framework to
facilitate building modification functions. A notable feature request in #references.exact-printer-mega-issue.get-link
is about being able to programmatically modify package descriptions. With this
mechanism, we expose a typed way to modify package descriptions. For example,
translating `SpecVersion -> SpecVersion` to `[FieldLines ann] -> [FieldLines ann]`,
which allows the user to modify the `cabal-version`
field while having all the position validation already dealt with behind
the scenes.

We will use the `Parsec` and `Pretty` classes to implement the typed
modification framework. Each field in a package description is represented by a
field name in association with some field lines. Upon modification, we
proceed with the following steps:

+ Should the field lines be non empty, join them into a single field
  line `fl` with indentation and newlines.

+ Run the `Parsec` instance of a desired type `τ` on the joined field
  lines `fl`, obtain data `p` which these field lines represent.

+ Apply user's transformation function `t` on `p`, obtaining `p'`.

+ Run the `Pretty` instance of `τ` on `p'` to obtain a new textual
  representation `fl'`.

+ We replace the entire `fl` with `fl'`.

+ Traverse all fields that has been modified to correct line numbers that have
  been moved.
  + If a field `f` is moved down due to addition before `f`, we
    increment the line numbers of `f` and its following siblings
    accordingly.
  + If a field `f` is moved up due to removal before `f`, we can either
    do nothing (leaving empty lines before `f`) or decrement the line
    numbers of `f` and its following siblings accordingly.
  + Modification is be a hybrid of addition and removal.

+ Run modifications similar to this until no more is demanded.

+ Validate that the new data is parsable and parses to the transformed value.

The above steps would not allow modifying list like values such as `[Dependency]`, especially
that cabal allows having more than one comma separated item in a list to be on the same line,
there's no bijection between fieldline and the individual item parsed.

To achieve precise and local change to a single item in a list,
we extend the algorithm in the following ways, using `Dependency` an example:

+ Instead of parsing `Located [Dependency]` where we obtain a single location the start of the
  entire list, we parse `[Located Dependency]` to obtain a location on each item.

+ Considering the user might only want to modify an item, the user's transformation function
  can be typed as `Dependency -> Maybe Dependency` where `Maybe` indicates that the dependency
  should be rerendered.

+ We only operate on changed `Dependency`.
  Given the location of a `Dependency` and the its transformed counterpart, refer to its source position
  and swap out the old representation with the new representation.
  Each change of an item is hence local and composable.

The extended algorithm doesn't cover the use case of adding new dependencies to the front
or the end of the dependency list, or sorting the list.
To do so, one can use the original algorithm for single values.
// TODO: this would format the entire list, but at the same time if you were to sort
// where sometimes there are more than one on a singleline, you might as well just mangle the entire
// field.
// Note that the rest of the file will still be untouched. The change will be scoped to a Field
// instead of a fieldline item.
// `foo, bar
// baz`

Exactprint and the modification framework can be implemented and tested
independently.

To validate an exactprint implementation, we test the property
`exactRenderFields . readFields = id` against Hackage; to validate a
modification framework implementation, we add golden tests for different
cases to ensure that important invariants of `[Field ann]` are preserved,
namely that `Position` of fields are not overlapping.

We want to let user describe a single modification that we call `Edit`
by specifying a focus and a transformation. Here we add a new dependency
`myNewDep` as an example. This modification can be expressed in plain
English as "within the section library with no arguments #footnote[In
  cabal, sections can have arguments. If-else conditions are actually
  sections where the condition is the single argument, and `library` is a
  section that can take a library name as a section argument.], within
the field `build-depends`, add (append) `myNewDep`." In pseudo Haskell
of the API we intend to build the aforementioned example modification
can be described as:

```haskell
appendDependency :: Edit
appendDependency =
  ModifySection
    -- Focus on a section.
    (hasSectionName "library" <> hasSectionArgument [])
    -- Don't transform the section name nor arguments.
    -- This mechanism can be useful to implement transformation on if conditions.
    id
    -- Transform nested fields or sections.
    $ AddField
        -- Focus on a field, create it should it not exist.
        (hasFieldName "build-depends")
        -- Inject a new dependency into the list of dependencies.
        (addFieldLinesListLike @Dependency myNewDep)

-- A helper function that adds a given thing into a list of 'FieldLine Position'.
addFieldLinesListLike :: forall t. (Parsec t, Pretty t) => t -> ([FieldLine Position] -> [FieldLine Position])
```

The set of all the foci of a `Edit` tree describes a set of matching
paths down the tree of fields. At the leaf (in the above example,
`AddField`) we help user build a function that modifies
`[FieldLine Position]` by providing `addFieldLinesListLike`.

We strive to make the API flexible and will expose ways to modify
`[Field Position]` directly. We don't try to guarantee the correctness of this
escape hatch, however we provide validation functions to catch problems.

== Alternatives Considered

Below is an exhaustive list of the changes we tried in chronological
order since september 2025 and what I learned from these attempts.

- #(
    references.trivia-tree.override-name
  )[Trivia Tree \#11425 (proof of concept)]
  implements a untyped tree `TriviaTree` using existential type.

  With it, we can imtate the shape of a recursive type `τ` freely and
  construct the same shape but with annotation as nodes. Constructing
  and destructing `τ` guides us to store/read annotations accordingly.
  This has the benefit of not duplicating all types we want to annotate,
  but due to its existential type nature, it is very easy to get things
  wrong and parsers/printers lose their roundtrip guarantee during
  composition.

- #(
    references.barbie-trees-that-grow.override-name
  )[Barbie/Trees-that-grow \#11690 (proof of concept)]
  tries to do the same thing as Trivia-tree in a typed way.

  We draw inspiration from ghc-exactprint and its trees that grow model,
  annotating data structurally on each extension point. Reaching the end
  of the design space of this approach with just enough fields
  implemented to make two package description from Hackage roundtrip 100%, inherent
  problems of using `GenericPackageDescription` as CST to implement
  exactprint started to catch my eyes. This is the first successful
  approach where syntactic roundtrip property of `Pretty`/`Parsec` are
  preserved with composition. The details of the inherent problems will
  be mentioned later in details.

From then, I started experimenting using `[Field Position]` as the CST
to implement Cabal Exactprint.

- #references.typed-fields.get-link

  Rereading the original #references.exact-printer-mega-issue.get-link,
  I realized that a big part of the demand was to modify
  `[Field Position]` in a typed way which doesn't necessarily need GPD.
  To allow typed modification in the fields, we extended the `Field`
  data type to have more constructor (the goal was one per known cabal
  field).

  This attempt proved that modifying or printing `[Field Position]` (or
  something isomorphic to it) is a lot easier. The shape of the field syntax
  is not lost and better reflects what was originally written. Also we
  would avoid threading everything through field grammar, which proved
  to be unwieldy.

  However, this resulted in the `FieldLine` bearing a too specific type
  for the field grammar and casting will be necessary, rendering the
  specific type information of each field useless for later parsing. It
  can only be a exactprint implementation and won't benefit other parts
  of Cabal-syntax.

=== "Trivia-Tree"

`TriviaTree` is an open recursive type implemented using existential
type. + To construct a `TriviaTree` node, the constructor can be applied
on data `p` along with its associated trivia, and optionally the trivia
of `p`'s children.

- To deconstruct a `TriviaTree` node, a function is provided to try to
  retrieve the associated trivia given some data `p`. We use the `Eq`
  instance to lookup in the trivia tree. This is internally implemented
  with `Data.Map`.

  Should the trivia exist, it will be returned, along with the
  `TriviaTree` that are children to `p` for further lookup using the
  data within `p`.

As long as the construction and the deconstruction matches up, the
trivia can be successfully recovered.

Inspired by #references.biparsers.get-link,
trivia tree is passed around along the data. Each parser is extended to
return a pair `(p, t)` where `p` is the data parsed and `t` is the
associated `TriviaTree`. The printer is extended to receive `(p, t)` to
print the data `p` with its associated `TriviaTree` `t`.

This model was appealing because it would allow us to maintain the same
amount of fields in each constructor of a type that should support
Cabal Exactprint, supporting backwards compatibility.

Trivia trees are poor in structural composition. Let's describe the
exactprint invariant as for a given `inp` and a type `τ`,
`(print @τ . parse @τ) inp == inp`. This reads as "parsing `inp` as `τ`
and then printing it results to the same string". Some subnodes
satisfying the exactprint invariant doesn't guarantee that building from
these nodes will lead to a bigger node that also satisfy the exactprint
invariant. This is because a structural "off-by-one" (e.g.~applying one
unnecessary constructor or forgetting to unwrap one level of
`TriviaTree`) can lead to not finding any trivia. We can't tell if some
trivia is missing because the TriviaTree was constructed incorrectly,
deconstructed incorrectly, or if that node doesn't have trivia to begin
with. During implementation there was a lot of "dumping the AST to see
where I messed up" in the construction or elimination of `TriviaTree`.
The engeerning cost was too high.

TriviaTree is also plagued with the `Newtype` idiom that Cabal uses
liberally. "Ala" parser methods in field grammar are often written in a
`f :: Type -> Type` context, and `f` is then instantiated to `Identity`
or some other wrapper type (e.g.~`SpecVersion` for `CabalSpecVersion`)
to redirect the `Parsec`/`Pretty` instance used. This doesn't work well
with the trivia tree model at all, which is designed to associate a data
with its surrounding trivia. We use the data to lookup in the trivia
tree. With newtypes, it is unsure whether we save/look up trivia with
the #emph[`pack`ed] data or the #emph[`unpack`ed] data, and any
incoherence will not be caught by the type checker but manifest as no
trivia during lookup. To make matters worse, field grammar uses
`Newtype` as type level parser/printer combinators. `List sep b a` is a
good example. Applying this `Newtype` changes the parsec to parse zero
or more `a`, using the `Newtype` `b`. Field grammar interacts with
newtypes over the `Newtype b a` class, not knowing the multiplicity of
the newtype used makes the lookup idea of trivia tree even more
convoluted to implement.

In hope for more correctness while constrained to only make
backwards-compatible changes, Jappie proposed draw inspiration from
Barbie.

=== "Barbie/Trees-that-grow"

#references.barbie-haskell-library.get-link is
a pattern that parameterizes a data declaration with a higher kinded
type parameter (commonly `f :: Type -> Type`). By leveraging this type
parameter, we can share the spine of the data type but have each leaf in
a different context.

This is somewhat what we wanted: annotating each leaf. As for
backwards-compatibility, we wanted to use the `TypeFamilies` extension
to conditionally return the same type, keeping the unannotated type
completely identical to existing implementation. Also, not using trivia
trees frees us from looking up, so `Newtype`s no longer bother us
despite the types becoming really nasty.

Here's an example of using this method to encode the
`targetBuildDepends :: MonoidalFieldAla Dependency` field of
`BuildInfo`. `Dependency` is a normal Cabal type.

```haskell
-- | Toggle whether a GPD component has annotation or not.
data ParsingPhase
  = {-| Concrete syntax tree -} Conc
  | {-| Abstract syntax tree -} Abst

-- Return identical type if not annotated.
type family IfConc (m :: ParsingPhase) (f :: Type -> Type) (a :: Type) where
  IfConc Abst _ a = a
  IfConc Conc f a = f a

type MonoidalFieldAla (m :: ParsingPhase) (a :: Type) =
  IfConc m List
    ( IfConc m ( (,,) [Comment Position] BS.ByteString )
        ( IfConc m ((,) Positions) a
        )
    )
```

After refining the idea, it ended up being quite similar to the famous
#references.trees-that-grow.get-link idiom used in GHC to implement ghc-exactprint.

A bearable albeit major inconvenience is constraints. In the existing
codebase there are some adhoc transformations done for
backwards-compatibility. For example, license-file and license-files are
both parsed to a list of licenses, concatenated and then inserted into
`GenericPackageDescription`. To make this still work with trees that
grow annotation, it requires adding a constraint saying that the
annotated licenses still form a Monoid, making the already long
constraint tuple even longer. See
#link(
  "https://github.com/haskell/cabal/blob/b498d6a911509e6dade136cfbeaad30ad9382b78/Cabal-syntax/src/Distribution/PackageDescription/FieldGrammar.hs#L585-L605",
)[before]
and
#link("https://github.com/leana8959/cabal/blob/a91c3fe5d5f0f01c350cc938a8d0c8460d452031/Cabal-syntax/src/Distribution/PackageDescription/FieldGrammar.hs#L552-L590")[after];.

A notable problem is we lose the shape of the original
`[Field Position]`. Components of `GenericPackageDescription` don't know
the section they belong to, and each data don't know which `FieldLine`
of which `Field` they were originally parsed from. This was previously
not known because the limitation of trivia tree didn't allow us to go
this far.

- Regarding losing the shape of the sections:

  In a package description, it is possible to have trivia for each section as
  well. The library stanza "library" is normalized to lower case in
  Cabal, but to achieve 100% roundtrip, we need to be able to save the
  original string (which I call _cased name_). Worse, cabal
  doesn't parse a simple component but a component wrapped in a
  conditional tree `CondTree`. `Library` is represented in a suboptimal
  way where non-conditional fields such as library name is nested within
  `CondTree`. The stop-gap solution would be to insert a
  `Maybe ByteString` that is the original cased name into the parsed
  library only at the top level of the `CondTree`.

- Regarding losing the shape of a field:

  `monoidalField` fields parses things that are monoids and merges them
  during parsing. This means that the following two cabal fields have
  exactly the same meaning.

  ```cabal
  build-depends: foo, bar
  ```

  ```cabal
  build-depends: foo
  build-depends: bar
  ```

  In order to remedy this, we store the position of the field name
  position (where "build-depends" occurs) as a trivia, in association
  with each element of the dependency list. During pretty printing, it
  suffices to group items of the dependency list by the field name
  position to which they belong to reconstruct the grouping. The
  positioning issue is also solved this way, two birds one stone.

  A variant such problem is the adhoc concatenation of different fields
  for backwards-compatibility. `license-file` and and `license-files`
  are both valid fields. In fact, they both accept zero or more than one
  license file, and the final parse is the concatenation of the two
  fields. This requires marking from which field the data comes
  originated, so at printing time we can recover what was originally
  written.

To demonstrate the added complexity of "losing the shape of `[Field ann]`"
caused by using `GenericPackageDescription`, we use
the previous definition of `MonoidalFieldAla` as example.
It is the same as the two following definition albeit generic in `ParsingPhase`.
You can see that in the `Abst`ract case, we maintain backwards-compatibility at type level.
```haskell
type MonoidalFieldAlaConc a = [ ([Comment Position], BS.ByteString, (Positions, a)) ]
type MonoidalFieldAlaAbst a = a
```

From outside to inside, `MonoidalFieldAlaConc` represents the bookkeeping of the following structure:

- We maintain everything in a list to remember which field a `build-depends` belongs to. This is
  because `build-depends` can be merged. Each item in this list will be referred to as a _group_.

- Each group (which was a field) has its associated comments from the original fieldlines.

- The ByteString here represents the original cased name of Fields. The user could've written
  `BuIlD-DePenDs` and we would need to restore it despite this string looks very funny.

- `Positions` is a product type, describing the field's position this group is associated to, as
  well as the position of the first field line `a` was originally found when represented as a string.
  This is the direct consequence of duplicating the Field's information to the leaf, because the
  field itself is not representable in `GenericPackageDescription`.

These problems illustrate that while it is possible to implement
Cabal Exactprint using `GenericPackageDescription` as CST, it is not a
good fit because it would require copying the information on all non
terminals of `[Field Position]` to all the leaves (i.e.~sections to
`GenericPackageDescription` components and monoidal fields that will be
merged to parsed `FieldLine`s).

This lead to the development of a new family of attempts based on
transforming the `Field Position` directly, without going to and from
`GenericPackageDescription`. The latest attempt of this family is the
approach described in this proposal.

=== Typed-Fields

`Field ann` represents either a field with its string content or a
section that has many fields. We want to use this type as CST while
allowing typed modification that people were hoping for in the original
thread.

The idea is to create a `TField ann` (typed field) data type that has a
constructor for each of the fields that cabal supports. Each of the
field will bear the value of the parsed type that its corresponding
field has.

This was an interesting idea, but it would be a type that is only used
for Cabal Exactprint. Field grammar finds a field by its string name.
While in `TField` we retain the original field name, the value we get
out of it will be typed. In other words, the type of the value we get
from a TField depends on which field name it is. This lead to opening
the box of pandora called dependent sum and dependent map, which was
soon closed due to the complexity it bears. It wouldn't be possible to
use template haskell in Cabal-syntax to generate `GEq` and `GOrdering`
instances due to it being a GHC boot library. Writing these instances by
hand will also be tedious due to the size of the pattern match being
quadratic to the size of the constructor, which is the amount of cabal
fields we support.

== Backwards Compatibility / Migration

We are extending the parser and implementing a modification framework.
The changes are local to the parser, we don't foresee any backwards-compatibility issues.


== Interested parties

As outlined in #references.exact-printer-mega-issue.get-link,
this would benefit the functionality of Cabal itself many ways, namely
the following:

- New command `cabal add` that adds a dependency automatically by
  editing the package description.
- `cabal gen-bounds` can modify the bounds of a package description.
- `cabal format` can format a package description in a canonical way while
  preserving comments.
- `cabal init` can leverage the "addition" part of the modification
  framework and generate package description easily.

It would also benefit existing programs that depend on Cabal:

- #references.cabal-add-project.get-link

  It has three strategies to add dependencies that are tried in
  sequence. All of the strategies use parsed fields to guide stringy
  manipulation directly within the source file. In comparison
  Cabal Exactprint will allow users to manipulate `[Field ann]`
  instead. Or, even better, we should be able to implement cabal-add in
  cabal directly.

- #references.cabal-fmt-project.get-link

  It parses the package description twice: once with `readFields` from cabal, and
  again with its own parser to find all the comments. This can be
  simplified the new `readFieldsWithComments` in #references.comment-parser-pr.get-link.

- Eventually #references.hls-project.get-link will be able to generate
  code actions to modify cabal files.

This work would also simplify implementation of formatters or modification tools operating on
other formats using the same envelope format, namely #(references.project-description-documentation.override-name)["project descriptions"].

== Implementation Notes

#references.jappie-original-twg-proposal.get-link has been accepted and funded by the Haskell Foundation.
Under the Haskell Foundation's funding since september 2025, I have tried to
implement and iterate on the previous proposal. Due to the design evoving
drastically over time, this is the most up-to-date proposal describing
our ideas after refining them after a year.

I will continue to work on this myself under the funding of the Haskell Foundation.

== Open Questions
We are still investigating if describing it is possible or beneficial to
describe the modification API in terms of lens.

== References
#list(..references.values().map(x => x.get-link))
