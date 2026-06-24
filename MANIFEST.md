# The Paranoid Tools Manifesto

**English** · [Русский](MANIFEST.ru.md)

*A small movement for honest privacy in a world that no longer logs off.*

---

## Where we stand

Digitalization stopped being an event and became the weather. Most of us now
live partly inside the machine: our memory is in the cloud, our judgment is
shared with models, our day passes through systems that watch, index, sync, and
remember by default. The line between a person and their digital extension has
thinned to almost nothing. That is not a complaint — it is the terrain.

On this terrain the old advice is obsolete and most of the new advice is selling
something. "Secure" has become a marketing word. Tools promise erasure they
cannot deliver, silence about the parts they cannot protect, and a feeling of
safety in place of the thing itself. A false sense of security is worse than
none, because you act on it.

We build the opposite.

## Privacy, not anonymity

We are precise about the word, because the confusion is deliberate elsewhere.

**Anonymity** is hiding *who you are*. It is a fight against attribution, often
adversarial, often political, and not what most people need most days.

**Privacy** is control over *what is yours* — who reaches it, when, and on whose
terms. A seed phrase. A key. A password. A draft no one else should read. You
can be fully known and still entitled to a locked drawer.

Privacy is agency. It is the right to draw a boundary around what is valuable to
you and to decide who crosses it. In an age where everything is connected to
everything, that boundary does not maintain itself — it has to be chosen, and
chosen again. Limiting access to what matters most is not paranoia. It is
hygiene.

## What we believe

**Honesty over theater.** A tool must tell you what it does *and* what it cannot
do. Every limitation stated plainly, in the open, before you trust it. We would
rather lose a user to the truth than keep one with a comforting lie.

**Hygiene over fear.** This is not survivalism. It is the digital equivalent of
washing your hands — small, repeatable, unglamorous acts that keep what is yours
intact. You don't need to be hunted to deserve a clean trail.

**Control over convenience, when they conflict.** Systems sync, index, and back
up by default because it is convenient. Privacy is the deliberate act of saying
*not this, not here, not without me.*

**Comprehension over trust.** "Don't trust, verify." Every install is checksum-
and signature-verified. Every tool is a single readable file you can audit
before you run it. We ask you to understand, not to believe.

## The law

These are not slogans. They are checked in every change, and a tool that breaks
them is not part of the ecosystem.

1. **One tool, one job.** No combines, no kitchen sinks. If a utility does two
   things, it is two utilities. Precision is a feature.

2. **Native primitives, zero dependencies.** Lean on what the operating system
   already provides. No runtime to rot, no supply chain to compromise, nothing
   between you and the metal that you didn't choose.

3. **Honest about the limits.** Every tool ships a *Scope & limitations* section
   that says, in plain language, what it does **not** guarantee. If a feature
   manufactures a false sense of security, we either fix it or warn loudly. We
   never sell overwriting as erasure, hiding as destruction, or a tool as a
   miracle.

## The tools are the argument

A manifesto that stays words is just an opinion. Ours is embodied in five small
instruments, each covering one step in **the lifecycle of a secret** — write it,
store it, guard it, hide it under threat, distribute it, destroy it:

| Step | Tool | One job |
|------|------|---------|
| write without a trace | [`ghostdraft`](https://github.com/Di-kairos/ghostdraft) | view or draft sensitive text leaving no copy in the usual places |
| store & destroy | [`securetrash`](https://github.com/Di-kairos/securetrash) | an encrypted vault, and honest deletion that refuses to lie about SSDs |
| guard while open | [`vaultwatch`](https://github.com/Di-kairos/vaultwatch) | narrow the leak channels while a vault is mounted, restore on close |
| hide under threat | [`panic`](https://github.com/Di-kairos/panic) | one command to hide and lock everything, instantly |
| distribute | [`seedsplit`](https://github.com/Di-kairos/seedsplit) | split a secret into Shamir shares — any T reconstruct, fewer reveal nothing |

Each is pure Bash, single-file, zero-dependency, MIT-licensed, and carries its
own honest *Scope & limitations*. They are made the way a good tool should be
made: to do exactly one thing, to do it well, and to say plainly where it stops.

## For everyone, everywhere

These tools are not for spies or survivalists. They are for the person who has a
seed phrase to protect, a draft to keep private, a boundary to hold — which, in a
digitalized world, is everyone.

So the work is meant to travel. Free and open source. Documented in plain
language in more than one tongue. Auditable by anyone, owned by no one. Privacy
is a precondition for agency, and agency should not be a luxury good. Wherever a
person is merging their life into the machine — and that is now everywhere — they
deserve instruments that are honest about protecting it.

## The credo

> One secret, several tiny honest tools.
> Each does exactly one thing — and each tells you plainly what it cannot do.

We don't promise safety. We give you control, comprehension, and the truth about
the edges. What you do with them is yours. That is the whole point.

---

*Free / open source · MIT · privacy, not anonymity · honesty over theater.*
*Technical release state lives in [`docs/RELEASE-STATE.md`](docs/RELEASE-STATE.md).*
