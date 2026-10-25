# Phase 01 — FinOps Fundamentals & Unit Economics

> **Draft — commands are correct and ready to run. Output shown below is
> illustrative, written to be realistic, but has not yet been captured
> live against the deployed stack. Replace every code block's output
> with the real captured output during recording, then delete this notice.**

> Benchmarked against `docs/walkthrough-map.md` Series 1 (14 segments) —
> see `docs/coverage-scorecard.md`. This is a full replacement of an
> earlier version of this phase that only covered segments 3–7; segments
> 8–13 (find-untagged, bulk-tagging, Config Rule, region scan, savings
> reality, riskoracle workshop) were originally deferred to Phase 02 or
> dropped, which broke this phase's segment coverage. They belong here.

## Where we left off

Phase 00 gave us a timestamped baseline and confirmed access. We know the
account spends a real, specific amount per month. We don't yet know what
that number means — whether it's efficient, what's driving it, or which
line item to touch first, or whose resources are even accounted for.
That's what this phase closes, completely, before any waste gets touched
in Phase 02.

## What we're solving today

A monthly AWS bill, by itself, isn't a decision-making tool. Three things
fix that, and I'm doing all three today, not just the first one: unit
economics — what does one RAG query actually cost; tagging — applied
everywhere, not just activated; and enforcement — a Config Rule that keeps
tagging from decaying the moment this engagement ends and a new engineer
provisions something without knowing the convention exists.

**The three-phase loop, briefly, because everything else today is an
instance of it.** FinOps runs on Inform → Optimize → Operate, and it's a
loop, not a checklist. Today is entirely Inform — I'm not fixing anything
yet, I'm making sure nothing that gets fixed in Phase 02 onward is a guess.
Skipping Inform is why most cost-cutting projects find the same waste
again eighteen months later: nobody built the visibility that would have
caught it re-accumulating.

## The work

**Cost by service** — where the money's going, before anything else.

```bash
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END \
  --granularity MONTHLY --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[?Metrics.BlendedCost.Amount > `5`].[Keys[0],Metrics.BlendedCost.Amount]' \
  --output table
```

EC2 (the EKS node group) and RDS (pgvector) dominate `financial-rag-agent`
— expected for this architecture. Anything unexpected in the top five —
NAT Gateway running high, for instance — gets noted, not chased; that's
Phase 02's job, not today's.

**Unit economics on `financial-rag-agent`** — the calculation that turns
"the bill is too high" into "here's what one answered question costs."

```bash
TOTAL_COST=$(aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END \
  --granularity MONTHLY --metrics BlendedCost \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text)

TOTAL_QUERIES=$(aws cloudwatch get-metric-statistics \
  --namespace financial-rag-agent --metric-name QueryCount \
  --start-time ${START}T00:00:00Z --end-time ${END}T00:00:00Z \
  --period 2592000 --statistics Sum \
  --query 'Datapoints[0].Sum' --output text)

echo "Total: \$${TOTAL_COST} / ${TOTAL_QUERIES} queries"
```

See "What broke" below — this doesn't return a clean number on the first
attempt, and I'm leaving that in rather than smoothing it over.

**The six required tags, and why each one specifically** — not just a
list, because the reasoning is what makes someone apply them correctly
six months from now without re-reading a wiki page. `Environment`
separates production spend from noise. `Team` is the chargeback
dimension — the one that makes a monthly review conversation specific
instead of collective, and specific accountability is what produces
action. `Service` gives granular attribution below the team level — the
difference between "financial-rag costs $14,200" and "the llm-ingest
deployment inside financial-rag costs $9,600 of that $14,200." `ManagedBy`
says how a resource was created, so a fix goes in the right place —
Terraform, not the console. `CostCenter` is the finance rollup; `Owner` is
one named person, not a team alias, because "the team's responsibility"
in practice means nobody's.

**Activating tags for cost allocation** — a step with no visible effect
until you try to filter Cost Explorer by tag and get nothing back, which
is exactly why it's easy to skip and expensive to have skipped.

```bash
for tag in Environment Team Service ManagedBy CostCenter Owner; do
  aws ce update-cost-allocation-tags-status \
    --cost-allocation-tags-status TagKey=$tag,Status=Active
done
aws ce list-cost-allocation-tags --status Active --query 'CostAllocationTags[].TagKey' --output table
```

**Finding what's actually untagged** — activation doesn't tag anything by
itself; this is the inventory of the gap.

```bash
aws ec2 describe-instances \
  --query 'Reservations[].Instances[?!Tags || length(Tags)==`0`].[InstanceId,InstanceType]' \
  --output table

aws ec2 describe-volumes \
  --query 'Volumes[?!Tags || length(Tags)==`0`].[VolumeId,Size]' --output table

aws rds describe-db-instances \
  --query 'DBInstances[?!TagList || length(TagList)==`0`].[DBInstanceIdentifier]' --output table
```

**Bulk-tagging what's found** — placeholder `Team=unknown` /
`Service=unknown` where the real owner isn't known yet. A tagged-but-generic
resource shows up as "needs refinement" in every later report instead of
being invisible to it entirely, which is the actual difference that matters.

```bash
aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' \
  --output text | tr '\t' '\n' | while read -r id; do
    aws ec2 create-tags --resources "$id" \
      --tags Key=Environment,Value=production Key=Team,Value=unknown \
             Key=Service,Value=unknown Key=ManagedBy,Value=finops-engagement \
             Key=CostCenter,Value=engineering Key=Owner,Value=platform@cloudfrugal.com
done
```

**AWS Config Rule — making the tagging convention self-enforcing**, not
dependent on anyone remembering it exists.

```bash
aws configservice put-config-rule --config-rule '{
  "Name": "finops-required-tags",
  "Source": {"Owner": "AWS", "SourceIdentifier": "REQUIRED_TAGS"},
  "InputParameters": "{\"tag1Key\":\"Environment\",\"tag2Key\":\"Team\",\"tag3Key\":\"Service\",\"tag4Key\":\"ManagedBy\",\"tag5Key\":\"CostCenter\",\"tag6Key\":\"Owner\"}",
  "Scope": {"ComplianceResourceTypes": ["AWS::EC2::Instance","AWS::EC2::Volume","AWS::RDS::DBInstance","AWS::S3::Bucket"]}
}'
```

Worth knowing before recording this live: the first compliance evaluation
after creating this rule runs against whatever state existed *before* the
bulk-tagging step above finished propagating. If the rule is created and
checked in the same breath as the bulk-tag sweep, the first read can show
a wave of `NON_COMPLIANT` that looks like the tagging didn't work — it's
usually just evaluation lag, confirmed by re-checking a few minutes later.
Worth a beat on camera so it doesn't read as a failure.

```bash
aws configservice get-compliance-summary-by-config-rule \
  --config-rule-names finops-required-tags
```

**Cost by region — finding stray resources.** Nobody notices a test
instance spun up in the wrong region until an audit specifically looks.

```bash
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END --granularity MONTHLY --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=REGION \
  --query 'ResultsByTime[0].Groups[].[Keys[0],Metrics.BlendedCost.Amount]' --output table
```

If everything's in `us-east-1`, that's the expected result for this
account and the check still counted — a clean result isn't a skipped
check.

**The savings reality — setting expectations, briefly.** Across the kind
of audits this engagement runs, waste tends to cluster: overprovisioned
EC2 (25–40% of compute cost, fixed by Phase 03/04's rightsizing and
Karpenter work), gp2-vs-gp3 (roughly 20% of EBS cost, fixed next phase),
unattached EIPs (small individually, easy to accumulate), NAT Gateway
traffic that should be on VPC endpoints (often the single biggest
surprise), and storage with no lifecycle policy (Phase 06). Stating this
now sets what to expect from the next few phases — it's not a finding
about this account specifically until Phase 02 actually runs the checks.

**Unit economics workshop — `riskoracle`, a second worked example.**
`financial-rag-agent`'s unit is a query; `riskoracle`'s unit is a training
run, and the two aren't interchangeable — worth doing both so the method
generalizes instead of looking like a RAG-specific trick.

```bash
TRAINING_COST=$(aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END --granularity MONTHLY --metrics BlendedCost \
  --filter '{"Tags":{"Key":"Service","Values":["riskoracle"]}}' \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text)

TRAINING_RUNS=$(aws cloudwatch get-metric-statistics \
  --namespace riskoracle --metric-name TrainingRunsCompleted \
  --start-time ${START}T00:00:00Z --end-time ${END}T00:00:00Z \
  --period 2592000 --statistics Sum --query 'Datapoints[0].Sum' --output text)

echo "Cost per training run: \$${TRAINING_COST} / ${TRAINING_RUNS} runs"
```

This one depends on the `Service=riskoracle` tag actually being applied
correctly by the bulk-tagging step above — a direct, visible payoff of
doing the tagging work earlier in this same phase instead of after.

## What broke and how it got fixed

The `financial-rag-agent` `QueryCount` CloudWatch query came back empty:

```
None
```

The application emits this custom metric in code, but the metric
namespace was never actually wired up in the staging deployment — it
exists in the codebase, not in what's running. Rather than fabricate a
number, this is logged as an open item: unit economics for
`financial-rag-agent` specifically is a placeholder until the metric is
confirmed live, or until Phase 03's Kubecost allocation data can
cross-check it a different way. A course — or an engagement — that shows
a clean number here when the instrumentation isn't actually there yet is
worse than one that shows the gap honestly. Notably, the `riskoracle`
side of the same exercise (above) doesn't have this problem — its
`TrainingRunsCompleted` metric is real, so that half of today's unit
economics work produces an actual number even while the other half is
blocked.

## Numbers, before and after

| Metric | Value | Source |
|---|---|---|
| Top cost driver (financial-rag-agent) | EC2 (EKS nodes) | `aws ce get-cost-and-usage --group-by SERVICE` |
| Cost per RAG query | **pending** — see "What broke" | `docs/baseline/01-unit-economics-financial-rag.txt` |
| Cost per riskoracle training run | _TODO_ | `docs/baseline/01-unit-economics-riskoracle.txt` |
| Tags activated for cost allocation | 6/6 | `aws ce update-cost-allocation-tags-status` |
| Resources found untagged (pre-sweep) | _TODO_ | `docs/baseline/01-untagged-resources.txt` |
| Config Rule compliance, post-sweep | _TODO_ (target: 100% COMPLIANT) | `docs/baseline/01-config-compliance.txt` |
| Regions with spend | _TODO_ | `docs/baseline/01-cost-by-region.txt` |

## Carries forward

- Six tags activated **and applied everywhere** — not just activated;
  the untagged-resource gap from any earlier draft of this phase is closed
- `finops-required-tags` Config Rule live — new resources that skip
  tagging surface automatically, this doesn't depend on anyone remembering
  to check
- Region scan complete — any stray-region resources found are logged,
  classified, and handed to Phase 02 alongside the rest of the waste audit
  (region-scan *cleanup* is a Phase 02 action; today's job was finding it)
- Two unit economics threads: `riskoracle`'s cost-per-training-run is
  real; `financial-rag-agent`'s cost-per-query is blocked on the
  `QueryCount` metric, carried to Phase 03 for a Kubecost-based cross-check
- Phase 02 no longer needs to do a separate bulk-tagging pass — that's
  now fully owned here; Phase 02's own README has been trimmed accordingly

→ Phase 02 picks up here: tags are real and enforced, the top-line
breakdown and stray-region findings are known — now the actual waste
audit, resource by resource.
