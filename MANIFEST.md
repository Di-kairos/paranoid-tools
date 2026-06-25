# The Paranoid Tools Manifesto

**English** · [Русский](MANIFEST.ru.md)

*A small movement for honest privacy in a world that no longer logs off.*

---

## Where we stand

Digitalization stopped being an event and became the weather. Most of us now
live partly inside the machine: our memory sits in the cloud, our judgment is
shared with models, our day runs through systems that watch, index, sync, and
remember by default. The line between a person and their digital extension has
worn down to almost nothing. That's not a complaint — it's the terrain.

On this terrain the old advice is obsolete and most of the new advice is selling
something. "Secure" has become a marketing word. Tools promise an erasure they
can't deliver, stay quiet about what they can't protect, and hand you a feeling
of safety in place of the real thing. A false sense of security is worse than
none — because you act on it.

We build the opposite.

## Privacy, not anonymity

We're precise about the word, because elsewhere the confusion is deliberate.

**Anonymity** hides *who you are*. It's a fight against attribution — often
adversarial, often political, and not what most people need on most days.

**Privacy** is control over *what is yours*: who reaches it, when, and on whose
terms. A seed phrase. A key. A password. A draft no one else should read. You
can be fully known and still entitled to a locked drawer.

Privacy is agency — the right to draw a line around what matters to you and
decide who crosses it. In an age where everything connects to everything, that
line doesn't hold itself; it has to be chosen, and chosen again. Limiting access
to what matters most isn't paranoia. It's hygiene.

## What we believe

**Honesty over theater.** A tool must tell you what it does *and* what it can't
do — every limitation stated plainly, in the open, before you trust it. We'd
rather lose a user to the truth than keep one with a comforting lie.

**Hygiene over fear.** This isn't survivalism. It's the digital equivalent of
washing your hands: small, repeatable, unglamorous acts that keep what's yours
intact. You don't have to be hunted to deserve a clean trail.

**Control over convenience, when they conflict.** Systems sync, index, and back
up by default because it's convenient. Privacy is the deliberate act of saying
*not this, not here, not without me*.

**Comprehension over trust.** Don't trust, verify. Every install is checked
against its checksum and signature. Every tool is a single readable file you can
audit before you run it. We ask you to understand, not to believe.

## The law

These aren't slogans. They're checked in every change, and a tool that breaks
them is not part of the ecosystem.

1. **One tool, one job.** No combines, no kitchen sinks. If a utility does two
   things, it's two utilities. Precision is a feature.

2. **Native primitives, zero dependencies.** Lean on what the operating system
   already gives you. No runtime to rot, no supply chain to compromise, nothing
   between you and the metal that you didn't choose.

3. **Honest about the limits.** Every tool ships a *Scope & limitations* section
   that says, in plain language, what it does **not** guarantee. If a feature
   manufactures a false sense of security, we fix it or warn loudly. We never
   sell overwriting as erasure, hiding as destruction, or a tool as a miracle.

## The tools are the argument

A manifesto that stays words is just an opinion. Ours lives in five small
instruments, each covering one step in **the lifecycle of a secret** — write it,
store it, guard it, hide it under threat, distribute it, destroy it:

| Step | Tool | One job |
|------|------|---------|
| write without a trace | [`ghostdraft`](https://github.com/Di-kairos/ghostdraft) | view or draft sensitive text leaving no copy in the usual places |
| store & destroy | [`securetrash`](https://github.com/Di-kairos/securetrash) | an encrypted vault, and honest deletion that refuses to lie about SSDs |
| guard while open | [`vaultwatch`](https://github.com/Di-kairos/vaultwatch) | narrow the leak channels while a vault is mounted, restore on close |
| hide under threat | [`panic`](https://github.com/Di-kairos/panic) | one command to hide and lock everything, instantly |
| distribute | [`seedsplit`](https://github.com/Di-kairos/seedsplit) | split a secret into Shamir shares — any T reconstruct, fewer reveal nothing |

Each is pure Bash: a single file, zero dependencies, MIT-licensed, with its own
honest *Scope & limitations*. They're built the way a good tool should be — to do
exactly one thing, do it well, and say plainly where it stops.

## For everyone, everywhere

These tools aren't for spies or survivalists. They're for the person with a seed
phrase to protect, a draft to keep private, a boundary to hold — which, in a
digitalized world, is everyone.

So the work is meant to travel. Free and open source. Documented in plain
language, in more than one tongue. Auditable by anyone, owned by no one. Privacy
is a precondition for agency, and agency shouldn't be a luxury good. Wherever a
person is merging their life into the machine — everywhere, now — they deserve
instruments that are honest about protecting it.

## The credo

> One secret, several tiny honest tools.
> Each does exactly one thing — and each tells you plainly what it can't do.

We don't promise safety. We give you control, comprehension, and the truth about
the edges. What you do with them is yours. That's the whole point.

---

*Free / open source · MIT · privacy, not anonymity · honesty over theater.*
*Technical release state lives in [`docs/RELEASE-STATE.md`](docs/RELEASE-STATE.md).*
