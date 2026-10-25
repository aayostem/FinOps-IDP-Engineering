# Phase 04 — Runbook

> **Draft — see the notice at the top of `README.md`. Output below is
> illustrative until this phase is recorded live.**

## 1. Capture node count before (baseline for the phase)

```bash
kubectl get nodes --no-headers | wc -l | tee ../../docs/baseline/04-node-count-before.txt
```

## 2. Remove the Cluster Autoscaler

```bash
kubectl get deployment cluster-autoscaler -n kube-system 2>/dev/null \
  && kubectl delete deployment cluster-autoscaler -n kube-system \
  || echo "Cluster Autoscaler not found — skip"

kubectl delete clusterrolebinding cluster-autoscaler --ignore-not-found
kubectl delete clusterrole cluster-autoscaler --ignore-not-found
```

## 3. IAM role and SQS interruption queue

```bash
OIDC_PROVIDER=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

cat > /tmp/karpenter-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {"StringEquals": {
      "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
      "${OIDC_PROVIDER}:sub": "system:serviceaccount:karpenter:karpenter"
    }}
  }]
}
EOF

aws iam create-role --role-name "KarpenterControllerRole-${CLUSTER_NAME}" \
  --assume-role-policy-document file:///tmp/karpenter-trust-policy.json

aws sqs create-queue --queue-name "KarpenterInterruptionQueue-${CLUSTER_NAME}" \
  --attributes '{"MessageRetentionPeriod":"300"}'
```

## 4. Install Karpenter

```bash
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version v0.33.0 --namespace karpenter --create-namespace \
  --set settings.clusterName="$CLUSTER_NAME" \
  --set settings.interruptionQueue="KarpenterInterruptionQueue-${CLUSTER_NAME}" \
  --wait

kubectl get pods -n karpenter
```

## 5. Tag subnets for discovery — first attempt failed (see README "What broke")

```bash
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)

for subnet in $(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" \
    "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
    --query 'Subnets[].SubnetId' --output text); do
  aws ec2 create-tags --resources "$subnet" \
    --tags Key=karpenter.sh/discovery,Value="$CLUSTER_NAME"
  echo "Tagged: $subnet"
done

for sg in $(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" \
    "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
    --query 'SecurityGroups[].GroupId' --output text); do
  aws ec2 create-tags --resources "$sg" \
    --tags Key=karpenter.sh/discovery,Value="$CLUSTER_NAME"
done
```

## 6. EC2NodeClass

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

## 7. Three NodePools

```bash
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
      taints: [{key: workload, value: memory-intensive, effect: NoSchedule}]
  disruption: {consolidationPolicy: WhenUnderutilized}
EOF

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

kubectl get nodepools
```

## 8. Disruption budgets

```bash
kubectl apply -f - <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: rag-api-pdb, namespace: financial-rag}
spec: {minAvailable: 2, selector: {matchLabels: {app: rag-api}}}
EOF
```

## 9. Watch it work — first attempt failed here (see README "What broke")

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

kubectl get pods -l app=karpenter-test    # -> Pending, first attempt
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=20
# -> "no subnets matched selector" — fixed by step 5's corrected tagging

# Re-run after fix:
kubectl get nodes -l karpenter.sh/nodepool -w
kubectl get pods -l app=karpenter-test    # -> Running within ~60s
```

## 10. Node count after, and cleanup

```bash
kubectl get nodes --no-headers | wc -l | tee ../../docs/baseline/04-node-count-after.txt
kubectl delete deployment karpenter-test
```

## 11. Karpenter + Kubecost efficiency check

```bash
curl -s "http://localhost:9090/model/allocation?window=1d&aggregate=namespace" \
  | jq -r '.data[0] | to_entries[] | "\(.key)\t\(.value.efficiency)"' \
  | tee ../../docs/baseline/04-kubecost-efficiency.txt
```

## 12. Drift-prevention weekly report

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --since=168h \
  | grep -E "consolidat|disruption" | tail -20 | tee /tmp/karpenter-weekly-report.txt
```

## 13. Append to the baseline document

```bash
cat >> ../../docs/baseline/finops-baseline.md <<EOF

## Phase 04 — Karpenter — $(date +%Y-%m-%d)

- Cluster Autoscaler removed, Karpenter installed
- Fixed: EC2NodeClass found zero subnets — karpenter.sh/discovery tag
  was never applied under the CA-era tagging convention; corrected
- Three NodePools live: general-purpose, memory-optimized, gpu-training
- Node count before/after: see 04-node-count-before.txt / 04-node-count-after.txt
- Kubecost efficiency: see 04-kubecost-efficiency.txt
EOF
```

## Verification before moving to Phase 05

- [ ] `kubectl get nodepools` shows all three, no errors
- [ ] Test deployment schedules and runs without manual intervention
- [ ] `kubectl get deployment cluster-autoscaler -n kube-system` returns not-found
- [ ] `04-kubecost-efficiency.txt` shows improved efficiency vs. Phase 03's baseline
- [ ] Disruption budget confirmed active: `kubectl get pdb -n financial-rag`
- [ ] Phase 04 section appended to `docs/baseline/finops-baseline.md`
