# Community Project Cabal Exact Printer

Note that this is a copy of the TWG
proposal: https://github.com/haskellfoundation/tech-proposals/pull/65
requested by Matthew: https://github.com/haskell/cabal/issues/11227#issuecomment-3590108400

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
<ul>
 <li> [hpack](https://github.com/sol/hpack),              </li>
 <li> [autopack](https://github.com/kowainik/autopack)    </li>
 <li> [cabal-fmt](https://github.com/phadej/cabal-fmt)    </li>
 <li> [gild](https://taylor.fausak.me/2024/02/17/gild/)   </li>
</ul>

Of course many of these projects do more then just module expansion.
hpack provides a completely different cabal file layout for example,
`cabal-fmt` and `gild` are formatters for cabal files.
Only auto-pack just does this one feature.
However, since all these programs implement this functionality
in their own distinct way,
there is clearly demand for it.

There are more issues then just module expansion however.
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

An example how a program to add dependencies to the main library could look:
```haskell
main :: IO ()
main = do
    theFile <- readFile "my.cabal"
    dependName <- PackageName <$> getLine
    case parseGenericPackageDescription theFile of
    let (warns, eDescription) = runParseResult res
    case eDescription of
      Left someFailure -> do
        error $ "failed parsing " <> show someFailure
      Right generic ->
        let
          depends = mkDependency dependName anyVersion (NES.singleton LMainLibName)
          modified = generic { condLibrary = case (condLibrary generic) of  
                                                Just lib -> (lib { condTreeConstraints = depends : condTreeConstraints lib })
                                                Nothing -> Nothing
                             }
        in
        Text.writeFile "my.cabal" $ exactPrint modified
```

All the difficulty in this programming lies in figuring out where to place a dependency,
we just made a decision here to do it in the main library assuming it exists.
We also assumed there would be no conditionals, 
all these questions are what a program to add dependencies should ask to a user,
and the `GenericPackageDescription` type guides the programmer in asking the right questions.
Therefore, we can say that `GenericPackageDescription` is stronger typed then `Field`.
Note that there is no low level syntax mangling going on at all,
because the functions exposed in the cabal library takes care of that for us.

## Proposed Change

This proposal want's to add a function to the cabal library:

```haskell
printExact :: GenericPackageDescription -> Text
```

Which will do exact printing.
This function has the following properties:

byte for byte roundtrip of all `hacakgePackage`:
```haskell
  forall (hackagePackage :: ByteString) . (printExact <$> (parseGeneric hackagePackage)) == Right hackagePackage
```

where `hackagePackage` is a cabal package found on hackage.
to support exact printing a new field is added to `GenericPackageDescritpion`:

```haskell
data GenericPackageDescription {
 ...
 , exactPrintMeta :: ExactPrintMeta
 }
```

Which in turn contains various meta data we need for exact printing:
```haskell
data ExactPrintMeta = ExactPrintMeta
  { exactPositions :: Map [NameSpace] ExactPosition
  , exactComments :: Map Position Text
  }
```

Where Exact position is:
```haskell
data ExactPosition = ExactPosition {namePosition :: Position
                                  , argumentPosition :: [Position] }
```
And `Postion` is just a row and column coordinate of a textfile.
This type already exists in cabal.

A namespace is used to find exact positions:
```haskell
data NameSpace = NameSpace
  { nameSpaceName :: FieldName
  , nameSpaceSectionArgs :: [ByteString]
  }
  deriving (Show, Eq, Typeable, Data, Ord, Generic)
```
It just encodes a path down the rose tree.
for example:
```haskell
library
  if flag(foo)
    build-depends:     base <5
```
Would be encoded as:
```haskell
,[NameSpace {nameSpaceName = "library", nameSpaceSectionArgs = []},NameSpace {nameSpaceName = "if", nameSpaceSectionArgs = ["flag(foo)"]},NameSpace {nameSpaceName = "build-depends", nameSpaceSectionArgs = []}]
```
This gives a unique way of figuring out the exact position of the build-depends field.
Although conditionals need a little bit more refinement, see the conditional section for that.

For comments some parser modifications were needed which were developed during zurich hack 2024.
This was a big uncertainty which now has been addressed.

It's unclear what other fields are required right now.
For example build bounds might require another map 
like `Map ([NameSpace], PackageVersionConstraint) Original`,
this kind of representation allows us to retrieve the original only if it hasn't changed.
However I'm confident all of this is do-able.

Many are concerned about using `Field` I suppose for the printing part, 
but we don't use that exact type, we use `PrettyField` because the pretty printer
already had a decent `FieldGrammar`,
and the type is almost the same.
The first thing `exactPrint` does is use the existing pretty field grammar to
create pretty fields:
```haskell
exactPrint :: GenericPackageDescription -> Text
exactPrint package = ...
  where
    fields :: [PrettyField ()]
    fields = ppGenericPackageDescription (specVersion (packageDescription (package))) package

```

Then we attach all the meta data to these `Fields` with `anotatePostions`:
```haskell
attachPositions :: [NameSpace] -> Map [NameSpace] ExactPosition -> [PrettyField ()] -> [PrettyField (Maybe ExactPosition)]
```
Here we put the various pieces of meta data directly into the field for parsing.
Maybe you have an exact position at a certain point during printing,
which you can use to "repair" the default pretty printing behavior.

Preliminary testing shows that this approach works with multiple sections of cabal files,
and now also with some basic comments.
Comments likely have to be worked out further as we only made that one test pass,
but the 'tools', and more importantly, the understanding is in place.
There is a working prototype.

Change of the `GenericPackageDescription` must be possible for
+ module addition/removal
+ library addition/removal

The issue for addition is that you now have to invent exact positions.
for removal, if it involves a line, you've to fix up all following lines, 
(and it has to know something was removed).

The overal goal would be to roundtrip 99% of all hackage packages.

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

Another effort revolved around creating a seperate AST[^ast], 
which was against maintainer recommendation because it'd make the issue even bigger, 
and then [abandoned](https://github.com/haskell/cabal/pull/9385).
They got discouraged because they received no maintainer feedback
after [one and a half year](https://discourse.haskell.org/t/pre-proposal-cabal-exact-print/9582/2?u=jappie).

A related effort is to build combinators that allow modifyng the `Field` type directly.
This would depracate the `GenericPackage` structure and make an alternative structure
available.
A proof of concept was developed during zurich hack
https://discourse.haskell.org/t/pre-proposal-cabal-exact-print/9582/9?u=jappie

The idea was to start with the `Field` type because it describes
the syntax of a cabal file.
If it could store whitespaces it could potentially be used to be exact printed.
This `Field` type later gets parsed into other types such as 
`InstalledPackageInfo`, `ProjectConfig` and `GenericPackageDescription`.
Currently it's unclear to me how this would work with modifications
on `GenericPackageDescription`.
Although the proposal presented here converts `GenericPackageDescription` into
`PrettyField` which is similar to `Field`, before printing.

This proposal only focusess only on getting exact printing
to work with a minimal footprint.
We don't want to do any additional refactoring.
Furthermore the test suite created by the exact print effort this module
describes can also be used in the related `GenericPackageDescription` to `Field` effort.

## Backwards Compatibility / Migration

We mostly want to prevent breaking changes.
I'm leaning towards breaking some fields
in GenericPackageDescription to indicate weather the common stanza's have
been merged or not.

For now that's the only issue.

## Interested parties

The primary benificiaries would be cabal users.
we can:

+ opens up the possibility to improve cabal user experience, 
  via inserting modules or running gen-bounds.
+ makes it easier for users of the cabal library to deal with cabal files, 
  such as hpack, HLS and cabal-fmt
+ makes maintaining cabal itself easier, 
  eg cabal init could be described via `GenericPackageDesription`

Furthermore I've heard that the HLS project will benefit this effort,
it could add a dependencies plugin for example: https://github.com/haskell/haskell-language-server/issues/155

## Implementation Notes

Yes me and Leana.
Timeline should be around 4 months.


## Open Questions

Since common stanza's have been solved.

Currently we're struggling with how to retrieve the 

## References

+ https://github.com/haskell/haskell-language-server/issues/155
+ https://github.com/haskell/cabal/issues/7304
+ https://github.com/haskell/cabal/issues/7337
+ https://github.com/haskell/cabal/issues/6187
