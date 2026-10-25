# Phase 01 — Runbook

> **Draft — see the notice at the top of `README.md`. Output below is
> illustrative until this phase is recorded live.**

Assumes `$ACCOUNT_ID $REGION $CLUSTER_NAME $START $END` are exported per
Phase 00.

## 1. Cost by service

```bash
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END --granularity MONTHLY --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[?Metrics.BlendedCost.Amount > `5`].[Keys[0],Metrics.BlendedCost.Amount]' \
  --output table | tee ../../docs/baseline/01-spend-by-service.txt
```

## 2. Unit economics — financial-rag-agent (blocked, see README)

```bash
TOTAL_COST=$(aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END --granularity MONTHLY --metrics BlendedCost \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text)

TOTAL_QUERIES=$(aws cloudwatch get-metric-statistics \
  --namespace financial-rag-agent --metric-name QueryCount \
  --start-time ${START}T00:00:00Z --end-time ${END}T00:00:00Z \
  --period 2592000 --statistics Sum --query 'Datapoints[0].Sum' --output text)

echo "Total: \$${TOTAL_COST} / ${TOTAL_QUERIES} queries" \
  | tee ../../docs/baseline/01-unit-economics-financial-rag.txt
```

## 3. Activate the six tags for cost allocation

```bash
for tag in Environment Team Service ManagedBy CostCenter Owner; do
  aws ce update-cost-allocation-tags-status \
    --cost-allocation-tags-status TagKey=$tag,Status=Active
  echo "Activated: $tag"
done
aws ce list-cost-allocation-tags --status Active --query 'CostAllocationTags[].TagKey' --output table
```

## 4. Find untagged resources

```bash
{
  echo "=== EC2 ==="
  aws ec2 describe-instances \
    --query 'Reservations[].Instances[?!Tags || length(Tags)==`0`].[InstanceId,InstanceType]' --output table
  echo "=== EBS ==="
  aws ec2 describe-volumes \
    --query 'Volumes[?!Tags || length(Tags)==`0`].[VolumeId,Size]' --output table
  echo "=== RDS ==="
  aws rds describe-db-instances \
    --query 'DBInstances[?!TagList || length(TagList)==`0`].[DBInstanceIdentifier]' --output table
} | tee ../../docs/baseline/01-untagged-resources.txt
```

## 5. Bulk-tag what's untagged

```bash
aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' \
  --output text | tr '\t' '\n' | while read -r id; do
    aws ec2 create-tags --resources "$id" \
      --tags Key=Environment,Value=production Key=Team,Value=unknown \
             Key=Service,Value=unknown Key=ManagedBy,Value=finops-engagement \
             Key=CostCenter,Value=engineering Key=Owner,Value=platform@cloudfrugal.com
    echo "Tagged: $id"
done

aws ec2 describe-volumes --query 'Volumes[].VolumeId' --output text | tr '\t' '\n' | while read -r id; do
    aws ec2 create-tags --resources "$id" \
      --tags Key=Environment,Value=production Key=Team,Value=unknown \
             Key=Service,Value=unknown Key=ManagedBy,Value=finops-engagement \
             Key=CostCenter,Value=engineering Key=Owner,Value=platform@cloudfrugal.com
done

aws rds describe-db-instances --query 'DBInstances[].DBInstanceArn' --output text | tr '\t' '\n' | while read -r arn; do
    aws rds add-tags-to-resource --resource-name "$arn" \
      --tags Key=Environment,Value=production Key=Team,Value=unknown \
             Key=Service,Value=unknown Key=ManagedBy,Value=finops-engagement \
             Key=CostCenter,Value=engineering Key=Owner,Value=platform@cloudfrugal.com
done
```

## 6. AWS Config Rule — enforcement

```bash
aws configservice put-config-rule --config-rule '{
  "Name": "finops-required-tags",
  "Source": {"Owner": "AWS", "SourceIdentifier": "REQUIRED_TAGS"},
  "InputParameters": "{\"tag1Key\":\"Environment\",\"tag2Key\":\"Team\",\"tag3Key\":\"Service\",\"tag4Key\":\"ManagedBy\",\"tag5Key\":\"CostCenter\",\"tag6Key\":\"Owner\"}",
  "Scope": {"ComplianceResourceTypes": ["AWS::EC2::Instance","AWS::EC2::Volume","AWS::RDS::DBInstance","AWS::S3::Bucket"]}
}'

# First check may show evaluation lag against pre-tagging state — see README.
aws configservice get-compliance-summary-by-config-rule \
  --config-rule-names finops-required-tags

# Re-check after a few minutes
sleep 180
aws configservice get-compliance-summary-by-config-rule \
  --config-rule-names finops-required-tags | tee ../../docs/baseline/01-config-compliance.txt
```

## 7. Cost by region — stray resources

```bash
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END --granularity MONTHLY --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=REGION \
  --query 'ResultsByTime[0].Groups[].[Keys[0],Metrics.BlendedCost.Amount]' --output table \
  | tee ../../docs/baseline/01-cost-by-region.txt
```

## 8. Unit economics — riskoracle (second worked example)

```bash
TRAINING_COST=$(aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END --granularity MONTHLY --metrics BlendedCost \
  --filter '{"Tags":{"Key":"Service","Values":["riskoracle"]}}' \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text)

TRAINING_RUNS=$(aws cloudwatch get-metric-statistics \
  --namespace riskoracle --metric-name TrainingRunsCompleted \
  --start-time ${START}T00:00:00Z --end-time ${END}T00:00:00Z \
  --period 2592000 --statistics Sum --query 'Datapoints[0].Sum' --output text)

echo "Cost per training run: \$${TRAINING_COST} / ${TRAINING_RUNS} runs" \
  | tee ../../docs/baseline/01-unit-economics-riskoracle.txt
```

## 9. Append to the baseline document

```bash
cat >> ../../docs/baseline/finops-baseline.md <<EOF

## Phase 01 — Unit Economics, Tagging & Enforcement — $(date +%Y-%m-%d)

- Top cost driver: EC2 (EKS node group)
- Cost per RAG query: PENDING (QueryCount metric not yet emitting)
- Cost per riskoracle training run: see 01-unit-economics-riskoracle.txt
- Cost allocation tags activated + applied to all discoverable resources
- finops-required-tags Config Rule live: see 01-config-compliance.txt
- Cost by region: see 01-cost-by-region.txt
EOF
```

## Verification before moving to Phase 02

- [ ] `aws ce list-cost-allocation-tags --status Active` shows all 6 tags
- [ ] `01-untagged-resources.txt` and post-sweep re-check show the gap closed
- [ ] `aws configservice get-compliance-summary-by-config-rule` trends toward 100% COMPLIANT
- [ ] `01-cost-by-region.txt` captured — even a clean single-region result counts
- [ ] `01-unit-economics-riskoracle.txt` has a real number
- [ ] Open item (financial-rag-agent QueryCount) logged, not silently dropped
- [ ] Phase 01 section appended to `docs/baseline/finops-baseline.md`
