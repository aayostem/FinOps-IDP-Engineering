# Walkthrough Map — Benchmark Reference

This is the segment-level source of truth every phase in `phases/` gets
checked against before it's considered done. It's a condensed version of
the original 11-series production blueprint, remapped onto this repo's
12-phase (00–11) structure. See `PRODUCTION-GUIDE.md` §8.

Segment titles are kept close to the original blueprint's wording so a
diff against a phase's `README.md` "The work" section is a straightforward
read-through, not a reinterpretation exercise. Where a segment was judged
cuttable (pure padding, or redundant with something video already shows
natively — see notes), it's marked `(cut — see note)` rather than silently
dropped, so the decision is visible and revisitable.

## Series 1 → Phases 00 + 01

1. Course Introduction & the Two Stacks — *(covered by README.md / ENGAGEMENT-BRIEF.md at repo level)*
2. What Is FinOps & The Three Phases (Inform/Optimize/Operate)
3. Environment Setup — *(Phase 00)*
4. First Cost Explorer Query — *(Phase 00)*
5. Cost by Service — *(Phase 01)*
6. Unit Economics — *(Phase 01, financial-rag-agent)*
7. The Six Required Tags — explained
8. Activating Tags & Finding Untagged Resources
9. Bulk Tagging Scripts
10. AWS Config Rule — Tag Enforcement
11. Cost by Region — Finding Stray Resources
12. The Savings Reality — What 30–60% Looks Like
13. Unit Economics Workshop (riskoracle — second worked example, different unit)
14. Baseline Document & Series 1 Complete — *(Phase 00)*

## Series 2 → Phase 02

1. Series 2 Intro — From Visibility to Action
2. gp2 vs gp3 — The Free 20%
3. Unattached EIPs
4. Stopped Instances & Their EBS Costs
5. Orphaned EBS Volumes
6. NAT Gateway Traffic — The Hidden Cost
7. VPC Endpoints — Eliminating NAT Costs
8. Old Snapshots & AMIs
9. Oversized CloudWatch Log Groups (retention policy)
10. Cost Anomaly Detection Setup
11. Waste Summary Script
12. Series 2 Complete — Updated Baseline

## Series 3 → Phase 03

1. Intro — Why `kubectl top` Lies
2. Installing Kubecost on EKS
3. The Kubecost UI Tour *(cut — see note: a live recording shows the UI natively; a narrated "tour" segment mattered more for audio-only production)*
4. Cost by Namespace — Team Chargeback
5. Cost by Deployment
6. Rightsizing Recommendations
7. Idle Cost Analysis
8. Network Cost Attribution (cross-AZ, egress — pays off Phase 02's per-AZ route table finding)
9. Kubecost Alerts (budget per namespace)
10. Efficiency Score
11. Series 3 Complete — First Kubecost Report

## Series 4 → Phase 04

1. Why the Cluster Autoscaler Is Not Enough
2. Karpenter Architecture (NodePool / EC2NodeClass)
3. IAM Roles & SQS Interruption Queue
4. Installing Karpenter
5. General-Purpose NodePool (financial-rag-agent)
6. Memory-Optimised NodePool (pgvector similarity search)
7. GPU NodePool (riskoracle)
8. Disruption Budgets & Consolidation
9. Watching Karpenter Work (live provision + consolidate)
10. Karpenter + Kubecost (before/after node efficiency)
11. The Drift Prevention Loop (weekly consolidation report)
12. Series 4 Complete

## Series 5 → Phase 05

1. Spot Economics & When to Use Spot
2. Instance Type Diversification
3. S3 Checkpoint Bucket
4. The ProductionCheckpointManager (Python class)
5. SIGTERM Handler for Graceful Shutdown (IMDS watcher)
6. Kubernetes Job with Spot Tolerations
7. Testing the Checkpoint System (manual interruption test)
8. financial-rag Ingestion on Spot (secondary target)
9. Spot Savings Dashboard in Kubecost
10. Interruption Metrics & Alerting
11. Series 5 Complete

## Series 6 → Phase 06

1. Series 6 Intro — Storage Is the Slow Killer
2. S3 Lifecycle Policies — financial-rag Documents
3. S3 Lifecycle for riskoracle Checkpoints
4. ECR Image Lifecycle
5. EBS Snapshot Lifecycle
6. RDS Stop/Start Lambda Scheduler
7. RDS Storage Autoscaling
8. pgvector Index Optimisation (Cost Angle) *(judgment call — may cut if it drifts into pure DB-perf territory with no cost delta shown)*
9. ElastiCache Right-Sizing
10. Reserved Instance Purchasing Strategy
11. The Monthly Storage Audit Script
12. Series 6 Complete

## Series 7 → Phase 07

1. Why Every FinOps Win Eventually Reverses
2. Team Topologies in Practice
3. What a Golden Path Actually Means
4. Why We Chose Backstage
5. Backstage Architecture
6. Installing Backstage on EKS
7. Registering the Two Stacks in the Catalog
8. The Cost Plugin — First Look
9. Platform Maturity Stages
10. Series 7 Complete

## Series 8 → Phase 08

1. The Scaffolder Architecture
2. The 5-Input Golden Path Template
3. Workload Type → NodePool Selection
4. Cost Estimate in the Scaffolder Form
5. Karpenter NodePool Template
6. S3 Lifecycle Policy Template
7. Kubecost Label Injection
8. ArgoCD Application Creation
9. Multi-Arch Docker Build
10. Testing the Golden Path End-to-End
11. Series 8 Complete

## Series 9 → Phase 09

1. The Day-Two Problem
2. The Kubernetes Plugin — Live Pod Status
3. Scale Action — With Cost Preview
4. Rollback Action — With Change Log
5. Log Streaming Without Cluster Access
6. Restart Action
7. riskoracle: Cancel Training Job (cost-saved-by-cancelling framing)
8. Audit Log of All IDP Actions
9. The Deployment Trace — Click to Running Pod
10. Series 9 Complete

## Series 10 → Phase 10

1. Closing the Loop — Why Visibility Changes Behavior
2. FinOps Backend Plugin — The Cost API
3. The Cost Card Frontend Component
4. Budget Alert Scheduler
5. Chargeback Reports & Anomaly Webhook
6. FinOps Homepage Dashboard
7. Troubleshooting — 6 Common Problems *(this is where a genuine cross-phase debugging moment belongs by design — don't skip it)*
8. Series 10 Complete

## Series 11 → Phase 11

1. The Platform Org Model
2. Running the Capstone Build (end-to-end through the IDP golden path)
3. Production Readiness Check — every control from every prior phase verified
4. The ROI Calculation
5. The CTO-Ready Before/After Report
6. What This Enables Going Forward — the client-facing forward-look
   (reframed from the original's career-focused framing; kept distinct
   from segment 8 below — this is the narrative, not the build steps)
7. The 18-Month Savings Projection (compounding effect of the IDP preventing regression)
8. `finops-scan` CLI — build, test, and ship (the literal work: added;
   not in the original blueprint — see phases/11-capstone-cto-report/README.md)
9. Course/Engagement Complete

## How this gets used

Before a phase's `README.md` is marked done (`PRODUCTION-GUIDE.md` §6),
every numbered segment above for that phase's series gets a yes/no: is
this represented in "The work," even in condensed form, or is it
deliberately cut with a reason recorded here? "I forgot about it" is not
a valid reason to skip a segment — see `docs/coverage-scorecard.md` for
the running score per phase.
