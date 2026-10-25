# Phase 00 — Runbook

Every command below, in the order it was actually run. `${ACCOUNT_ID}` etc.
are the real placeholders used in the recorded session — never substitute a
literal value into this file.

## 1. Identity check

```bash
aws sts get-caller-identity
```
Expected:
```json
{
    "UserId": "AIDAxxxxxxxxxxxxxxxxx",
    "Account": "${ACCOUNT_ID}",
    "Arn": "arn:aws:iam::${ACCOUNT_ID}:user/engagement-readonly"
}
```

## 2. Cost Explorer access check (failed first attempt — see README "What broke")

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY --metrics BlendedCost \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text
```
First attempt:
```
An error occurred (AccessDeniedException) when calling the GetCostAndUsage
operation: User: arn:aws:iam::${ACCOUNT_ID}:user/engagement-readonly is not
authorized to perform: ce:GetCostAndUsage
```
Fix applied (IAM policy attach, outside this repo — engagement account
admin action). Re-run after 60s propagation:
```
12.47
```

## 3. EKS access check

```bash
aws eks list-clusters --query 'clusters' --output table
```
Expected: table listing `${CLUSTER_NAME}` among the returned clusters.

## 4. Environment variables — exported for the rest of the engagement

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REGION=us-east-1
export CLUSTER_NAME=financial-rag-staging-cluster
export START=$(date -d '30 days ago' +%Y-%m-%d)
export END=$(date +%Y-%m-%d)

echo "$ACCOUNT_ID | $REGION | $CLUSTER_NAME | $START -> $END"
```

macOS note: replace `date -d '30 days ago'` with `date -v-30d`.

## 5. Persist to shell profile (so the engagement survives a closed terminal)

```bash
cat >> ~/.finops-engagement-env <<'EOF'
export REGION=us-east-1
export CLUSTER_NAME=financial-rag-staging-cluster
EOF
echo 'source ~/.finops-engagement-env' >> ~/.bashrc
```
`ACCOUNT_ID`, `START`, `END` are re-derived per session rather than
persisted — they're either always-recomputable (`ACCOUNT_ID`) or meant to
roll forward (`START`/`END`).

## 6. Baseline capture

```bash
mkdir -p docs/baseline
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END \
  --granularity MONTHLY --metrics BlendedCost \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text \
  | tee docs/baseline/00-kickoff-total.txt
```

## 7. Seed the append-only baseline document

```bash
cat > docs/baseline/finops-baseline.md <<EOF
# FinOps Baseline — ${CLUSTER_NAME}

Append-only. Each phase adds a dated section below; nothing above a phase's
own entry is ever edited by a later phase.

## Phase 00 — Kickoff — $(date +%Y-%m-%d)

- Account: \${ACCOUNT_ID}
- Baseline monthly spend (BlendedCost, trailing 30d): \$$(cat docs/baseline/00-kickoff-total.txt)
- Access confirmed: Cost Explorer (read), EC2 (read), EKS (read)
EOF

cat docs/baseline/finops-baseline.md
```

## Verification before moving to Phase 01

- [ ] `aws sts get-caller-identity` returns the engagement account
- [ ] `aws ce get-cost-and-usage` returns a real number, not an error
- [ ] `docs/baseline/finops-baseline.md` exists with a Phase 00 entry
- [ ] `$ACCOUNT_ID $REGION $CLUSTER_NAME $START $END` all echo non-empty
