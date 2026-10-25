# Production Guide

Rules every phase is written, recorded, and reviewed against. Phase 00 and
Phase 01 are the reference implementation — if a later phase drifts from
these rules, fix the phase, not the rule.

## 0. Brownfield by default

This engagement — and almost every real FinOps/IDP client engagement — lands
on existing infrastructure that someone else built under deadline pressure,
not a clean slate. That means debugging-heavy phases are the expected
baseline, not a deviation to minimize or edit out. A phase where the first
attempt fails, the error is genuinely unexpected, and the fix takes real
investigation is a *more* representative phase than one that runs clean on
the first take. Do not re-shoot a phase to make it look cleaner than the
infrastructure actually was. See Rule 1's ban on fabricated third-party
anecdotes — the same principle extends here: a real dead end is worth more
than a smoothed-over one.

## 1. Voice and framing

- First person, present tense. "I'm checking whether this NAT Gateway is
  actually carrying S3 traffic" — not "a client had this problem" and not
  "you would check whether."
- Audience is a CTO, VP Eng, or senior engineer evaluating whether to hire
  this skill set — not a bootcamp student. Explain *judgment*, not syntax.
  When a command is self-explanatory from its flags, don't narrate the flags;
  narrate why this check, in this order, right now.
- No anonymous "a startup I worked with" stories. If a technique originated
  on client work, it's generalized into the live demo per
  `ENGAGEMENT-BRIEF.md` — never told as a third-person anecdote standing in
  for evidence.
- One ending per phase. Draft, then delete every "see you next time" that
  isn't the actual last line of the actual last section.

## 2. What never gets committed

Real values that must never appear in any file, commit, or recorded terminal
in this repo, even briefly:

- AWS account IDs, IAM ARNs, or role names — always `${ACCOUNT_ID}`
- Real cluster names, VPC IDs, subnet IDs — always `${CLUSTER_NAME}` etc.
- Client names, sizes, or identifying details of any kind
- Slack webhook URLs, tokens, or any credential — always a placeholder plus
  a one-line note on where it comes from (Secrets Manager, Vault, etc.)

Before any terminal recording is published, `scripts/redact-check.sh` (see
`scripts/`) greps the session log for the account ID pattern and known
identifiers. A phase is not done until that script passes clean.

## 3. Every phase README has the same six sections

1. **Where we left off** — one paragraph, carries forward the prior phase's
   ending state. First phase (00) instead opens the engagement.
2. **What we're solving today** — the specific problem, stated the way the
   client (or, on camera, the demo stack) actually presented it. Not a
   restated table of contents.
3. **The work** — narrated in the order it actually happened, including
   dead ends. If a first approach didn't work, that stays in, with why.
4. **What broke and how it got fixed** — every phase needs at least one real
   debugging moment. If nothing broke, that's a signal the phase was
   over-rehearsed before recording — go run it again for real.
5. **Numbers, before and after** — pulled from `docs/baseline/`, never
   hand-typed into the README from memory.
6. **Carries forward** — the exact state (files, env vars, dollar figures,
   open questions) the next phase's "Where we left off" will reference.

`runbook.md` sits next to `README.md` in every phase folder: every command,
in the order it was actually run, each with real captured output — not
illustrative output. `iac/` holds the actual Terraform/Helm diff applied
that phase. `artifacts/` holds the actual Cost Explorer / Kubecost exports.

## 4. Numbers discipline

- A dollar figure in any phase must trace to a command in that phase's
  `runbook.md` or a file in its `artifacts/`. No figure is asserted without
  a command that produced it, in this repo, on these stacks.
- Never inflate demo-stack numbers to match a larger hypothetical company.
  State the real number and, if useful, the scaling assumption separately
  (see `ENGAGEMENT-BRIEF.md`).
- `docs/baseline/finops-baseline.md` is append-only across phases — treat it
  like the client evidence file it's modeled on. Every phase appends to it;
  no phase rewrites an earlier phase's entry.

## 5. Terminology locked for this repo

- **Phase**, not "series" or "module." (Course numbering: 00–11, twelve
  phases total — 00 is the kickoff, 01–11 match the eleven-series scope
  from the original course outline.)
- **Engagement**, not "project," when referring to the whole 12-phase arc.
- Stack names are exactly `financial-rag-agent` and `riskoracle` everywhere
  — repo folder names, catalog-info.yaml, Helm release names, Kubecost
  namespace labels. No `financial-ai-agent` variant anywhere in this repo.

## 6. Definition of done for a phase

- [ ] `README.md` has all six sections, first person, present tense
- [ ] `runbook.md` commands were actually run against a real stack this pass
- [ ] At least one genuine failure + fix is documented
- [ ] `artifacts/` has the real export backing every number in `README.md`
- [ ] `redact-check.sh` passes clean
- [ ] "Carries forward" section matches the next phase's "Where we left off"
      word for word on the state it hands over
## 7. Draft status marker — what "real output" means before a phase is recorded

Every phase README claims real commands and real output. That claim is
only true once someone has actually run the commands against
`financial-rag-agent` / `riskoracle` and pasted in what came back. A phase
written *before* that recording session — drafted to plan the segment, get
the command sequence right, and rehearse the narration — is not yet in
that state, and has to say so.

Any phase README not yet backed by an actual recorded session opens with:

```
> **Draft — commands are correct and ready to run. Output shown below is
> illustrative, written to be realistic, but has not yet been captured
> live against the deployed stack. Replace every code block's output with
> the real captured output during recording, then delete this notice.**
```

This applies retroactively: Phase 00 and Phase 01 were written the same
way — plausible, carefully-constructed output, not a captured terminal
session, because writing them didn't include AWS access to the actual
account. They now carry this marker too. Don't treat their absence of a
marker in an earlier version of this repo as evidence they were verified;
they weren't, and the marker is the fix for that gap, not a downgrade.

The one output in this repo that *is* real end-to-end, not illustrative:
`tools/finops-scan-cli`'s test suite and sample report — those were
actually executed (against `moto`-mocked AWS, not the live account, but
genuinely executed code, not hand-written prose) and can be re-run by
anyone who clones the repo. That's a meaningfully different confidence
level than a phase README's example output, and the distinction matters:
"I ran this" and "this is what I expect it to look like when you run it"
are not interchangeable claims, and this repo doesn't blur them.

## 8. Benchmark every phase against the walkthrough map

`docs/walkthrough-map.md` is the segment-level source of truth, carried
forward from the original 11-series production blueprint. Before a phase
is marked done, every segment listed for its series gets one of three
states: represented in "The work" (even condensed — a paragraph can cover
what was a 5-minute segment), explicitly marked cut with a reason
recorded in the map itself, or missing. Missing segments are a defect,
not a style choice — record the score in `docs/coverage-scorecard.md`
after every phase is written or revised, using the same segment-by-segment
method, not an impression of how thorough it feels.

This check happens *before* a phase is called done, not as a retrospective
audit — writing a phase without opening `docs/walkthrough-map.md` first is
the failure mode this rule exists to prevent.

