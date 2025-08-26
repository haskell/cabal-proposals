# Cabal Support for Bytecode Objects and Bytecode Libraries

## Summary

Extend Cabal to support building, installing, and managing persistent bytecode
artifacts (`.gbc` files) and bytecode libraries alongside native code, enabling
faster build times and better tooling integration for development and REPL use
cases.

## Motivation

Currently, GHC's bytecode interpreter only generates transient, in-memory
bytecode that must be regenerated every time a module is loaded in GHCi or for
Template Haskell evaluation. This proposal extends Cabal and `cabal-install` to support persistent
bytecode artifacts, which will:

- Enable caching of bytecode for faster (`cabal repl`) startup and tooling
- Reduce compilation time for development workflows
- Provide better integration between Cabal and GHC's bytecode capabilities
- Support the new `-fwrite-bytecode` flag in GHC for persistent bytecode generation
- Allow the debugger to step-through library dependencies code

This is not intended to replace native code for production executables, but
rather to extend Cabal's capabilities where fast build times, portability, and
tooling integration are more important than peak execution speed.

## Proposed Change

### Changes to `ghc-pkg`

- Add a new field `bytecode-library-dirs` to the package database to store the locations of bytecode libraries.

### Changes to Cabal Library (Setup Interface)

The main changes are to add a new bytecode "library way" to Cabal.

- Add `--enable-library-bytecode` build option to the Cabal library interface which when enabled will pass `-fwrite-bytecode` to GHC
- If requesting an object way and the bytecode way, then `-fbyte-code-and-object-code` will be passed to GHC to enable compilation of all artifacts in a single pass.
- Once a library is finished being compiled, cabal will create a bytecode library archive containing all the `.gbc` files for the library.
- The bytecode library will be installed into the package database alongside the native library.
- Add a new option to enable the `repl` command to write bytecode files. This will be enabled by default.

### Changes to cabal-install (User Interface)

- `--enable-library-bytecode` flag: When specified, enables bytecode generation for the build
- This flag exposes the underlying `--enable-library-bytecode` build option from the Cabal library
- This flag is like `--enable-shared` or `--enable-library-profiling`, it is a way specifier.

## Alternatives Considered

- The other option is to not add support to Cabal for bytecode libraries, and
instead have the user manually create a bytecode library archive and install it
into the package database. This approach would lead to a difficult adoption of
the feature.

## Backwards Compatibility / Migration

This change maintains full backwards compatibility:

- Default Behaviour: Bytecode generation is disabled by default, so existing builds are unaffected
- Optional Feature: The `--enable-library-bytecode` flag is opt-in, requiring explicit user action

## Interested parties

- Haskell Tooling Developers: Those building IDEs, language servers, and development tools that would benefit from faster bytecode loading
- GHC Developers: The GHC team implementing the `-fwrite-bytecode` functionality
- Cabal Maintainers: The Cabal team who will review and integrate these changes
- Package Authors: Developers who want faster development cycles and better tooling integration
- Haskell Community: Users who would benefit from improved development experience

### Contact Status

- GHC Team: I am collaborating with Cheng Shao, and Rodrigo Mesquita on the bytecode implementation
- Cabal Team: Will engage with Cabal maintainers for review and integration
- Tooling Community: I made a [post on discourse](https://discourse.haskell.org/t/rfc-introduce-a-serialisable-bytecode-format-and-corresponding-bytecode-way/12678) asking for feedback on the proposal.

## Implementation Notes

### Implementation Plan

1. Phase 1: Extend Cabal library to support bytecode configuration and artifact generation
   - Add `--enable-library-bytecode` build option to the Cabal library
   - Implement bytecode generation in the build system
   - Extend package registration for bytecode artifacts

2. Phase 2: Implement cabal-install user interface changes
   - Add `--enable-library-bytecode` command-line flag

3. Phase 3: Integration testing and documentation
   - Test across different platforms and configurations
   - Document new features and usage patterns

Either myself or a colleague can implement these changes.

## Open Questions

- `cabal-install` could also support the option to use `-fprefer-bytecode`, which would imply generating bytecode for dependencies rather than object code
  in the same build way as the compiler.
- There currently isn't support for building "bytecode executables", and hence no `--enable-executable-bytecode` flag.

## References

* [GHC Issue 26298](https://gitlab.haskell.org/ghc/ghc/-/issues/26298)
* [Cabal Issue 11188](https://github.com/haskell/cabal/issues/11188)
* Discourse post: [RFC: Introduce a serialisable bytecode format and corresponding bytecode way](https://discourse.haskell.org/t/rfc-introduce-a-serialisable-bytecode-format-and-corresponding-bytecode-way/12678)
