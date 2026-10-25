# Phase 04 — Karpenter — Continuous Cost-Aware Autoscaling

> **Draft — commands are correct and ready to run. Output shown below is
> illustrative, written to be realistic, but has not yet been captured
> live against the deployed stack. Replace every code block's output
> with the real captured output during recording, then delete this notice.**

> Benchmarked against `docs/walkthrough-map.md` Series 4 (12 segments) —
> see `docs/coverage-scorecard.md`. Written against the map from the
> first draft, per PRODUCTION-GUIDE.md §8.

## Where we left off

Phase 03 left Kubecost running with cost correctly attributed by team,
rightsizing recommendations captured for both namespaces, idle cost known
(with `riskoracle`'s idle cost flagged as expected-high, not a rightsizing
target), and budget alerts live. One thing carried forward specifically
for today: this account's VPC uses per-AZ private subnets and route
tables, not a single "main" one — Phase 02 hit this with VPC endpoints,
and it matters again today for a different reason.

## What we're solving today

The rightsizing recommendations from Phase 03 tell me pods are
over-requesting resources. That's only half the problem — the nodes
underneath those pods were provisioned by the Cluster Autoscaler, which
picks from a fixed instance-type list per node group and takes 4–8
minutes to react to a pending pod. Today Karpenter replaces it: NodePools
that pick the cheapest instance type that actually fits the workload,
provisioning in under a minute, and consolidating continuously instead of
on a slow timer. Three NodePools, matched to what's actually running:
general-purpose for `financial-rag-agent`'s API and ingestion pods,
memory-optimized for the pgvector similarity search workload
specifically, and GPU for `riskoracle`'s training jobs.

## The work

**Why the Cluster Autoscaler isn't enough, concretely, not just in
theory.** It only adds a node after a pod is already `Pending` — 4–8
minutes of wait while it evaluates, calls EC2, and boots. It's rigid: one
or two instance types per node group, so a cheaper type becoming
available doesn't get used unless someone manually updates the group. And
it's slow to scale down — a 10–20 minute cooldown before an idle node
gets removed, which on a cluster that scales frequently is real, ongoing,
paid-for idle time.

**Remove it before installing Karpenter** — they fight over the same
nodes if both run.

```bash
kubectl delete deployment cluster-autoscaler -n kube-system
kubectl delete clusterrolebinding cluster-autoscaler
kubectl delete clusterrole cluster-autoscaler
```

**IAM role and SQS interruption queue.** Karpenter uses IRSA for EC2
permissions and an SQS queue to catch Spot interruption events at the
cluster level — needed now even though Spot workloads specifically don't
start until Phase 05, because retrofitting the queue later means
recreating the NodePool's interruption handling from scratch.

```bash
OIDC_PROVIDER=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

aws iam create-role --role-name "KarpenterControllerRole-${CLUSTER_NAME}" \
  --assume-role-policy-document file:///tmp/karpenter-trust-policy.json

QUEUE_URL=$(aws sqs create-queue \
  --queue-name "KarpenterInterruptionQueue-${CLUSTER_NAME}" \
  --attributes '{"MessageRetentionPeriod":"300"}' --query 'QueueUrl' --output text)
```

**Install Karpenter.**

```bash
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version v0.33.0 --namespace karpenter --create-namespace \
  --set settings.clusterName="$CLUSTER_NAME" \
  --set settings.interruptionQueue="KarpenterInterruptionQueue-${CLUSTER_NAME}" \
  --wait

kubectl get pods -n karpenter
```

**Tag subnets for discovery** — see "What broke," this is where today's
real problem is.

```bash
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)

for subnet in $(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" \
    "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
    --query 'Subnets[].SubnetId' --output text); do
  aws ec2 create-tags --resources "$subnet" \
    --tags Key=karpenter.sh/discovery,Value="$CLUSTER_NAME"
done
```

**EC2NodeClass — the shared AWS-side configuration every NodePool below
references.**

```bash
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2
  role: KarpenterNodeRole-${CLUSTER_NAME}
  subnetSelectorTerms:
    - tags: {karpenter.sh/discovery: ${CLUSTER_NAME}}
  securityGroupSelectorTerms:
    - tags: {karpenter.sh/discovery: ${CLUSTER_NAME}}
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs: {volumeSize: 50Gi, volumeType: gp3, encrypted: true}
EOF
```

**Three NodePools, matched to what's actually running.**

```bash
# General-purpose — financial-rag-agent API and ingestion
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata: {name: general-purpose}
spec:
  template:
    spec:
      nodeClassRef: {name: default}
      requirements:
        - {key: karpenter.k8s.aws/instance-family, operator: In, values: ["m5","m6i","t3"]}
  disruption: {consolidationPolicy: WhenUnderutilized}
EOF

# Memory-optimised — pgvector similarity search specifically
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata: {name: memory-optimized}
spec:
  template:
    spec:
      nodeClassRef: {name: default}
      requirements:
        - {key: karpenter.k8s.aws/instance-family, operator: In, values: ["r5","r6i"]}
      taints:
        - {key: workload, value: memory-intensive, effect: NoSchedule}
  disruption: {consolidationPolicy: WhenUnderutilized}
EOF

# GPU — riskoracle training (On-Demand for now; Spot toleration added Phase 05)
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata: {name: gpu-training}
spec:
  template:
    spec:
      nodeClassRef: {name: default}
      requirements:
        - {key: karpenter.k8s.aws/instance-family, operator: In, values: ["g4dn","g5"]}
      taints: [{key: nvidia.com/gpu, value: "true", effect: NoSchedule}]
  disruption: {consolidationPolicy: WhenEmpty}
EOF
```

**Disruption budgets, so consolidation can't drop production below a safe
replica count.**

```bash
kubectl apply -f - <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: rag-api-pdb, namespace: financial-rag}
spec: {minAvailable: 2, selector: {matchLabels: {app: rag-api}}}
EOF
```

**Watching it work.** Deploy a test workload that needs more than
current capacity, watch Karpenter provision, then scale it down and
watch consolidation happen within the `WhenUnderutilized` window rather
than the Cluster Autoscaler's 10–20 minute cooldown.

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: karpenter-test}
spec:
  replicas: 5
  selector: {matchLabels: {app: karpenter-test}}
  template:
    metadata: {labels: {app: karpenter-test}}
    spec:
      containers:
        - {name: stress, image: polinux/stress, resources: {requests: {cpu: "1", memory: "2Gi"}}}
EOF

kubectl get nodes -l karpenter.sh/nodepool -w
```

**Karpenter + Kubecost, before and after** — the node-level efficiency
number Kubecost reports should move once Karpenter's had a full day to
consolidate.

```bash
curl -s "http://localhost:9090/model/allocation?window=1d&aggregate=namespace" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.efficiency)"'
```

**The drift-prevention loop** — a weekly scheduled report, not a one-time
check, since node efficiency degrades again the moment nobody's watching.

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --since=168h \
  | grep -E "consolidat|disruption" | tail -20 > /tmp/karpenter-weekly-report.txt
```

## What broke and how it got fixed

The test deployment's pods stay `Pending` indefinitely — no new node
appears.

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=20
```
```
{"level":"ERROR","msg":"no subnets matched selector","nodepool":"general-purpose"}
```

This account's subnets were tagged for the Cluster Autoscaler's discovery
convention (`kubernetes.io/role/internal-elb`) but never carried a
`karpenter.sh/discovery` tag — nothing needed it until today. The
EC2NodeClass's `subnetSelectorTerms` looks specifically for that tag and
finds zero matches, so Karpenter has nowhere to launch a node, and fails
silently from the pod's perspective — it just stays `Pending` with no
error visible unless you specifically check the Karpenter controller
logs, not the pod's own events.

Fix: tag the actual private subnets — not the route tables this time,
the subnets themselves — with `karpenter.sh/discovery`, using the
existing `internal-elb` tag as the filter to find the right ones (the
`create-tags` command in "The work" above already reflects this fix, not
the broken first attempt). Re-applying the EC2NodeClass after the subnet
tags propagate, the test deployment schedules within about 60 seconds.

Worth being explicit about for anyone following along: this is a second,
distinct instance of the same underlying account characteristic Phase 02
found (per-AZ networking, not a single conventionally-tagged resource) —
worth checking subnet and route table tagging explicitly on any
migration step from here forward, rather than assuming AWS default
conventions hold.

## Numbers, before and after

| Metric | Value | Source |
|---|---|---|
| Node count before Karpenter (Cluster Autoscaler) | _TODO_ | `docs/baseline/04-node-count-before.txt` |
| Node count after Karpenter, steady state | _TODO_ | `docs/baseline/04-node-count-after.txt` |
| Time to provision a node (Karpenter vs. CA's 4-8 min) | _TODO_ | `docs/baseline/04-provision-time.txt` |
| `financial-rag` node-level efficiency, before/after | _TODO_ | `docs/baseline/04-kubecost-efficiency.txt` |
| `riskoracle` node-level efficiency, before/after | _TODO_ | `docs/baseline/04-kubecost-efficiency.txt` |
| Estimated monthly compute saving | _TODO_ | `docs/baseline/04-compute-savings.txt` |

## Carries forward

- Karpenter live with three NodePools: general-purpose, memory-optimized
  (tainted for pgvector-specific workloads), GPU (On-Demand for now)
- Disruption budgets protecting `financial-rag-agent`'s production
  replica count from over-aggressive consolidation
- Subnets correctly tagged `karpenter.sh/discovery` — the fix here
  matters again in Phase 05, where the GPU NodePool gets a Spot
  requirement added; if that NodePool references a different subnet
  selector, the same failure mode can recur
- Weekly drift-prevention report scheduled, not a one-time check
- Cluster Autoscaler fully removed — no dual-autoscaler conflict risk
  going forward

→ Phase 05 picks up here: the GPU NodePool exists and provisions
On-Demand correctly — now it gets a Spot requirement and the checkpoint
engineering to make interruption harmless for `riskoracle`'s training
runs.
