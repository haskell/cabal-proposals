# Timeline and plan for removing `v1-` legacy commands

## Summary

The `v2-` project based commands were introduced alongside the legacy interface in
2016. This family of commands introduced support for multi-package based workflows
and installation of packages into a global store.

The primary way which people use cabal today is via the `v2-` interface. Writing
a command without a prefix defaults to using the `v2` command.

This document starts from the premise that

> We want to remove the `v1-` family of commands, therefore we need a plan to achieve that.

## Motivation

* There is much legacy code which has to be maintained and updated when modifying other parts of cabal. This code is not well-tested nor understood anymore. In legacy codebases like cabal, you quite often might modify a commonly used function and be forced to consider how to adapt all the codepaths which use it. It is hard to modify legacy paths which aren't understood and little used to know what the right thing to do is.
* It is confusing to users having two families of command exist for nearly 10 years. Users can follow old tutorials which suggest using v1- commands for certain tasks, they can raise bug reports about `v1-` features, when their use-case may be better served by a `v2-` command.
* We talk about performing this task a lot, which is halting progressing cabal on other fronts. For example, I am spending my time writing this document.

## Proposed Change

I propose to build consensus in the community around removing `v1-` commands.

1. Internal Phase: Produce a document for cabal developers to agree on a direction of travel which we can work together on. <--- We are here
2. Community Phase: Solicit feedback from the community about which `v1-` features are still used, and why.
   This phase isn't a promise to implement specific new features of modifications of
   existing features, but a fact-building mission so that an informed decision can be
   made in public.
3. Planning Phase: Produce a concrete plan about what will and won't be implemented before
   `v1-` commands are removed. The aim of this plan isn't to satisfy every request from the
   community phase, but to make a balanced judgement about what is realistic and essential.
4. Deprecation Phase: Once the plan has been established. The commands are deprecated.
5. Removal Phase: Once the plan has been executed, the commands are removed in the next release.

### Timeline

I propose that we will complete "Internal/Community and Planning" phases during
this release cycle. The deprecation phase will take place in the subsequent release cycle and
finally removal in the release cycle after that.

* 3.16-3.18 (Internal/Community/Planning)
* 3.18-3.20 (Deprecation)
* 3.20-4.00 (Removal)

### Internal Phase

The purpose of the internal phase is firstly to gather feedback internally from
cabal developers about the overall structure of this plan. The plan will require
coordination and collaboration between different members of the cabal team. Therefore
I think it's important to discuss ourselves initially what we think the best way forward
would be and whether we agree with this direction of travel.

### Community Phase

The community phase is one of the most important phases of the project.

I can see three main avenues to solicit feedback from users.

* Reading existing tickets about `v1-` commands, and verifying that the requirement still exists.
* Posting about this proposal on official spaces such as Discourse.
* Directly contacting "known users" of `v1-` commands.

The purpose of the consultation process is to identify users and workflows that
still actively depend on `v1-` commands, and to understand why they do so.

Feedback about general improvements to `v2-` workflows is welcome, but the focus
of this phase is to locate active dependencies. Those are the cases where removing `v1-`
commands would break an existing workflow.

Suggestions about how `v2-` could be improved are valuable for the long-term
evolution of Cabal, but they are not direct blockers for deprecating `v1-`
unless they correspond to a current `v1-` use case.

If a user no longer relies on `v1-`, removal of those commands should not
materially affect their experience.


### Planning Phase

Once user requirements have been established. The Cabal maintainers can construct
a concrete plan, with actionable issues that need to be completed before the `v1-`
commands are removed. This list may be quite short or quite long, but each item on
the list is actionable, well-defined, and directly helping a user identifed in the
community phase.

The work on the concrete plan can be distributed amongst different maintainers and
other people interested in working on the project.

### Deprecation Phase

Once the plan has been constructed, the `v1-` commands are deprecated in the next
release of `cabal-install`.

In exceptional circumstances, new items can be added to the work list during the
deprecation phase, but in general, the work-list is fixed at this point.

The good news is that if someone runs into a deprecation warning then they are actually
using a `v1-` command, so their opinion is considered a valuable signal.

### Removal Phase

Once the items on the list are completed the commands will be removed.

Any subsequent usages discovered are treated as future pieces of work.

## Alternatives Considered

I consider the other approach is to decide to keep the `v1-` interface forever.
I would also consider this issue resolved if that was decision made by cabal developers.
My main motivation is to allow people to move on from the `v1-`, `v2-` split.


## Backwards Compatibility / Migration

The document describes a concrete plan for removal of `v1-` commands in a way which users can migrate to the `v2-` commands.

## Interested parties

This change has the potential to affect any user of cabal. During the relevant
phases the documenant and plan will be communicated widely on platforms such as Discourse.

## Implementation Notes

I can implement some parts myself, but the overall project requires buy-in from
other core contributors.

## Open Questions

## References

* [Remove legacy code from code base](https://github.com/haskell/cabal/issues/10262)
* [Establish a plan for removing v1- commands](https://github.com/haskell/cabal/issues/11249)
* [v1-vs-v2 label](https://github.com/haskell/cabal/issues?q=is%3Aissue%20state%3Aopen%20label%3A%22re%3A%20v1-vs-v2%22)
* [Deprecate new- prefix](https://github.com/haskell/cabal/issues/9109)

