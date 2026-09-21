# Tooling Improvement // Implement `--watch` switch for reloading only changed code and running tests fast

## Summary

Integrate file watching and incremental code reload so `cabal test --watch` becomes both possible and fast.

## Motivation

*Why is this change needed?*

 * It is good engineering practice to have a test-runner running while developing and getting instant feedback.
 * Majority of (new) users are very unlikely to find the badly documented (now possible) special command using `ghcid` and less likely to get it right, for example:
     `ghcid -c 'cabal repl --enable-multi-repl test:sandwich lib:mylib' --test Main.main --warnings`
 * Release dependency on `ghcid` or similar packages for what developers expect to be builtin in 2026.
 * Because it is a high value feature that drives most users' productivity.
 * Because running any test-suite directly (via external watch command) takes much longer (as it does not figure what has changed) than just recompiling what has changed, hence the development experience is less fun than it could be.

*What problem does it solve?*

  * No more fiddling around (and in majority of cases of users giving up figuring out the right configuration) of getting testing set up *with fast feedback*.
  * Slow feedback of test suite not using GHC's API? for reloading only changed code.
  * While more recent languages ([Zig](https://ziglang.org/documentation/0.16.0/#Zig-Test), [Rust](https://doc.rust-lang.org/rust-by-example/testing/unit_testing.html)) have their integrated test suite, it's a real hassle to get it configured and have it up and running as a fast watcher with

## Proposed Change

  * Introduce new command line switch `--watch` to cabal like `cabal test --watch` or `cabal repl --watch` to reload on any changes (including tests themselves) in the (multi-component) code base by:

    * integrating file watcher that
    * triggers incremental recompilation of changed files (GHC), like `:r` does in repl

## Alternatives Considered

What other approaches were considered?

  * document `ghcid -c 'cabal repl --enable-multi-repl test:sandwich lib:mylib' --test Main.main --warnings` more prominently -- discouraged because of external dependency and complicated syntax
  * https://cabal.readthedocs.io/en/stable/external-commands.html (it should not be an external command as it is the test suite that is being run using cabal)
  * run [watchexec](https://github.com/haskell/cabal/issues/5252#issuecomment-988678870) with running the tests-suite directly -- discouraged because it rebuilds everything, thus takes longer wasting possibility of incremental rebuilds like repl `:r`

*Why was this one chosen?*

  * because it is the most natural way a developer (= language & tooling user) would the tool expect to behave
  * no external dependencies
  * no configuration friction
  * it is boosting both new and experienced language users' productivity with minimal effort, hence facilitates user adoption of the language based on proper tooling

## Backwards Compatibility / Migration

*Does this change affect backwards compatibility?*

  * No, as it introduces a new command line switch to existing cabal commands.

*What migration path is needed?*

  * None, as it does not change existing behaviour or expectations of users.

## Interested parties

*Who are the interested parties in the broader Haskell community?*

  * Language users:
  
    * Newcomers to the language who shall not become disappointed by missing test-runner.
    * Experienced users who all to long have accepted missing what should not be missing but builtin.
    * Basically most users who benefit from rapid feedback of their test-suite.

  * Implementors / engineers familiar with internals of GHC and cabal-install

  * Neil Mitchell because he has experience and knowledge through writing `ghcid`

  * Users from industry who seek to improve their productivity (cue to funding?).
  
*Have you contacted them?*

No, since the people who are familiar with the right parts of existing systems are unclear to me.
Though, this document can be a starting point.

## Implementation Notes

*Are you willing to implement this yourself?*

No, but I can help in coordinating.

*What is the expected timeline?*

Unclear.

## Open Questions

*Are there any unresolved questions or areas needing further input?*

Yes, a rough outline of implementation plan / which parts of which existing systems (GHC, ghcid) need to be re-used and how they need to be brought together.

 - Who knows what needs to be done?
 - Which parts of existing systems need to be re-used (GHC, ghcid, etc.)?
 - What needs to be done for the actual implementation?

## References

*Links to related issues, discussions, or previous work.*

### Previous work

 - ghcid
 - george.fst [working](https://discourse.haskell.org/t/tooling-improvement-integrate-test-watcher-cabal/14623/5) on file watching tool specifically for Obelisk, with separate REPL processes for the backend and the Wasm frontend. I’ll try to upstream what I can to GHCI
 - WIP ghci watch command: https://gitlab.haskell.org/ghc/ghc/-/merge_requests/14440
 - ghciwatch: https://github.com/MercuryTechnologies/ghciwatch/
 - cabal watch command: https://github.com/haskell/cabal/issues/5252
 - ghcid --test https://github.com/ndmitchell/ghcid/issues/191
 - tricorder: https://github.com/tweag/tricorder
 - buck2 for haskell: https://github.com/simonmar/haskell-buck2

### Other related work

 - Steel Overseer: https://github.com/schell/steeloverseer
 - Watchman: https://facebook.github.io/watchman/
 - feedback: https://github.com/NorfairKing/feedback
 - Watchexec: https://github.com/watchexec/watchexec
 - entr: https://github.com/eradman/entr

### Discussions (non-exhaustive yet)

 - https://discourse.haskell.org/t/tooling-improvement-integrate-test-watcher-cabal/14623
