# Phase 03 — Runbook

> **Draft — see the notice at the top of `README.md`. Output below is
> illustrative until this phase is recorded live.**

## 1. Prerequisites

```bash
kubectl get nodes
kubectl cluster-info
helm version
```

## 2. Install Kubecost with cloud integration

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

kubectl get pods -n kubecost -w
```
Expect: `cost-analyzer`, `prometheus-server`, `prometheus-node-exporter`,
`prometheus-kube-state-metrics`, `kubecost-metrics` all `1/1 Running`.

## 3. Port-forward and first namespace pull

```bash
kubectl port-forward deployment/kubecost-cost-analyzer 9090 -n kubecost &

curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.totalCost)"' \
  | tee ../../docs/baseline/03-cost-by-namespace.txt
```

## 4. Efficiency scores

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.efficiency | . * 100 | round)%"' \
  | tee ../../docs/baseline/03-efficiency-scores.txt
```

## 5. Cost by team — first attempt (broken, see README "What broke")

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=label:team&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.totalCost)"' \
  | tee ../../docs/baseline/03-cost-by-team-before.txt
```

## 6. Fix — add explicit `team` pod label to both stacks

```bash
kubectl patch deployment rag-api -n financial-rag --type=merge -p \
  '{"spec":{"template":{"metadata":{"labels":{"team":"financial-rag"}}}}}'

kubectl patch deployment risk-trainer -n riskoracle --type=merge -p \
  '{"spec":{"template":{"metadata":{"labels":{"team":"riskoracle"}}}}}'

kubectl rollout status deployment/rag-api -n financial-rag
kubectl rollout status deployment/risk-trainer -n riskoracle
```

## 7. Cost by team — re-run after fix

```bash
# allow one Kubecost scrape interval (~1-5 min) before re-querying
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=label:team&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.totalCost)"' \
  | tee ../../docs/baseline/03-cost-by-team-after.txt
```

## 8. Cost by deployment — one level more specific than namespace

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace,deployment&accumulate=true&filter=namespace:\"financial-rag\"" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.totalCost)"' \
  | tee ../../docs/baseline/03-cost-by-deployment.txt
```

## 9. Idle cost analysis

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\tidle: $\(.value.idleCost // 0 | . * 100 | round / 100)"' \
  | tee ../../docs/baseline/03-idle-cost.txt
```

## 10. Network cost attribution — checking Phase 02's VPC endpoint fix

```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\tnetwork: $\(.value.networkCost // 0 | . * 100 | round / 100)"' \
  | tee ../../docs/baseline/03-network-cost.txt
```

## 11. Kubecost budget alerts per namespace

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
Placeholder thresholds — see README for why real values wait on Phase 01's
trusted baseline.

## 12. Rightsizing recommendations (input for Phase 04)

```bash
curl -s "http://localhost:9090/savings/requestSizing?window=7d&targetCPUUtilization=0.75&targetRAMUtilization=0.75" \
  | jq -r '.recommendations[] | "\(.containerName)\t\(.currentCPUReq)->\(.recommendedCPUReq)\t$\(.monthlySavings)"' \
  | tee ../../docs/baseline/03-rightsizing-recommendations.txt
```

## 13. Append to the baseline document

```bash
cat >> ../../docs/baseline/finops-baseline.md <<EOF

## Phase 03 — Kubecost on EKS — $(date +%Y-%m-%d)

- Kubecost installed with cloudIntegration.enabled=true
- Cost by namespace: see 03-cost-by-namespace.txt
- Efficiency scores: see 03-efficiency-scores.txt
- Fixed: cost-by-team query was collapsing into __unallocated__ — pods
  lacked an explicit \`team\` label; added to both stacks' Deployments
- Cost by deployment within financial-rag: see 03-cost-by-deployment.txt
- Idle cost per namespace: see 03-idle-cost.txt
- Network cost per namespace (Phase 02 VPC endpoint fix check): see 03-network-cost.txt
- Budget alerts configured (placeholder thresholds): financial-rag, riskoracle
- Rightsizing recommendations captured for Phase 04: see 03-rightsizing-recommendations.txt
EOF
```

## Verification before moving to Phase 04

- [ ] All 5 Kubecost pods `Running` and `1/1`
- [ ] `03-cost-by-namespace.txt` shows non-zero cost for `financial-rag` and `riskoracle`
- [ ] `03-cost-by-team-after.txt` shows spend attributed to real team names, not `__unallocated__`
- [ ] `03-cost-by-deployment.txt` identifies a top cost driver within `financial-rag`
- [ ] `03-idle-cost.txt` captured for both namespaces
- [ ] `03-network-cost.txt` captured — confirms (or disproves) Phase 02's VPC endpoint fix with a real number
- [ ] `kubecost-alerts` ConfigMap applied and Kubecost restarted to pick it up
- [ ] `03-rightsizing-recommendations.txt` has at least one recommendation per stack
- [ ] Phase 03 section appended to `docs/baseline/finops-baseline.md`
