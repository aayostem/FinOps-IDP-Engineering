# Phase 10 — Runbook

> **Draft — see the notice at the top of `README.md`. Output below is
> illustrative until this phase is recorded live.**

## 1. Scaffold the FinOps backend plugin

```bash
npx @backstage/cli new --select backend-plugin --option id=finops
yarn --cwd plugins/finops-backend add node-fetch @backstage/catalog-client @slack/web-api
```

## 2. Cost API — first version queries the wrong value (see README "What broke")

```typescript
// plugins/finops-backend/src/router.ts (initial, buggy version)
router.get('/cost', async (req, res) => {
  const namespace = req.query.namespace as string;
  const resp = await fetch(`${kubecostUrl}/allocation?window=30d&aggregate=namespace&filter=namespace:"${namespace}"`);
  // called with namespace = entity name ("financial-rag-agent"), not the
  // backstage.io/kubernetes-namespace annotation value ("financial-rag")
});
```

```bash
curl -s "http://localhost:7007/api/finops/cost?namespace=financial-rag-agent"
# -> {"namespace": "financial-rag-agent", "currentMonth": 0}
```

## 3. Fix — read the annotation value explicitly, everywhere in the query path

```typescript
// Corrected: the frontend card and the backend route both resolve the
// actual namespace from the annotation, never the entity name.
const namespace = entity.metadata.annotations?.['backstage.io/kubernetes-namespace'];
```

```bash
curl -s "http://localhost:7007/api/finops/cost?namespace=financial-rag" \
  | tee ../../docs/baseline/10-cost-card-before.txt
# re-test after deploying the fix:
curl -s "http://localhost:7007/api/finops/cost?namespace=financial-rag" \
  | tee ../../docs/baseline/10-cost-card-after.txt
```

## 4. Deploy the cost card frontend component

```bash
yarn --cwd packages/app add @internal/plugin-finops
# add <FinOpsCostCard /> to the service EntityPage per README
```

## 5. Update budget thresholds from placeholder to real baseline data

```bash
grep -A2 "Phase 06" ../../docs/baseline/finops-baseline.md | tee ../../docs/baseline/10-budget-thresholds.txt

# Update each Component's catalog-info.yaml annotation:
#   finops.io/monthly-budget: "<real trailing-30-day figure>"
# replacing Phase 03's placeholder ($5000 / $1500)
```

## 6. Budget alert scheduler

```bash
# Deployed as a Backstage backend scheduled task, cron '0 9 * * *'
# See README for the checkBudgets() implementation.
```

## 7. Chargeback report

```bash
curl -s "http://localhost:9090/model/allocation?window=lastmonth&aggregate=label:team&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key),\(.value.totalCost)"' \
  > ../../docs/baseline/10-chargeback.csv
cat ../../docs/baseline/10-chargeback.csv
```

## 8. Anomaly webhook

```bash
kubectl patch configmap kubecost-cost-analyzer -n kubecost --type merge -p \
  '{"data":{"alertConfigs":"{\"alerts\":[{\"type\":\"anomaly\",\"threshold\":0.20,\"slackWebhookUrl\":\"https://backstage.internal/api/finops/webhooks/kubecost\"}]}"}}'

# Manual test fire:
curl -X POST https://backstage.internal/api/finops/webhooks/kubecost \
  -H "Content-Type: application/json" \
  -d '{"type":"anomaly","namespace":"financial-rag","costIncrease":340,"percentageIncrease":28}' \
  | tee ../../docs/baseline/10-anomaly-webhook-test.txt
```

## 9. Homepage dashboard

```bash
# FinOps homepage plugin route added to app routes; org-wide view pulling
# from the same /cost endpoint across every catalog Component.
```

## 10. Append to the baseline document

```bash
cat >> ../../docs/baseline/finops-baseline.md <<EOF

## Phase 10 — FinOps Data Inside the IDP — $(date +%Y-%m-%d)

- Cost card live on every service page
- Fixed: cost API queried entity name instead of the
  backstage.io/kubernetes-namespace annotation value — $0 for every
  service until corrected
- Fixed: budget alert thresholds still Phase 03 placeholders three
  phases after a real baseline existed — updated from post-Phase-06 data
- Chargeback CSV: see 10-chargeback.csv
- Anomaly webhook tested: see 10-anomaly-webhook-test.txt
EOF
```

## Verification before moving to Phase 11

- [ ] Cost card shows non-zero, Kubecost-matching values for both stacks
- [ ] Budget thresholds reflect real data, not $5000/$1500 placeholders
- [ ] Chargeback CSV has no `__unallocated__` line
- [ ] Anomaly webhook test produces a visible Slack/log entry
- [ ] Phase 10 section appended to `docs/baseline/finops-baseline.md`
