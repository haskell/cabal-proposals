# Community Project Cabal Exact Printer

Note that this proposal builds on the earlier TWG (Technical Working Group)
proposal: https://github.com/haskellfoundation/tech-proposals/pull/65
requested by Matthew: https://github.com/haskell/cabal/issues/11227#issuecomment-3590108400
It has been substantially updated to reflect implementation experience and the barbies approach.

## Summary

The Exact Printer project aims to develop a precise parsing and printing tool for .cabal files in the cabal library.
This will allow both cabal and other tools to modify cabal files without
mangling the format, structure or comments of users files.
Furthermore it makes cabal authoritative on the cabal file format
allowing downstream users to use the provided printing functions
and get a stability guarantee.

## Motivation

Currently if you build a project with an extra module not listed in your cabal file,
GHC emits a warning:
```
<no location info>: error: [-Wmissing-home-modules, -Werror=missing-home-modules]
    These modules are needed for compilation but not listed in your .cabal file's other-modules: 
        X
```

You'd say, why doesn't cabal just add this module to the cabal file?
Well, it can't.
Cabal is currently only able to parse Cabal files, 
it can print them back out, but in a mangled form.

There are other programs providing module detection, 
but nothing is integrated in cabal itself.
This problem has been solved by the community, several times outside of cabal.
For example:
+ [hpack](https://github.com/sol/hpack)
+ [autopack](https://github.com/kowainik/autopack)
+ [cabal-fmt](https://github.com/phadej/cabal-fmt)
+ [gild](https://taylor.fausak.me/2024/02/17/gild/)

Of course many of these projects do more than just module expansion.
hpack provides a completely different cabal file layout for example,
`cabal-fmt` and `gild` are formatters for cabal files.
Only auto-pack just does this one feature.
However, since all these programs implement this functionality
in their own distinct way,
there is clearly demand for it.

There are more issues than just module expansion however.
For example [cabal gen-bounds](https://github.com/haskell/cabal/issues/7304) could modify a cabal file in place,
with [cabal edit](https://github.com/haskell/cabal/issues/7337) we could add a dependency via cli, 
[cabal init](https://github.com/haskell/cabal/issues/6187) could be simplified.

The current implementation of printing in cabal via the `cabal format` command, has the following issues:

1. It Deletes all comments [^1]
2. It merges any `common` stanza into wherever it was imported. https://github.com/haskell/cabal/issues/5734
3. It changes line ordering.
4. It changes spacing (although perhaps to be expected from a formatter)

[^1]: Andreas helped me solve this on zurich hack.

A similar problem occurs when HLS want's to do any modification to a cabal
file during development.
For example if a module was added or renamed, or if a (hidden) library is required.
Or perhaps some function used in a known library via Hoogle for example.
HLS has no clue what to do,
because even if it links against the cabal library,
there is no function to modify a generic cabal representation and print a cabal file that keeps
it similar to the users'.

The goal is to make non invasive changes to cabal files.
This tech proposal therefore aims to address all these issues.
Furthermore by bringing it directly into cabal we can enforce the round tripping
property.
This will ensure clients of the Cabal library can print cabal files more
easily and have some stability guarantees.

Why even bother with adding this directly to cabal? 
What advantage do existing tools get by making cabal smart enough
to modify it's own files?
It's hard to guarantee stability across projects if many functionalities
are distributed across many projects.
For example a newly introduced tool called [cabal-add](https://github.com/Bodigrim/cabal-add), would need to take into account any 
syntax change to cabal, *forever*. 
This is true for other tools as well that want to modify cabal files (such as HLS).
If cabal would support an exact printer all syntax odds and ends
will remain within cabal allowing us to change the cabal file format easily
without breaking downstream libraries and tools.
This is because cabal would supports parsing and printing,
and exposes this capability as library functions.
This will allow downstream programmers to parse and print 
cabal files without having to care about the syntax details.
Furthermore it'll make it easier for programmers to add new cabal related tools.
Which is different from the current situation where some diligent programmers 
assumed the entire cabal file format is stable, 
and write their own own parsers and printers.
So every tool that want's to modify cabal files has a larger maintenance
burden because cabal isn't doing this upstream.

An example of how a program to add dependencies to the main library could look:
```haskell
main :: IO ()
main = do
    theFile <- BS.readFile "my.cabal"
    dependName <- mkPackageName <$> getLine
    let (warns, eDescription) = runParseResult $ parseGenericPackageDescription theFile
    case eDescription of
      Left someFailure ->
        error $ "failed parsing " <> show someFailure
      Right generic ->
        let
          depends = mkDependency dependName anyVersion (NES.singleton LMainLibName)
          modified = generic { condLibrary = fmap addDep (condLibrary generic) }
          addDep tree = tree { condTreeData = addDepToLib (condTreeData tree) }
          addDepToLib lib = lib { libBuildInfo = addDepToBI (libBuildInfo lib) }
          addDepToBI bi = bi { targetBuildDepends = depends : targetBuildDepends bi }
        in
        Text.writeFile "my.cabal" $ exactPrint modified
```
We are not modifying any of the exact print metadata.
The exact printer is smart enough to add new lines if necessary and relatively shift everything below upon line addition.

All the difficulty lies in figuring out where to place a dependency;
we made a decision here to do it in the main library assuming it exists.
We also assumed there would be no conditionals.
These are the questions a program that adds dependencies should ask a user,
and the `GenericPackageDescription` type guides the programmer in asking the right questions.
`GenericPackageDescription` is more strongly typed than `Field`:
there is no low-level syntax mangling going on at all,
because the functions exposed in the cabal library take care of that for us.

#### Example: adding an exposed module

As a second example, here is how a tool could add an exposed module to the main library:
```haskell
addExposedModule :: ModuleName -> GenericPackageDescriptionAnn -> GenericPackageDescriptionAnn
addExposedModule modName gpd =
    gpd { condLibrary = fmap addMod (condLibrary gpd) }
  where
    addMod tree =
      let lib = condTreeData tree
       in tree { condTreeData = lib { exposedModules = modName : exposedModules lib } }
```
This is the kind of operation that `cabal-add` or HLS could use.
The caller only manipulates typed Haskell values;
the exact printer handles all formatting and position bookkeeping.

## Proposed Change

This proposal want's to add a function to the cabal library:

```haskell
printExact :: GenericPackageDescription -> Text
```

Which will do exact printing.
This function has the following properties:

Byte-for-byte roundtrip of all Hackage packages:
```haskell
  forall (hackagePackage :: ByteString) . (printExact <$> parseGeneric hackagePackage) == Right hackagePackage
```

The byte-for-byte roundtrip property holds where `hackagePackage` is a cabal package found on Hackage.

We explored two approaches.
The namespace (trivia-tree) approach works but progress was slow because:
+ Figuring out why something is missing from the trivia tree is hard.
+ The trivia tree creates large golden tests which are hard to read.
+ Monoidal fields would work more easily because we no longer have to figure out which field was used to recreate provenance.

We therefore developed the in-tree annotated (barbies) approach described below,
which is now the primary design.
The namespace approach is kept here for historical context.

### Namespace approach (explored earlier under the TWG (Technical Working Group) proposal)
To support exact printing a new type can wrap `GenericPackageDescription`, called `AnnotedGpd`:

```haskell
data AnnotatedGpd {
 , unAnnotatedGpd :: GenericPackageDescription 
 , exactComments :: ExactPrintMeta
 }
```
We can return this from the parser.
This contains the data we just don't need in cabal
proper, but do need for printing like comments:

```haskell
data ExactPrintMeta = ExactPrintMeta
  { exactComments :: Map Position Text
  }
```
Implementation example is here: https://github.com/haskell/cabal/pull/11252/changes#diff-99cd3111ed91eea7db1e3b8b3c20eb2cf7999840c2f161ffdd36943b10cff71dR19

If we store comments like this it would be easy to add multiline comments as well,
because now we don't have to intercalate everything with comments.

### In-tree annotated (barbies)
This is the latest design which is quite different from the original
TWG proposal: https://github.com/haskellfoundation/tech-proposals/blob/main/proposals/0000-cabal-exact-printer.md#technical-content

The current implementation lives on the [`gpd-barbie`](https://github.com/leana8959/cabal/tree/gpd-barbie) branch.

**Goal.** We want to annotate `GenericPackageDescription` with exact-print data (positions, surrounding whitespace, comments)
while keeping the existing API backwards compatible.
Inspired by the [barbies](https://hackage.haskell.org/package/barbies)
package, we parameterise the data types with a phantom type-level tag
and use type families to conditionally include or exclude annotations.

#### Core type machinery

A `HasAnnotation` kind selects between two modes:

```haskell
data HasAnnotation = HasAnn | HasNoAnn

type family AnnotateWith (trivia :: Type) (m :: HasAnnotation) (a :: Type) where
  AnnotateWith t HasNoAnn a = a          -- plain: just the value
  AnnotateWith t HasAnn  a = Ann t a     -- annotated: value wrapped with trivia
```

When `m ~ HasNoAnn`, the type family reduces to the bare value,
so `GenericPackageDescriptionWith HasNoAnn` is identical to the old `GenericPackageDescription`.
When `m ~ HasAnn`, values gain trivia wrappers.
There are additional type families for attaching positions and preserving field grouping,
but the core idea is this single conditional wrapper.

We use a closed type family with two equations rather than a type class or open type family.
Because the kind `HasAnnotation` has exactly two constructors,
the two equations are exhaustive and GHC can reduce them fully at every use site.
A `TypeError` catch-all is not needed:
any type applied at kind `HasAnnotation` is either `HasAnn` or `HasNoAnn`,
so there is no third case to reject.

#### Trivia types

The annotation data lives in a `Trivia` wrapper:

```haskell
data SurroundingText = SurroundingText String String  -- leading and trailing whitespace

data Positions = Positions
  { fieldNamePos :: Position   -- position of the field name
  , fieldLinePos :: Position   -- position of the field value
  }

data Trivia t
  = HasTrivia t                -- carries concrete whitespace / position data
  | ExactRepresentation String -- store the original source text verbatim
  | IsInserted                 -- value was programmatically added (not in source)
  | NoTrivia                   -- no metadata available

data Ann t a = Ann { getAnn :: Trivia t, unAnn :: a }
```

The `IsInserted` constructor is how the printer knows a value was added by a tool
and needs to be pretty-printed from scratch rather than reproduced from source text.

#### Parameterised GPD

The top-level type is parameterised once; type aliases preserve the old name:

```haskell
type GenericPackageDescription    = GenericPackageDescriptionWith HasNoAnn
type GenericPackageDescriptionAnn = GenericPackageDescriptionWith HasAnn

data GenericPackageDescriptionWith (m :: HasAnnotation) = GenericPackageDescription
  { packageDescription :: PackageDescriptionWith m
  , gpdScannedVersion  :: AnnotateWith Positions m (Maybe Version)
  , genPackageFlags    :: [PackageFlagWith m]
  , condLibrary        :: Maybe (CondTree ConfVar (LibraryWith m))
  , ...
  }
```

The `m` parameter appears at every level, recursively parameterising the entire tree.
`PackageDescriptionWith m`, `PackageFlagWith m`, `LibraryWith m` all follow the same pattern.
`LibraryWith m` contains `BuildInfoWith m`, and that is where most of the field-level annotations live:

```haskell
data LibraryWith (m :: HasAnnotation) = Library
  { libName        :: LibraryName
  , exposedModules :: [ModuleName]
  , libBuildInfo   :: BuildInfoWith m
  , ...
  }

data BuildInfoWith (m :: HasAnnotation) = BuildInfo
  { buildable          :: AnnotateWith Positions m Bool
  , targetBuildDepends :: PreserveGrouping m (...)
  , ...
  }
```

When `m ~ HasNoAnn`, `AnnotateWith Positions HasNoAnn Bool` reduces to `Bool`
and `LibraryWith HasNoAnn` is just `Library` — nothing changes for existing code.
When `m ~ HasAnn`, fields gain `Ann` wrappers carrying positions and whitespace.

The parameterisation recurses through component types.
For example `LibraryWith m` contains `BuildInfoWith m`,
which in turn contains annotated fields:

```haskell
data BuildInfoWith (m :: HasAnnotation) = BuildInfo
  { buildable          :: AnnotateWith Positions m Bool
  , targetBuildDepends :: PreserveGrouping m
                            (AttachPositions m [AttachPosition m (Annotate m (DependencyWith m))])
  , ...
  }
```

When `m ~ HasNoAnn` the field `targetBuildDepends` reduces to `[Dependency]` (the current type).
When `m ~ HasAnn` it becomes `[(Positions, [( Position, Ann SurroundingText DependencyAnn)])]`,
carrying per-occurrence position and whitespace data.

#### Why this is better than the namespace approach

In the namespace (trivia-tree) approach, trivia is stored in a separate map keyed by position.
When a lookup into that map fails it could mean either "there is no trivia here" or "we made a mistake in the key".
These two cases are indistinguishable, making debugging hard.
The in-tree approach eliminates this ambiguity: trivia is either present in the `Ann` wrapper or the value is `IsInserted`.

Furthermore:
+ Golden tests are smaller because we no longer serialise a whole separate namespace tree.
+ Monoidal fields (fields that appear multiple times, e.g. `build-depends` in two conditionals) work naturally because each occurrence carries its own trivia.
+ The approach is backwards compatible: `GenericPackageDescription` (the `HasNoAnn` alias) has the same record fields as before.

#### Relationship to Trees That Grow

This approach is similar to [Trees That Grow](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/trees-that-grow.pdf),
although GPD is not an AST.
The key difference is that we use a single closed type family (`AnnotateWith`) rather than an open extension family per constructor.
This keeps the machinery simple and avoids the pattern-match exhaustiveness problems
that Trees That Grow can introduce in GHC's own codebase.

Concretely, for code that pattern-matches on GPD (such as `cabal check`):
+ When matching on `GenericPackageDescription` (i.e. `HasNoAnn`), all fields reduce to their current types.
  No code that only works with the non-annotated variant needs to change.
+ When matching on `GenericPackageDescriptionAnn` (i.e. `HasAnn`), the programmer additionally sees
  `Ann` wrappers and position tuples that they can inspect or ignore via `unAnn`.
+ The compiler still catches non-exhaustive patterns because the type families reduce fully;
  there are no extension constructors to add a wildcard for.

Knowing "at which line you are" is straightforward in the annotated variant:
every field and list element carries a `Position` (row, column) from parsing.

Change of the `GenericPackageDescription` must be possible for
+ module addition/removal
+ dependency addition/removal
+ library addition/removal

When a value is added programmatically it has no source position.
The `Trivia` constructor `IsInserted` marks these values;
the printer falls back to default pretty-printing for them
and relatively shifts everything below.
When a value is removed the printer omits it and adjusts following positions.

#### Comma and separator handling

A question raised in earlier reviews is whether commas in `build-depends` lists
are preserved when they can appear on either the preceding or following line.
The `Sep` type class has dual instances for `HasNoAnn` (which discards separator info)
and `HasAnn` (which preserves it).
For example, `parsecLeadingCommaListAnn` captures the comma and any surrounding whitespace
as `SurroundingText` trivia attached to the list element via `Ann`:

```haskell
parsecLeadingCommaListAnn p =
  P.optional comma >>= \case
    Nothing -> toList <$> P.sepEndByNonEmptyAnn lp comma <|> pure []
    Just c  ->
      let insertTriviaHead (x :| xs) = mapAnn (preTrivia c <>) x :| xs
       in toList . insertTriviaHead <$> P.sepByNonEmptyAnn lp comma
  where
    lp    = parsecSpacesAnn p
    comma = (:) <$> P.char ',' <*> P.spaces' P.<?> "comma"
```

The `SurroundingText` (leading and trailing whitespace strings) recorded per element
contains the comma character and surrounding spaces.
On printing, `applyTriviaDoc` replays the original text around each element.
This means leading-comma style, trailing-comma style, and mixed styles
are all preserved through a roundtrip.

#### Monoidal field merging

A question raised by @Bodigrim in [#11227](https://github.com/haskell/cabal/issues/11227#issuecomment-2863513015):
how do we distinguish two separate `build-depends` fields from one combined field?

```cabal
build-depends: base
build-depends: containers
```
vs.
```cabal
build-depends: base, containers
```

In the current GPD these are identical because monoidal fields are merged during parsing.
The barbies approach solves this with the `PreserveGrouping` type family.
When `m ~ HasNoAnn`, `PreserveGrouping HasNoAnn a` reduces to `a` (the merged list, as before).
When `m ~ HasAnn`, `PreserveGrouping HasAnn a` reduces to `[a]` — a list of per-occurrence groups.

So `targetBuildDepends` in `BuildInfoWith HasAnn` has type
`[(Positions, [(Position, Ann SurroundingText DependencyAnn)])]`.
Each outer list element corresponds to one `build-depends:` line in the source file,
and each inner list contains the dependencies on that line with their trivia.
This means we can always reconstruct how many `build-depends` fields there were
and which dependencies belonged to which.

#### Spaces inside version bounds

Another question from @Bodigrim: how are spaces within version bounds preserved?
For example, `base<5` vs `base    < 5` vs `base>=4   &&<  5`.

The barbies approach parameterises recursively: `DependencyWith m` contains `VersionRangeWith m`,
and `VersionRangeWith m` stores `SurroundingText` at each node of the version range expression.
The `SurroundingText` (a pair of leading/trailing strings) captures the exact whitespace
that appeared around operators and operands.
When printing, `applyTriviaDoc` replays these strings around the pretty-printed node,
reproducing the original spacing.

For programmatically inserted values (where there is no source text),
the `IsInserted` trivia constructor causes the printer to fall back to default formatting.

#### Relationship to other lossless parsing approaches

Several approaches to lossless parsing were discussed in [#11227](https://github.com/haskell/cabal/issues/11227):

+ **ruamel.yaml** (raised by @mpickering): the parser records extra info about whitespace and comments;
  the user edits the result; unchanged nodes are printed as before; changed nodes are printed fresh.
  The barbies approach follows this exact pattern.
  `HasTrivia` / `ExactRepresentation` preserves original formatting for unchanged nodes;
  `IsInserted` triggers fresh pretty-printing for new values.

+ **Rowan / Swift lib/Syntax** (raised by @ulysses4ever): these build a full Concrete Syntax Tree (CST)
  where every token (including trivia) is a node.
  Our approach is different: we annotate the existing abstract types rather than building a separate CST.
  This is pragmatic — cabal files are simpler than Haskell or Rust source,
  and we already have a working parser that produces GPD.
  Building a full CST would require a second parser or a major rewrite.

+ **GHC Exact Print Annotations** (raised by @Bodigrim): GHC attaches trivia to AST nodes via extension fields.
  Our approach is similar in spirit but simpler: GHC's syntax is much larger
  and uses open type families (Trees That Grow) which cause exhaustiveness issues.
  Our closed type family with two constructors avoids this.

+ **cabal-fields / Field-level manipulation** (raised by @mpickering referencing cabal-add):
  working at the `Field` level avoids touching GPD but loses type safety.
  See the "Why GPD rather than Field" section under Alternatives Considered.

#### Eliminating the namespace / side-table

The earlier namespace approach (discussed extensively in [#11227](https://github.com/haskell/cabal/issues/11227))
stored trivia in a side-table keyed by a `Namespace` path (e.g. `library.build-depends`).
@Bodigrim raised a fundamental problem: how do you key into this map unambiguously,
especially for monoidal fields and nested conditionals?

The barbies approach eliminates this problem entirely.
There is no side-table and no namespace keys.
Trivia lives directly inside each value via `Ann` wrappers.
Each `DependencyAnn` carries its own `SurroundingText`;
each field occurrence carries its own `Positions`.
There is nothing to look up and nothing to match back.

The overall goal would be to roundtrip 99% of all hackage packages.

#### Current roundtrip status

There is no roundtrip failure data yet because the barbies prototype does not roundtrip.
This is different from the earlier ZuriHac prototype which completely bypassed `FieldGrammar`
and could roundtrip basic files.
The barbies approach is much better integrated with the rest of cabal —
it threads annotations through `FieldGrammar` itself via dual `HasNoAnn`/`HasAnn` instances —
but this also makes modifying the field grammar the hardest part of the implementation,
since the type class has many methods and each needs both instances.
A first simple roundtrip test based on the barbies approach is expected soon.

### Exact printing
The `pretty` library doesn't have a newline primitive, and I find it hard to position elements exactly.

First, we traverse the `[PrettyField ann]` where `ann` allows us to retrieve exact `Position` information.
We use that to create a representation that uses relative placements. Using a relative positioning
makes layout easier, and works better when there are elements in the GPD that are programmatically
inserted.

To address this we created a custom minimal pretty printer in Cabal.
Notably, we need the following law, where `place` is a primitive in our relative version of Doc
algebra.
```hs
nest indent (place leadingEmptyLines leadingSpace doc) = place leadingEmptyLines leadingSpace doc
```
This would allow nesting to not influence the relatively placed elements.

## Alternatives Considered
This [issue](https://github.com/haskell/cabal/issues/7544) is tracked on the cabal bug tracker.
Essentially this proposal attempts to "solve" that issue.
As can be seen in the issue, there have been previous attempts.
these attempts have been fragmented, 
and no comprehensive solution has been finished. 
There is however a work in progress implementation of the [exact printer](https://github.com/haskell/cabal/pull/9436/).
The goal of this proposal is to buy time to finish that implementation.

The current work left to be done on this pull request is:
+ Add more comment preservation on more locations.
+ Deal with changes in generic package description.
   + We need to add tests about which changes we care about. 
     For example add a build field, add a field which causes comment overlap on x,y. 
     Delete a section, add a language flag, etc.
   + The algorithm just relatively shifts everything if you add
     a build field for example.
     You know something got added because you can't find it in `ExactPrintMeta`.
+ Redo how common stanza's are handled (they're currently "merged" into sections directly, which is unrecoverable).
 See the technical content section for more details on this.
+ Add support for comma printing.
+ add support for conditional branches.
  See the technical content section for more details on this.

A Previous attempts by [patrick](https://github.com/ptkato) for making this directly into cabal was [abandoned](https://github.com/haskell/cabal/pull/7626).
In private they mentioned that they worked for the Haskell foundation for a while on this,
but the contract expired and he moved on to another employer.
However another issue they had with this was that there appeared to
be no agreement on how to move forward with this specific problem.
They found the debate somewhat chaotic, and didn't know to proceed.
So at least what we can do with this proposal is come to a consensus what
a good solution looks like.
And let the perfect not be the enemy of good.

Another effort revolved around creating a separate AST[^ast],
which was against maintainer recommendation because it'd make the issue even bigger, 
and then [abandoned](https://github.com/haskell/cabal/pull/9385).
They got discouraged because they received no maintainer feedback
after [one and a half year](https://discourse.haskell.org/t/pre-proposal-cabal-exact-print/9582/2?u=jappie).

A related effort is to build combinators that allow modifying the `Field` type directly.
This would deprecate the `GenericPackage` structure and make an alternative structure
available.
A proof of concept was developed during ZuriHac:
https://discourse.haskell.org/t/pre-proposal-cabal-exact-print/9582/9?u=jappie

#### Why GPD rather than Field

A question raised in review is whether we could stick with `Field` instead of touching GPD.
The `Field` type describes the raw syntax of a cabal file:
if it could store whitespace it could potentially be used for exact printing.
`Field` later gets parsed into typed structures such as
`InstalledPackageInfo`, `ProjectConfig` and `GenericPackageDescription`.

We chose to annotate GPD rather than work at the `Field` level for these reasons:
1. **Type safety for modifications.** `Field` is essentially `[(FieldName, [FieldLine])]`.
   To add a dependency you would have to construct raw field lines with correct syntax.
   With annotated GPD you manipulate typed Haskell values
   (`DependencyWith`, `LibraryWith`, etc.) and the printer handles syntax.
2. **Validation is built in.** GPD carries semantic structure (conditionals, component boundaries)
   that `Field` does not. Modifications at the GPD level are checked by the type system;
   modifications at the `Field` level can produce syntactically valid but semantically broken files.
3. **The field grammar already bridges both worlds.** The `FieldGrammar` type class
   defines how to parse `Field` into GPD and how to pretty-print GPD back to `PrettyField`
   (which is similar to `Field`). By adding `HasAnn` instances to `FieldGrammar`
   we get annotation-aware parsing and printing without duplicating the grammar.

The proposal presented here converts `GenericPackageDescriptionAnn` into
`PrettyField` (which is similar to `Field`) before printing,
so the `Field`-level representation is still used as an intermediate step.

We had a large attempt at using a trivia tree based approach
which would track the exact positions in a dedicated tree.
This works however implementation is slow and difficult.
A missing item from the tree can mean many things
and it's hard to verify which one it is.
See details here: https://github.com/haskell/cabal/pull/11425

This proposal only focusess only on getting exact printing
to work with a minimal footprint.
We don't want to do any additional refactoring.
Furthermore the test suite created by the exact print effort this module
describes can also be used in the related `GenericPackageDescription` to `Field` effort.

## Backwards Compatibility / Migration

The `GenericPackageDescription` type alias is preserved:
```haskell
type GenericPackageDescription = GenericPackageDescriptionWith HasNoAnn
```
Because every type family in `Modify.hs` reduces `HasNoAnn` to the bare value,
code that only mentions `GenericPackageDescription` (not the `With` variant)
sees exactly the same record field types as before.
Functions like `parseGenericPackageDescription` continue to return the non-annotated type.

#### What does change

The main library's `condLibrary` field changes from
`Maybe (CondTree ConfVar Library)` to `Maybe (CondTree ConfVar (LibraryWith m))`.
At the `HasNoAnn` type alias this is the same as before,
but code that is polymorphic over the GPD parameter or that
pattern-matches on `GenericPackageDescriptionWith` directly will see `LibraryWith m`.

Additionally, common stanza merging will be postponed to allow
re-creating the common stanzas upon exact printing.
Compile errors can be solved by calling `mergeCondLibrary` to get the merged type,
or by calling `noImports` if there are no common stanza imports.

The discussion can be seen [here](https://github.com/haskell/cabal/pull/11277#issuecomment-3679092808).
In practice `PatternSynonyms` is not powerful enough for full backwards compatibility on record updates.

#### Migration path

For downstream code that uses `GenericPackageDescription`:
1. **Code that only reads fields** (e.g. `depPkgName`, `depVerRange`): no change needed.
   The accessor functions operate on the `HasNoAnn` type alias which has the same field types.
2. **Code that pattern-matches on GPD fields** (e.g. `cabal check`):
   if it matches on the type alias `GenericPackageDescription`, no change is needed.
3. **Code that constructs or updates GPD records**:
   if it constructs a `GenericPackageDescription` value directly,
   the record fields are the same types and no change is needed.
4. **Custom `Setup.hs` files** that import and manipulate GPD internals
   (e.g. `gtk2hs`, `gi-gtk`) may need adjustment if they are polymorphic
   over the GPD parameter or directly import `GenericPackageDescriptionWith`.
   The expected fix is small: either pin to the `HasNoAnn` alias
   or add a `mergeCondLibrary` call.

We do not expect this to be a major problem for most cabal client libraries,
as only code that touches GPD internals directly is affected.

#### Testing compatibility

To get an idea of how much breakage these changes introduce we tested
the two packages identified as most likely to be affected:

1. **haskell-gi** (`Data.GI.CodeGen.CabalHooks`):
   This is the most relevant test case — it directly accesses `GenericPackageDescription`
   fields in its `confHook`: it reads `condLibrary`, extracts `condTreeData`,
   updates `exposedModules`, `libBuildInfo`, and `autogenModules`, then writes back
   `condLibrary` via record update.
   **Result: compiles unchanged against the `gpd-barbie` branch.**
   All field types reduce to their original types under `HasNoAnn`:
   `condLibrary :: Maybe (CondTree ConfVar (LibraryWith HasNoAnn))` = `Maybe (CondTree ConfVar Library)`.

2. **gtk2hs** (`Gtk2HsSetup`):
   Despite being identified as a potential concern, gtk2hs only uses the resolved
   `PackageDescription` (via `Distribution.PackageDescription`), not `GenericPackageDescription`.
   It never touches `condLibrary` or any GPD-specific fields.
   **Result: compiles unchanged** — `PackageDescription` is not parameterised at all.

These results confirm that the barbies parameterisation is backwards compatible
for code that works with the `GenericPackageDescription` type alias (i.e. `HasNoAnn`).
The only breaking change is the common stanza merging (which is a separate, deliberate change).

For broader ecosystem testing, a `head.hackage`-style approach
or testing against `clc-stackage` could be done before merging.

## Interested parties

### Beneficiaries

The primary beneficiaries would be cabal users:

+ Opens up the possibility to improve cabal user experience,
  via inserting modules or running gen-bounds.
+ Makes it easier for users of the cabal library to deal with cabal files,
  such as hpack, HLS and cabal-fmt.
+ Makes maintaining cabal itself easier,
  e.g. `cabal init` could be described via `GenericPackageDescription`.

The HLS project would benefit from this effort;
it could add a dependencies plugin for example: https://github.com/haskell/haskell-language-server/issues/155

### Potentially affected downstream packages

Direct dependencies of `Cabal-syntax` on stackage are:
autoexporter, Cabal, cabal-gild, cabal-install, cabal-install-solver,
hackage-revdeps, hackage-security, imp, jailbreak-cabal.
There are hundreds more on hackage that depend on `Cabal`.

Most of these use `Cabal` through opaque functions (e.g. `parseGenericPackageDescription`,
field accessors) and will not be affected because the `HasNoAnn` type alias
preserves the existing types.

The packages most likely to be affected are those with custom `Setup.hs` files
that directly pattern-match on or construct `GenericPackageDescription` internals.
Known examples include:
+ `gtk2hs` and `gi-gtk` — their custom `Setup.hs` manipulates GPD internals.
+ Any package with a custom `Setup.hs` that imports `Distribution.Types.GenericPackageDescription`
  and pattern-matches on its fields.

We intend to identify and test these packages before the proposal is merged.
We could also make a post on discourse to ask if anyone else is affected.

## Implementation Notes

Implementors: Jappie and Leana.
Timeline: around 4 months of development, excluding review time.

The implementation is split across multiple PRs:
+ Comment parsing: https://github.com/haskell/cabal/pull/11252
+ Common stanzas: https://github.com/haskell/cabal/pull/11277
+ GPD barbie parameterisation (current work): https://github.com/leana8959/cabal/tree/gpd-barbie

### Maintainer impact

Adding new cabal-file fields will require two things in addition to the current work:
1. Add the field to the `HasAnn` instance of the field grammar (alongside the existing `HasNoAnn` instance).
2. Ensure the roundtrip test suite passes for the new field.

The `FieldGrammarWith` class has separate instances for `HasNoAnn` (current behaviour)
and `HasAnn` (annotation-preserving behaviour).
When a maintainer adds a new field they write the grammar once;
the `HasNoAnn` instance works as before,
and the `HasAnn` instance additionally records positions and trivia.
If the `HasAnn` instance is missing, the roundtrip test suite will catch it
because parsing will not produce annotations for that field,
causing the roundtrip to fail.

We intend to introduce a thorough test suite preventing regressions.
We also intend to document our findings of how
exact printing works via blog posts.

The first one already shed light on the parser grammar:
+ https://blog.haskell.org/a-comment-preserving-cabal-parser/

We intend another that sheds light on the field grammar.

These blog posts make cabal development more accessible
and make onboarding of new maintainers easier.

## Open Questions

We introduced a custom pretty printer now, we're not sure if this is the right approach.
CF: https://github.com/haskell/cabal/issues/11227#issuecomment-3901663867
Jappie encouraged Leana down this path because she drafted out a small printer in a couple days,
and it seemed to immediately solve problems she had been struggling with for weeks.
Would be good if anyone has more advice on this?

We're not sure how to deal with trailing white space on empty lines?
The lexer appears to drop them.


## References

+ https://github.com/haskell/haskell-language-server/issues/155
+ https://github.com/haskell/cabal/issues/7304
+ https://github.com/haskell/cabal/issues/7337
+ https://github.com/haskell/cabal/issues/6187
