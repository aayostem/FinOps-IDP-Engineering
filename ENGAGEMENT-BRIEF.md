# Engagement Brief

## The premise, stated plainly

This repository documents a FinOps + Internal Developer Platform engagement
for an international client under NDA. The client's environment, account
IDs, internal Slack handles, and exact traffic numbers are never shown —
that's a confidentiality obligation, not a production choice.

What you're watching instead is the identical playbook run live, in the open,
against two real production stacks I own and operate: `financial-rag-agent`
and `riskoracle`. Same audit steps. Same tooling. Same order of operations I
use on client infrastructure. The numbers you see are real because they're
mine to show — not because I've reconstructed a client's environment for the
camera.

If a number in this repo looks smaller than a "$10M-raised, 40-engineer"
startup's AWS bill, that's because it is — these are two services, not an
entire company's infrastructure. The engagement methodology scales linearly;
the dollar figures don't, and I won't pretend otherwise. Where the client
engagement this mirrors operated at a different scale, `docs/cto-report/`
notes the scaling assumption explicitly rather than inflating the demo
numbers to match.

## Why this framing, not a generic tutorial

A CTO evaluating whether to hire a FinOps consultant doesn't want to watch a
sanitized demo app. They want to watch the actual judgment calls: which
finding gets fixed today versus flagged for a follow-up ticket, which Spot
interruption is a shrug and which one means switching instance families,
when "acceptable waste" beats "not worth the engineering risk yet." That
judgment only shows up when the infrastructure is real and the person
running the commands doesn't already know what they'll find.

## Confidentiality model — what this means in practice

- Every command in every runbook uses `${ACCOUNT_ID}`, `${CLUSTER_NAME}`,
  `${REGION}` — never a literal value. See `PRODUCTION-GUIDE.md`.
- Dollar figures come from real Cost Explorer / Kubecost output on the two
  stacks above. They are not projected, estimated, or rounded up for effect.
- Where a technique in this repo was learned or refined on client work, the
  client is never named, sized, or made identifiable, even indirectly (no
  "a fintech doing X" if X is specific enough to identify them).
- Screenshots and terminal recordings are re-run against the demo stacks
  before publishing, even if they were first validated on client
  infrastructure — nothing client-derived is ever pasted directly into a
  public artifact.

## Engagement scope (what the 12 phases cover)

| Phase | Deliverable |
|---|---|
| 00 | Environment access, baseline capture, engagement ground rules |
| 01 | Unit economics + tagging strategy — the Inform foundation |
| 02 | Cloud cost audit — immediate, identifiable waste eliminated |
| 03 | Kubecost on EKS — namespace/pod-level cost attribution |
| 04 | Karpenter — continuous node-level cost-aware autoscaling |
| 05 | Spot instance engineering for `riskoracle`'s GPU training |
| 06 | Storage + database cost controls (S3, ECR, RDS) |
| 07 | IDP fundamentals — why the savings above need a platform to hold |
| 08 | Backstage golden-path scaffolder |
| 09 | Self-service day-two operations via the IDP |
| 10 | FinOps data surfaced inside the IDP — cost visible to every developer |
| 11 | Capstone — validation, final baseline, CTO-ready report |

Phases 00–06 are the audit-and-fix engagement. Phases 07–11 are the platform
engagement that makes phases 00–06 permanent. Both are billed and delivered
as one engagement — see `phases/00-engagement-kickoff/README.md` for why.
