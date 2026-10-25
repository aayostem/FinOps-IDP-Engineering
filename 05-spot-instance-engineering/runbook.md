# Phase 05 — Runbook

> **Draft — see the notice at the top of `README.md`. Output below is
> illustrative until this phase is recorded live.**

## 1. Spot price-history check — instance diversification

```bash
for instance_type in g4dn.xlarge g4dn.2xlarge g5.xlarge; do
  echo "=== $instance_type ==="
  aws ec2 describe-spot-price-history \
    --instance-types "$instance_type" --product-descriptions "Linux/UNIX" \
    --availability-zone "${REGION}a" \
    --start-time "$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --query 'SpotPriceHistory[0].SpotPrice' --output text
done
```

## 2. S3 checkpoint bucket

```bash
aws s3 mb "s3://riskoracle-checkpoints-${ACCOUNT_ID}"
aws s3api put-bucket-versioning --bucket "riskoracle-checkpoints-${ACCOUNT_ID}" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-lifecycle-configuration --bucket "riskoracle-checkpoints-${ACCOUNT_ID}" \
  --lifecycle-configuration '{"Rules":[{"ID":"expire-old-checkpoints","Status":"Enabled",
    "NoncurrentVersionExpiration":{"NoncurrentDays":7},"Filter":{"Prefix":""}}]}'
```

## 3. Capture On-Demand baseline before switching to Spot

```bash
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END --granularity MONTHLY --metrics BlendedCost \
  --filter '{"Tags":{"Key":"Service","Values":["riskoracle"]}}' \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text \
  | tee ../../docs/baseline/05-cost-before.txt
```

## 4. Deploy checkpoint_manager.py and imds_watcher.py

```bash
# (files created per README — checkpoint_manager.py, imds_watcher.py —
# baked into the riskoracle-training container image in a real build)
kubectl create configmap riskoracle-checkpoint-code -n riskoracle \
  --from-file=checkpoint_manager.py --from-file=imds_watcher.py
```

## 5. Add Spot requirement to the gpu-training NodePool

```bash
kubectl patch nodepool gpu-training --type=merge -p '
{"spec":{"template":{"spec":{"requirements":[
  {"key":"karpenter.sh/capacity-type","operator":"In","values":["spot","on-demand"]}
]}}}}'

kubectl get nodepool gpu-training -o yaml | grep -A3 capacity-type
```

## 6. Deploy the Spot-tolerant training Job

```bash
kubectl apply -f - <<EOF
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
EOF

kubectl get pods -n riskoracle -l job-name=riskoracle-training-spot -w
```

## 7. Interruption test — first attempt fails here (see README "What broke")

```bash
kubectl exec -n riskoracle "$(kubectl get pod -n riskoracle -l job-name=riskoracle-training-spot -o jsonpath='{.items[0].metadata.name}')" \
  -- curl -s -m 2 http://169.254.169.254/latest/meta-data/spot/termination-time
# -> curl: (28) Connection timed out
```

## 8. Fix — raise the shared EC2NodeClass hop limit

```bash
kubectl patch ec2nodeclass default --type=merge -p '
{"spec":{"metadataOptions":{"httpPutResponseHopLimit":2}}}'

# Force replacement of the current GPU node so it picks up the new NodeClass:
kubectl delete node "$(kubectl get pod -n riskoracle -l job-name=riskoracle-training-spot -o jsonpath='{.items[0].spec.nodeName}')"
kubectl get pods -n riskoracle -l job-name=riskoracle-training-spot -w
```

## 9. Re-run the interruption test after the fix

```bash
kubectl exec -n riskoracle "$(kubectl get pod -n riskoracle -l job-name=riskoracle-training-spot -o jsonpath='{.items[0].metadata.name}')" \
  -- curl -s -m 2 http://169.254.169.254/latest/meta-data/spot/termination-time
# -> 200 (or 404 if no interruption currently scheduled — either is a real reachable response now)

NODE=$(kubectl get pod -n riskoracle -l job-name=riskoracle-training-spot -o jsonpath='{.items[0].spec.nodeName}')
aws ec2 terminate-instances --instance-ids \
  "$(aws ec2 describe-instances --filters Name=private-dns-name,Values="$NODE" \
      --query 'Reservations[0].Instances[0].InstanceId' --output text)"

kubectl get pods -n riskoracle -l job-name=riskoracle-training-spot -w
# -> confirm the retried pod's logs show "Resumed from step N" (N > 0), not step 0
kubectl logs -n riskoracle -l job-name=riskoracle-training-spot | grep -i "resumed from step" \
  | tee ../../docs/baseline/05-checkpoint-test-result.txt
```

## 10. financial-rag-agent ingestion CronJob on Spot

```bash
kubectl patch cronjob rag-ingestion -n financial-rag --type=merge -p '
{"spec":{"jobTemplate":{"spec":{"template":{"spec":{"tolerations":[
  {"key":"karpenter.sh/capacity-type","operator":"Equal","value":"spot","effect":"NoSchedule"}
]}}}}}}'
```

## 11. Spot cost in Kubecost, interruption metrics

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true&filter=capacitytype:spot" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.totalCost)"' \
  | tee ../../docs/baseline/05-cost-after.txt

kubectl get events --all-namespaces --field-selector reason=SpotInterruption \
  --sort-by='.metadata.creationTimestamp' | tail -20 \
  | tee ../../docs/baseline/05-interruption-rate.txt
```

## 12. Append to the baseline document

```bash
cat >> ../../docs/baseline/finops-baseline.md <<EOF

## Phase 05 — Spot Instance Engineering — $(date +%Y-%m-%d)

- gpu-training NodePool: spot with on-demand fallback
- Fixed: IMDS unreachable from pods — EC2NodeClass metadataOptions
  httpPutResponseHopLimit raised from default (1) to 2, cluster-wide
- Checkpoint recovery tested against a real node termination: see 05-checkpoint-test-result.txt
- Cost before/after: see 05-cost-before.txt / 05-cost-after.txt
- financial-rag-agent ingestion CronJob now Spot-tolerant
EOF
```

## Verification before moving to Phase 06

- [ ] `kubectl get nodepool gpu-training -o yaml` shows `spot` in capacity-type values
- [ ] IMDS curl from inside a pod returns a real response (200 or 404), not a timeout
- [ ] Checkpoint test shows a resumed step count > 0 after a forced node termination
- [ ] `05-cost-after.txt` shows a real Spot-window cost figure
- [ ] `financial-rag-agent`'s `rag-ingestion` CronJob has the Spot toleration applied
- [ ] Phase 05 section appended to `docs/baseline/finops-baseline.md`
