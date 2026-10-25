# Phase 00 — Engagement Kickoff

> **Draft — commands are correct and ready to run. Output shown below is
> illustrative, written to be realistic, but has not yet been captured
> live against the deployed stack. Replace every code block's output
> with the real captured output during recording, then delete this notice.**

## Where we left off

Nowhere yet. This is the start of the engagement. What follows is the
kickoff work every FinOps + IDP engagement opens with, before a single
dollar of waste gets touched: confirming access, confirming scope, and
capturing the number nobody can dispute later because it was captured on
day one, not reconstructed afterward.

## What we're solving today

Two things, and they're both boring on purpose. First: do I actually have
the access this engagement needs, and is it the *right* access — read-only
where read-only is enough, so nothing I do in week one can be mistaken for
having broken something. Second: what is the bill today, in a number that's
timestamped, saved, and immune to "I thought it was lower than that"
six weeks from now.

Every engagement I've run that skipped this step ended with a disagreement
about how much was actually saved. This step exists to prevent that
disagreement from being possible.

## The work

**Access verification.** I don't assume the IAM role I've been given does
what the scoping call said it would. I check.

```bash
aws sts get-caller-identity
```

This has to return a JSON blob with an Account, UserId, and Arn before
anything else in this engagement happens. If it doesn't, nothing below is
worth running — the account context would be wrong for every command that
follows.

**Scope the permissions, don't assume them.** The access request for this
engagement was: Cost Explorer read, EC2 read, EKS read, read-only on
everything else, write access scoped narrowly to the resources we'll
actually touch (tags, node groups, S3 lifecycle configs). I verify the two
that block the most work if missing:

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY --metrics BlendedCost \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text

aws eks list-clusters --query 'clusters' --output table
```

**Environment variables, exported once, used for the entire engagement.**
Not just this phase — every phase from here forward assumes these are set.

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REGION=us-east-1
export CLUSTER_NAME=financial-rag-staging-cluster   # substitute per stack
export START=$(date -d '30 days ago' +%Y-%m-%d)
export END=$(date +%Y-%m-%d)
```

**Capture the baseline — the number this whole engagement is measured
against.**

```bash
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END \
  --granularity MONTHLY --metrics BlendedCost \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text \
  | tee docs/baseline/00-kickoff-total.txt
```

I use `BlendedCost`, not `UnblendedCost`. Blended reflects what's actually
paid after any Savings Plans or Reserved Instance discounts already in
effect — the real number, not the list price. If this account has zero
committed spend, the two are identical; if it doesn't, Unblended
overstates the baseline and makes every later saving look bigger than it
is. I'd rather understate my own impact than inflate it.

## What broke and how it got fixed

First run of the Cost Explorer command came back with:

```
An error occurred (AccessDeniedException) when calling the GetCostAndUsage
operation: User: arn:aws:iam::${ACCOUNT_ID}:user/engagement-readonly is not
authorized to perform: ce:GetCostAndUsage
```

The scoping call said Cost Explorer read was included in the access grant.
It wasn't — `AWSBillingReadOnlyAccess` covers the Billing console, not the
Cost Explorer API, and they're granted by different managed policies. This
is common enough that I now check for it explicitly rather than assuming
"billing access" covers both. Fix was a one-line addition to the IAM
policy attached to the engagement role, confirmed via the same command
30 seconds after the policy propagated.

## Numbers, before and after

| Metric | Value | Source |
|---|---|---|
| Baseline monthly spend (BlendedCost, trailing 30d) | see `docs/baseline/00-kickoff-total.txt` | `aws ce get-cost-and-usage` |
| Access confirmed | Cost Explorer read, EC2 read, EKS read | this phase |

This phase produces no savings — it produces the number every later
phase's savings claim gets subtracted from.

## Carries forward

- `$ACCOUNT_ID`, `$REGION`, `$CLUSTER_NAME`, `$START`, `$END` exported and
  assumed set for every subsequent phase
- `docs/baseline/finops-baseline.md` created and seeded with the kickoff
  total (see `docs/baseline/README.md` for the append-only convention)
- Access confirmed for Cost Explorer, EC2, EKS — Phase 01 will need
  `AWSBillingReadOnlyAccess` *and* the Cost Explorer policy fix from above
  if working from a fresh IAM role

→ Phase 01 picks up here: same baseline number, first real question —
what does one unit of this business actually cost.
