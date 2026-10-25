# Phase 11 — Runbook

> **Draft — see the notice at the top of `README.md`. Output below is
> illustrative until this phase is recorded live.**

## 1. Run the capstone build — one more service through the full golden path

```bash
# Via Backstage /create: name=capstone-validation-service, team=platform-test,
# traffic_tier=medium, needs_s3=true
curl -s http://localhost:7007/api/catalog/entities/by-name/component/default/capstone-validation-service \
  | jq '.metadata.annotations["backstage.io/errors"] // "none"'
```

## 2. Production readiness check — every phase's checklist, together

```bash
{
  echo "=== Karpenter ==="; kubectl get nodepools
  echo "=== Core namespaces ==="; kubectl get pods -n karpenter; kubectl get pods -n kubecost; kubectl get pods -n backstage; kubectl get pods -n argocd
  echo "=== Kubecost allocation ==="; curl -s "http://localhost:9090/model/allocation?window=1d&aggregate=namespace" | jq '.data[0] | keys'
  echo "=== Catalog Groups ==="; curl -s "http://localhost:7007/api/catalog/entities?filter=kind=Group" | jq -r '.items[].metadata.name'
} | tee ../../docs/baseline/11-production-readiness.txt
```

## 3. Duplicate-entity check — surfaces the real problem (see README "What broke")

```bash
curl -s "http://localhost:7007/api/catalog/entities?filter=kind=Group&filter=metadata.name=riskoracle" \
  | jq -r '.items[] | "\(.metadata.uid) origin: \(.metadata.annotations["backstage.io/managed-by-location"])"' \
  | tee ../../docs/baseline/11-catalog-duplicate-check.txt
```

## 4. Fix — remove the duplicate Group definition

```bash
# Remove the inline Group definition from riskoracle's own catalog-info.yaml,
# leaving infrastructure/backstage/groups.yaml as the single source.
curl -X POST http://localhost:7007/api/catalog/refresh \
  -H 'Content-Type: application/json' -d '{"entityRef":"group:default/riskoracle"}'

curl -s "http://localhost:7007/api/catalog/entities?filter=kind=Group&filter=metadata.name=riskoracle" \
  | jq '.items | length' | tee -a ../../docs/baseline/11-catalog-duplicate-check.txt
# -> 1
```

## 5. ROI calculation from the real baseline

```bash
grep -E "saving|Saving" ../../docs/baseline/finops-baseline.md | tee ../../docs/baseline/11-roi-summary.txt
```

## 6. Generate the CTO report

```bash
# Populate docs/cto-report/finops-final-report.template.md from the
# figures in 11-roi-summary.txt and finops-baseline.md — no hand-typed numbers.
```

## 7. Validate finops-scan against the real demo stacks (not just mocked AWS)

```bash
cd ../../tools/finops-scan-cli
pip install -e .
finops-scan run --profile financial-rag --region us-east-1 --output /tmp/capstone-scan.md
cat /tmp/capstone-scan.md | tee ../../docs/baseline/11-finops-scan-live-test.txt
```

## 8. Deploy the regression watchdog

```bash
zip /tmp/finops_watchdog.zip /tmp/finops_watchdog.py
aws lambda create-function --function-name finops-watchdog --runtime python3.11 \
  --handler finops_watchdog.lambda_handler --zip-file fileb:///tmp/finops_watchdog.zip \
  --role "arn:aws:iam::${ACCOUNT_ID}:role/LambdaBillingRole"

aws events put-rule --name finops-watchdog-weekly --schedule-expression "cron(0 9 ? * MON *)" --state ENABLED
echo "deployed" | tee ../../docs/baseline/11-watchdog-deployed.txt
```

## 9. Final baseline append and engagement close

```bash
cat >> ../../docs/baseline/finops-baseline.md <<EOF

## Phase 11 — Capstone — $(date +%Y-%m-%d)

- Full production readiness check run across all 11 prior phases together
- Fixed: duplicate riskoracle Group entity (registered via two catalog
  locations independently) — resolved to a single source of truth
- CTO report generated from real baseline data
- finops-scan validated against real demo stacks, published
- Regression watchdog deployed, weekly, \$50-equivalent drift threshold
- ENGAGEMENT COMPLETE
EOF
```

## Verification — engagement close

- [ ] Capstone test service created cleanly, zero catalog errors
- [ ] No duplicate catalog entities of any kind remain (`Group`, `Component`, or otherwise)
- [ ] CTO report generated with every figure traceable to `finops-baseline.md`
- [ ] `finops-scan` produces a real report against `financial-rag-agent`'s account, not just mocked AWS
- [ ] Regression watchdog Lambda confirmed `Active` in EventBridge
- [ ] Phase 11 section appended to `docs/baseline/finops-baseline.md`, marked ENGAGEMENT COMPLETE
