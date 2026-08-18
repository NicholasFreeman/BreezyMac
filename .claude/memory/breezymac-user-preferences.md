---
name: breezymac-user-preferences
description: BreezyMac product owner's use-case, design tastes, and tuning preferences
metadata:
  type: user
---

The user is building BreezyMac primarily to **mitigate thermal throttling** on
their Apple-Silicon MacBook (macOS 26). Their driving complaint: the default
macOS fan curve keeps fans too quiet for too long, leading to throttling under
their workloads. Goal is simply "fans at whatever level avoids throttling."

**Design tastes (apply these when proposing UI/UX):**
- Strongly prefers **minimal, low-fiddliness controls**. Loved that the single
  Automatic "Anticipation" slider gives large effective control without fussy
  curve editing — explicitly asked to keep that design. Favor few high-leverage
  knobs over complex editors.
- Prefers a **gentle fan response**; dislikes hard/sudden fan swings. In testing
  (with a wide 50→95 °C band) he settled on ~**12%** anticipation personally;
  also liked **70→95 °C with 15–20%**. Agreed the shipped **default is 0.15**.
- Between test runs he switches to **Performance** to cool the system back to
  ~ambient (~5 °C over) before the next run.
- Averse to duplicate ways to configure the same thing *unless* comparing them
  is genuinely useful (agreed to prototype linear vs monotone-cubic curves to
  pick one).

**Working style:** tests thoroughly on real hardware and gives precise,
step-by-step feedback (very valuable — trust it). Likes committing progress and
keeping memory current; comfortable starting fresh sessions when context fills.

**Git / project identity:** commit author is **Nicholas Freeman** with GitHub's
protected no-reply address `12092720+NicholasFreeman@users.noreply.github.com`.
The personal email was scrubbed from all history after GitHub push-protection
flagged it; local `git config user.email` already uses the no-reply address, so
keep committing as-is — never write the personal email into any file or commit.
Public repo: **https://github.com/NicholasFreeman/BreezyMac** (clones to
`BreezyMac/`). Licensed **MIT** (© 2026 Nicholas Freeman, `LICENSE.md`). The
`org.WhoCo` bundle id / mach-service namespace is intentional — leave it unless a
rebrand is explicitly requested (changing it touches the whole helper install
architecture). See [[breezymac-phase-and-open-questions]].
