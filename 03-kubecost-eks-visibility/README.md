# Phase 03 — Kubecost on EKS

> **Draft — commands are correct and ready to run. Output shown below is
> illustrative, written to be realistic, but has not yet been captured
> live against the deployed stack. Replace every code block's output
> with the real captured output during recording, then delete this notice.**

> Benchmarked against `docs/walkthrough-map.md` Series 3 (11 segments) —
> see `docs/coverage-scorecard.md`. Revision history: pass 1 added Idle
> Cost Analysis and Kubecost budget alerts. Pass 2 is a correction — a
> prior "10/10" claim for this phase was checked again and found wrong:
> Cost by Deployment and Network Cost Attribution were missing
> entirely, and Efficiency Score / Rightsizing Recommendations existed
> only in the numbers table and carries-forward, never narrated as real
> beats in "The work." All four are fixed in this pass — see
> CHANGELOG.md for the full account. The Kubecost UI Tour segment
> remains deliberately cut — see the map's note on why.

## Where we left off

Phase 02 closed with immediate waste eliminated on both stacks, VPC
endpoints correctly attached across every private-subnet route table
(not just a single "main" one — this account's networking is per-AZ), a
tag sweep applied everywhere Phase 01 left gaps, and Cost Anomaly
Detection live at a $50 threshold. Two open items carried forward: real
unit economics for `financial-rag-agent` is still pending a working
`QueryCount` metric, and Phase 04's Karpenter work needs to account for
the same per-AZ route table topology Phase 02 found.

Note on naming before this phase starts: `financial-rag-agent` is the
stack; `financial-rag` is the Kubernetes namespace it deploys into. Same
distinction applies conceptually to `riskoracle`. Every `kubectl` command
below uses the namespace name, every AWS CLI command uses the stack name
— worth being precise about which is which once Kubecost starts
aggregating by both.

## What we're solving today

Cost Explorer answers "how much did EC2 cost this month." It cannot
answer "which pod." Ten pods can share one EC2 instance, and Cost
Explorer has no visibility into how that instance's cost should split
between them. Today I deploy Kubecost so that question gets an actual
answer — cost by namespace, cost by deployment, and an efficiency score
that says not just what something costs but how much of what it costs is
actually being used.

This also finally unblocks the unit-economics open item from Phase 01:
Kubecost's allocation API can approximate cost-per-request even without
`financial-rag-agent`'s own `QueryCount` metric working, by combining pod
cost with request-count data pulled from the ingress controller instead.
Not as precise as the application's own instrumentation, but real enough
to stop blocking on a metric that isn't live yet.

## The work

**Prerequisites.**

```bash
kubectl get nodes                 # expect 3+ nodes, Ready
kubectl cluster-info
helm version                      # expect v3.x
```

**Install, with cloud integration enabled from the start** — this is the
part that's easy to skip and expensive to skip. Without it, Kubecost
prices everything at on-demand list rates, which overstates cost on any
resource already covered by a Savings Plan or Reserved Instance — the
exact BlendedCost-vs-list-price distinction Phase 00 already established
matters for this account.

```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm repo update
kubectl create namespace kubecost

helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --set kubecostToken="$KUBECOST_TOKEN" \
  --set cloudIntegration.enabled=true \
  --set prometheus.nodeExporter.enabled=true \
  --set global.prometheus.enabled=true
```

```bash
kubectl get pods -n kubecost -w
```
Waiting for five pods Running: `cost-analyzer`, `prometheus-server`,
`prometheus-node-exporter`, `prometheus-kube-state-metrics`,
`kubecost-metrics`.

**First cost-by-namespace pull**, once Prometheus has had time to collect
data (allow 30-60 minutes for a fresh install before efficiency numbers
mean anything).

```bash
kubectl port-forward deployment/kubecost-cost-analyzer 9090 -n kubecost &

curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.totalCost)"'
```

**Cost by team** — where today's real problem shows up.

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=label:team&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.totalCost)"'
```

**Cost by deployment** — one level more specific than namespace. Knowing
`financial-rag` costs $X tells me which team to talk to; knowing which
*deployment inside* `financial-rag` drives that cost tells me which
engineer to talk to and which service to actually optimize.

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace,deployment&accumulate=true&filter=namespace:\"financial-rag\"" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.totalCost)"'
```

If one deployment dominates — the embedding workers, usually, on this
architecture — that's the one worth a rightsizing conversation first,
not whichever one happens to be easiest to reason about.

**Efficiency score** — the single number that summarizes whether a
namespace's requested resources match what it actually uses.

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.efficiency | . * 100 | round)%"'
```

Target range for production workloads is 70–85%. Below 60% is waste.
Below 40% is significant waste — and significant enough that it's worth
checking whether the request was ever based on real usage data or just
copied from another service's manifest.

**Network cost attribution — checking whether Phase 02's fix actually
worked.** Phase 02 moved S3/DynamoDB traffic off the NAT Gateway onto
VPC endpoints. Kubecost's per-namespace network cost is the first place
that shows up as a number, not just an assumption that the endpoint
creation command succeeding meant the fix worked.

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\tnetwork: $\(.value.networkCost // 0 | . * 100 | round / 100)"'
```

If `financial-rag`'s network cost is low relative to its total, that's
Phase 02's fix actually paying off, visible here for the first time —
worth saying explicitly rather than letting it pass as just another
number.

**Idle cost analysis** — a different question from the efficiency score.
Efficiency says *how much of what's requested gets used*; idle cost says
*what that gap costs in dollars*, per namespace, which is the number that
actually motivates a rightsizing conversation.

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\tidle: $\(.value.idleCost // 0 | . * 100 | round / 100)"'
```

If `riskoracle`'s idle cost is high relative to `financial-rag`'s, that's
expected and not automatically a problem — GPU training jobs are bursty
by design, and provisioning for peak means idle time between runs. The
number matters in Phase 05, where Spot engineering is the actual answer
to `riskoracle`'s idle cost, not rightsizing its requests down.

**Kubecost alerts — budget per namespace.** Cost Anomaly Detection (Phase
02) watches the AWS-level bill; this watches Kubernetes-level namespace
spend specifically, which is the granularity that lets an alert say
"`financial-rag` is at 85% of its monthly budget" instead of just "AWS
spend moved."

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubecost-alerts
  namespace: kubecost
data:
  alerts.json: |
    {
      "alerts": [
        {"type": "budget", "window": "30d", "namespace": "financial-rag",
         "threshold": 5000, "notification": "slack"},
        {"type": "budget", "window": "30d", "namespace": "riskoracle",
         "threshold": 1500, "notification": "slack"}
      ]
    }
EOF
kubectl rollout restart deployment/kubecost-cost-analyzer -n kubecost
```

These two thresholds are placeholders — real values come from Phase 01's
baseline once `financial-rag-agent`'s and `riskoracle`'s actual monthly
spend is known with confidence, not guessed at in Phase 03.

**Rightsizing recommendations** — the output Phase 04's Karpenter work
actually consumes. Kubecost watches real usage against requested
resources over the window and recommends what the request *should* be,
at a target utilization that leaves headroom for spikes rather than
running at the edge.

```bash
curl -s "http://localhost:9090/savings/requestSizing?window=7d&targetCPUUtilization=0.75&targetRAMUtilization=0.75" \
  | jq -r '.recommendations[] | "\(.containerName)\t\(.currentCPUReq)->\(.recommendedCPUReq)\t$\(.monthlySavings)"'
```

`targetCPUUtilization=0.75` is deliberate, not a default left
unexamined — 100% target would mean zero headroom for a traffic spike.
Whatever this returns today is a recommendation, not an action; Phase 04
is where a NodePool actually gets sized around it.

## What broke and how it got fixed

The cost-by-namespace query works cleanly. The cost-by-team query doesn't
— almost all of the spend lands in a bucket called `__unallocated__`,
with `financial-rag` and `riskoracle` showing near-zero.

This isn't a Kubecost bug. `financial-rag-agent`'s Helm chart labels its
pods `app.kubernetes.io/part-of: financial-rag-agent` — a standard
Kubernetes recommended label — but never sets a bare `team` label.
Kubecost's default `aggregate=label:team` looks for a pod label literally
named `team`, and finds nothing, so every pod that doesn't have one falls
into `__unallocated__`. The AWS-side `Team` tag from Phase 01 and 02 lives
on EC2/EBS/RDS resources; it has no automatic relationship to a
Kubernetes pod label. Tagging the AWS resources and labeling the
Kubernetes pods are two different mechanisms, and nothing keeps them in
sync unless something is built to keep them in sync.

Two ways to fix this, and I take the second: patch every Deployment to
add an explicit `team` pod label matching the values used in the AWS
tags, rather than reconfiguring Kubecost's aggregation to read
`app.kubernetes.io/part-of` instead. Reasoning: the IDP work starting
Phase 07 is going to need a clean, explicit `team` label on every pod
anyway for the golden-path template's cost attribution — fixing it at the
source now means Phase 07 doesn't inherit this same gap.

```bash
kubectl patch deployment rag-api -n financial-rag --type=merge -p \
  '{"spec":{"template":{"metadata":{"labels":{"team":"financial-rag"}}}}}'
kubectl patch deployment risk-trainer -n riskoracle --type=merge -p \
  '{"spec":{"template":{"metadata":{"labels":{"team":"riskoracle"}}}}}'
```

Re-running the cost-by-team query after the rollout (and after Kubecost's
next scrape interval) shows spend correctly split between `financial-rag`
and `riskoracle` instead of collapsing into `__unallocated__`.

## Numbers, before and after

| Metric | Value | Source |
|---|---|---|
| `financial-rag` namespace cost (7d) | _TODO_ | `docs/baseline/03-cost-by-namespace.txt` |
| `riskoracle` namespace cost (7d) | _TODO_ | `docs/baseline/03-cost-by-namespace.txt` |
| `financial-rag` efficiency score | _TODO_ | `docs/baseline/03-efficiency-scores.txt` |
| `riskoracle` efficiency score | _TODO_ | `docs/baseline/03-efficiency-scores.txt` |
| `__unallocated__` cost, before team-label fix | _TODO_ | `docs/baseline/03-cost-by-team-before.txt` |
| `__unallocated__` cost, after team-label fix | _TODO_ (target: near zero) | `docs/baseline/03-cost-by-team-after.txt` |
| `financial-rag` idle cost (7d) | _TODO_ | `docs/baseline/03-idle-cost.txt` |
| `riskoracle` idle cost (7d) | _TODO_ (expect higher — bursty by design) | `docs/baseline/03-idle-cost.txt` |
| Top cost driver within `financial-rag` by deployment | _TODO_ | `docs/baseline/03-cost-by-deployment.txt` |
| `financial-rag` network cost (7d) | _TODO_ (checking Phase 02's VPC endpoint fix) | `docs/baseline/03-network-cost.txt` |
| Rightsizing recommendations captured | _TODO_ (count) | `docs/baseline/03-rightsizing-recommendations.txt` |
| Budget alerts configured | 2 (financial-rag, riskoracle — placeholder thresholds) | this phase |

## Carries forward

- Kubecost running, `cloudIntegration.enabled=true` so pricing reflects
  actual negotiated rates, not on-demand list price
- Every Deployment across both stacks carries an explicit `team` pod
  label matching the AWS-side `Team` tag value — this becomes the pattern
  the Phase 08 golden-path template enforces for every new service
- Rightsizing recommendations available via
  `/savings/requestSizing` for Phase 04's Karpenter work to consume
- Unit economics open item from Phase 01: now approximable via Kubecost
  allocation data cross-referenced with ingress request counts, even
  without `QueryCount` — no longer fully blocked, still not as precise as
  the application's own instrumentation would be
- `riskoracle`'s idle cost is noted as expected-high, not flagged for
  rightsizing — Phase 05's Spot engineering is the actual fix for that
  gap, and Phase 04 shouldn't try to "solve" it by shrinking requests
- Budget alerts live for both namespaces with placeholder thresholds —
  real thresholds get set once Phase 01's baseline spend is trusted
- Phase 02's VPC endpoint fix confirmed (or not) via real network-cost
  numbers this phase, not just assumed from the endpoint-creation
  command succeeding — first time that fix had a dollar figure behind it

→ Phase 04 picks up here: pod-level cost and efficiency are known per
namespace — now the question is whether the nodes underneath those pods
are sized and provisioned as efficiently as the pods running on them.
