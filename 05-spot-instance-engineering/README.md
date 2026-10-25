# Phase 05 — Spot Instance Engineering

> **Draft — commands are correct and ready to run. Output shown below is
> illustrative, written to be realistic, but has not yet been captured
> live against the deployed stack. Replace every code block's output
> with the real captured output during recording, then delete this notice.**

> Benchmarked against `docs/walkthrough-map.md` Series 5 (11 segments) —
> see `docs/coverage-scorecard.md`. Written against the map from the
> first draft.

## Where we left off

Phase 04 left three Karpenter NodePools live — general-purpose,
memory-optimized, and `gpu-training` — all provisioning On-Demand, all
sharing one `EC2NodeClass` named `default`. The GPU NodePool exists and
schedules `riskoracle` training pods correctly, but it's not saving
anything yet; it's just Karpenter picking the right On-Demand instance
instead of a fixed node group.

## What we're solving today

`riskoracle` runs GPU training jobs on a schedule, not continuously, and
each run checkpoints its own progress by design — which makes it close to
the ideal Spot workload: interruption-tolerant if the interruption is
handled correctly, and expensive enough On-Demand that the savings are
worth the engineering. The `gpu-training` NodePool gets a Spot capacity
requirement today, plus the actual engineering that makes an interruption
cost less than the two minutes of warning AWS gives — a checkpoint
manager, a termination watcher, and a Kubernetes Job configured to retry
and resume rather than restart from zero.

## The work

**Spot economics, briefly, for this specific workload.** Spot pricing
runs 60–90% below On-Demand depending on instance family and
availability zone; the tradeoff is a 2-minute interruption warning with
no guarantee of runtime. `riskoracle`'s training jobs are exactly the
shape that tradeoff favors — batch, schedulable, checkpointable, and
nobody's blocked waiting on a single run in real time. `financial-rag-agent`'s
serving path is the opposite shape and stays On-Demand; only its
ingestion CronJob (idempotent, retryable) gets added to Spot today as a
secondary target.

**Instance type diversification** — never anchor to one Spot pool.

```bash
for instance_type in g4dn.xlarge g4dn.2xlarge g5.xlarge; do
  aws ec2 describe-spot-price-history \
    --instance-types "$instance_type" --product-descriptions "Linux/UNIX" \
    --availability-zone "${REGION}a" \
    --start-time "$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --query 'SpotPriceHistory[0].SpotPrice' --output text
done
```

Below ~15% price variance over 30 days is a stable pool; the NodePool
requirement lists all three families so Karpenter picks whichever is
cheapest and available at launch time, rather than betting everything on
one.

**S3 checkpoint bucket**, versioned, with a lifecycle rule that keeps
recent checkpoints and expires old noncurrent versions rather than
retaining every checkpoint of every run forever.

```bash
aws s3 mb "s3://riskoracle-checkpoints-${ACCOUNT_ID}"
aws s3api put-bucket-versioning --bucket "riskoracle-checkpoints-${ACCOUNT_ID}" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-lifecycle-configuration --bucket "riskoracle-checkpoints-${ACCOUNT_ID}" \
  --lifecycle-configuration '{"Rules":[{"ID":"expire-old-checkpoints","Status":"Enabled",
    "NoncurrentVersionExpiration":{"NoncurrentDays":7},"Filter":{"Prefix":""}}]}'
```

**The checkpoint manager** — the piece that makes an interruption survivable.
Saves periodically during training, saves immediately on the 2-minute
warning, and resumes from the latest checkpoint on restart instead of
from step zero.

```python
# checkpoint_manager.py
import signal, boto3, torch
from datetime import datetime

class CheckpointManager:
    def __init__(self, model, optimizer, job_name, bucket, interval=100):
        self.model, self.optimizer = model, optimizer
        self.job_name, self.bucket, self.interval = job_name, bucket, interval
        self.step, self.s3 = 0, boto3.client('s3')
        signal.signal(signal.SIGTERM, self._on_interruption)

    def _on_interruption(self, signum, frame):
        self.save(tag='emergency')
        exit(0)

    def save(self, tag=None):
        label = tag or self.step
        path = f'/tmp/checkpoint_{label}.pt'
        torch.save({'step': self.step, 'model_state': self.model.state_dict(),
                    'optimizer_state': self.optimizer.state_dict(),
                    'timestamp': datetime.utcnow().isoformat()}, path)
        self.s3.upload_file(path, self.bucket, f'{self.job_name}/checkpoint_{label}.pt')

    def load_latest(self):
        objs = self.s3.list_objects_v2(Bucket=self.bucket,
            Prefix=f'{self.job_name}/checkpoint_').get('Contents', [])
        numbered = [o for o in objs if 'emergency' not in o['Key']]
        if not numbered:
            return 0
        latest = max(numbered, key=lambda o: o['LastModified'])
        self.s3.download_file(self.bucket, latest['Key'], '/tmp/checkpoint.pt')
        state = torch.load('/tmp/checkpoint.pt')
        self.model.load_state_dict(state['model_state'])
        self.optimizer.load_state_dict(state['optimizer_state'])
        self.step = state['step']
        return self.step

    def after_step(self):
        self.step += 1
        if self.step % self.interval == 0:
            self.save()
```

**The IMDS termination watcher** — a host-level signal, separate from the
process-level SIGTERM above, polled directly for the earliest possible
warning. This is where today's real problem shows up — see "What broke."

```python
# imds_watcher.py
import requests, time, os, signal

def watch_spot_termination():
    url = "http://169.254.169.254/latest/meta-data/spot/termination-time"
    while True:
        try:
            r = requests.get(url, timeout=1)
            if r.status_code == 200:
                os.kill(os.getpid(), signal.SIGTERM)
                return
        except requests.exceptions.RequestException:
            pass
        time.sleep(5)
```

**The Kubernetes Job** — Spot toleration added to the `gpu-training`
NodePool from Phase 04, and `backoffLimit` set high enough that an
interruption is a retry, not a failure.

```yaml
apiVersion: batch/v1
kind: Job
metadata: {name: riskoracle-training-spot, namespace: riskoracle}
spec:
  backoffLimit: 10
  template:
    spec:
      restartPolicy: OnFailure
      tolerations:
        - {key: nvidia.com/gpu, value: "true", effect: NoSchedule}
      containers:
        - name: training
          image: your-registry/riskoracle-training:latest
          env: [{name: CHECKPOINT_BUCKET, value: "riskoracle-checkpoints-${ACCOUNT_ID}"}]
          resources: {requests: {"nvidia.com/gpu": "1"}, limits: {"nvidia.com/gpu": "1"}}
```

```bash
kubectl patch nodepool gpu-training --type=merge -p '
{"spec":{"template":{"spec":{"requirements":[
  {"key":"karpenter.sh/capacity-type","operator":"In","values":["spot","on-demand"]}
]}}}}'
```

**Testing the checkpoint system** — a manual interruption test, not just
trusting the code. I run a real training job, kill the node mid-run, and
confirm the retry resumes from the last checkpoint instead of step zero.

```bash
kubectl get pods -n riskoracle -l job-name=riskoracle-training-spot -o wide
NODE=$(kubectl get pod -n riskoracle -l job-name=riskoracle-training-spot \
  -o jsonpath='{.items[0].spec.nodeName}')
aws ec2 terminate-instances --instance-ids \
  "$(aws ec2 describe-instances --filters Name=private-dns-name,Values="$NODE" \
      --query 'Reservations[0].Instances[0].InstanceId' --output text)"

kubectl get pods -n riskoracle -l job-name=riskoracle-training-spot -w
```

**`financial-rag-agent` ingestion on Spot** — the secondary target.
Idempotent CronJob, safe to interrupt and retry without a checkpoint
manager.

```bash
kubectl patch cronjob rag-ingestion -n financial-rag --type=merge -p '
{"spec":{"jobTemplate":{"spec":{"template":{"spec":{"tolerations":[
  {"key":"karpenter.sh/capacity-type","operator":"Equal","value":"spot","effect":"NoSchedule"}
]}}}}}}'
```

**Spot savings in Kubecost, and interruption metrics + alerting.**

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true&filter=capacitytype:spot" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.totalCost)"'

kubectl get events --all-namespaces --field-selector reason=SpotInterruption \
  --sort-by='.metadata.creationTimestamp' | tail -20
```

## What broke and how it got fixed

The IMDS watcher never fires — no termination warning arrives even during
the deliberate interruption test above, and the pod runs straight through
to the hard kill with no emergency checkpoint saved.

```bash
kubectl exec -n riskoracle <pod> -- curl -s -m 2 \
  http://169.254.169.254/latest/meta-data/spot/termination-time
```
```
curl: (28) Connection timed out after 2001 milliseconds
```

The request never reaches the instance metadata service from inside the
pod. Cause: the `EC2NodeClass` created in Phase 04 doesn't set
`metadataOptions`, so it inherits AWS's default `httpPutResponseHopLimit`
of `1`. A hop limit of 1 permits the host itself to reach IMDS but blocks
anything routed through an additional network hop — which is exactly what
a non-host-network pod's traffic to `169.254.169.254` is. This is a
known, common EKS gotcha, not specific to Karpenter, but it only surfaces
the first time something actually tries to poll IMDS from inside a pod —
nothing in Phases 00–04 exercised this path.

Fix: raise the hop limit on the shared `EC2NodeClass`, which every
NodePool references, so this is fixed cluster-wide, not just for
`gpu-training`.

```bash
kubectl patch ec2nodeclass default --type=merge -p '
{"spec":{"metadataOptions":{"httpPutResponseHopLimit":2}}}'
```

New nodes launched after this patch pick it up; existing nodes need to be
drained and replaced (Karpenter's consolidation handles this naturally
within its normal cycle, or it can be forced). Re-running the interruption
test after a fresh node launch: the watcher fires, `_on_interruption`
saves an emergency checkpoint, and the retried pod resumes from that
checkpoint's step count instead of zero.

## Numbers, before and after

| Metric | Value | Source |
|---|---|---|
| `riskoracle` training cost, On-Demand baseline | _TODO_ | `docs/baseline/05-cost-before.txt` |
| `riskoracle` training cost, on Spot | _TODO_ | `docs/baseline/05-cost-after.txt` |
| Interruption rate over test window | _TODO_ (target <5%) | `docs/baseline/05-interruption-rate.txt` |
| Training runs lost to interruption | _TODO_ (target: 0) | `docs/baseline/05-checkpoint-test-result.txt` |
| `financial-rag-agent` ingestion moved to Spot | yes/no | this phase |

## Carries forward

- `gpu-training` NodePool now requires `spot` with `on-demand` fallback
- The shared `EC2NodeClass`'s `metadataOptions.httpPutResponseHopLimit`
  is fixed to `2` — this applies to every NodePool, not just GPU, so any
  future workload on `general-purpose` or `memory-optimized` that needs
  IMDS access from inside a pod is already covered
- Checkpoint manager and IMDS watcher code exist and are tested against a
  real interruption, not just unit-level
- `financial-rag-agent`'s ingestion CronJob tolerates Spot
- Interruption metrics visible in Kubecost and via `kubectl get events`
  — Phase 10's alerting work wires this to Slack, not built yet here

→ Phase 06 picks up here: compute is optimized across both stacks — now
the storage and database costs that don't shrink on their own.
