# FinOps + IDP Engineering — Live Engagement Repository

This is not a tutorial repo. It's the working repository from a real consulting
engagement, kept in the open so the engagement can double as a course.

Everything here — the Terraform, the Karpenter NodePools, the Backstage
templates, the phase-by-phase engagement logs — is what actually got typed,
run, and committed while doing this work. Nothing was scripted first and
demoed after. If a command failed during the engagement, the failure and the
fix are both in the log, not smoothed over.

Read [`ENGAGEMENT-BRIEF.md`](./ENGAGEMENT-BRIEF.md) first. It explains who the
client is, why the account numbers you'll see are never real ones, and why
the two stacks in `stacks/` are the ones actually being optimized on camera.

## How this repo is organized

```
FinOps-IDP-Engineering/
├── ENGAGEMENT-BRIEF.md        # the client, the constraints, the confidentiality model
├── PRODUCTION-GUIDE.md        # the rules every phase log is written and recorded against
├── stacks/                    # the two production stacks under optimization
│   ├── financial-rag-agent/   # RAG system — SEC filing Q&A, pgvector, EKS
│   └── riskoracle/            # GPU batch risk-model training, Spot-native
├── platform/                  # the IDP being built: Backstage, Karpenter, Kubecost config
├── phases/                    # the 12 phases — each one is a course module AND an engagement log
│   ├── 00-engagement-kickoff/
│   ├── 01-finops-fundamentals-unit-economics/
│   ├── ...
│   └── 11-capstone-cto-report/
├── docs/                      # baseline + CTO report templates, shared glossary
├── tools/
│   └── finops-scan-cli/       # standalone CLI — the engagement's diagnostic
│                               # core, packaged for anyone's AWS account
├── production/                # video production rules + per-phase scene
│                               # decompositions (Manim/Remotion/isostate +
│                               # Live Capture) — see production/VIDEO-PRODUCTION-RULES.md
└── scripts/                   # environment verification, shared helpers
```

## How to use this repo

**If you're following along as a course:** start at `phases/00-engagement-kickoff/`
and work forward. Each phase's `README.md` is the engagement log — read it like
you're the engineer who just finished writing it. Each phase's `runbook.md` is
every command, in order, with the real output and the real failure modes.

**If you're evaluating this as a hiring manager or client:** `docs/cto-report/`
has the format the engagement ends in. `phases/11-capstone-cto-report/` shows
how it gets produced from the baseline data collected in every prior phase.

## The two stacks

| Stack | What it is | Starting state | Role in this engagement |
|---|---|---|---|
| `financial-rag-agent` | Production RAG system answering questions over SEC filings — EKS, pgvector on RDS, ElastiCache, GPU embedding workers | Running, untagged, unaudited | The always-on service — rightsizing, tagging, IDP golden path |
| `riskoracle` | GPU batch risk-model training, nightly runs | Running On-Demand | The interruptible workload — Spot engineering, checkpointing |

Both are real, deployed stacks — not toy apps built for this course. Every
dollar figure recorded in `docs/baseline/` comes from `aws ce get-cost-and-usage`
run against a real account, with the account ID substituted for `${ACCOUNT_ID}`
before anything is committed. See `PRODUCTION-GUIDE.md` → "What never gets
committed" before you touch any file in this repo.

## The CLI tool

`tools/finops-scan-cli/` is a real, tested, installable package — not a
mockup. It's a standalone extraction of the Phase 01/02/06 diagnostic
logic: point it at an AWS account with read-only credentials, get a
dollar-denominated gap report in minutes. It's also the free front door
for the consulting engagement this repo documents — run it yourself
before reading further. See its own `README.md` for install and usage,
and `phases/11-capstone-cto-report/README.md` for why it exists.

## Status

Scaffolding in progress. Phase 00 and Phase 01 are the reference
implementation — every later phase is written to match their structure and
level of detail exactly. `tools/finops-scan-cli` v1 (tagging, waste,
S3-lifecycle checks) is built, installs, and passes its test suite against
mocked AWS — see `PRODUCTION-GUIDE.md` for what "done" means for the
phases that still reference it as `_TODO_`.
# FinOps-IDP-Engineering
