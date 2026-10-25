# Cloud Infrastructure Optimisation Report — Template

Generated in Phase 11 from `docs/baseline/finops-baseline.md`. Every number
below must trace to a dated entry in that file — this template has no
fields that get hand-typed from memory.

```
# Cloud Infrastructure Optimisation Report
Date: {{DATE}}
Prepared by: {{ENGINEER_NAME}}
Account: ${ACCOUNT_ID}
Engagement: Phases 00–11, FinOps + IDP Engineering

## Executive Summary

Monthly infrastructure spend across the two audited stacks reduced from
${{BASELINE_TOTAL}} to ${{FINAL_TOTAL}} — a {{PCT_REDUCTION}}% reduction,
achieved without service disruption or product code changes.

## Impact by Phase

| Phase | Initiative | Monthly Saving | Source entry |
|---|---|---|---|
| 02 | Waste elimination (gp2→gp3, EIPs, NAT) | ${{P2_SAVING}} | baseline §Phase 02 |
| 03 | Kubecost rightsizing | ${{P3_SAVING}} | baseline §Phase 03 |
| 04 | Karpenter node consolidation | ${{P4_SAVING}} | baseline §Phase 04 |
| 05 | Spot ML training | ${{P5_SAVING}} | baseline §Phase 05 |
| 06 | Storage & database automation | ${{P6_SAVING}} | baseline §Phase 06 |

## Platform Investment (Phases 07–10)

The IDP prevents the savings above from regressing. Without it, the
median engagement sees 40–60% of savings return within six months as new
engineers and services bypass the manual controls that produced them —
[cite the specific regression evidence gathered this engagement, if any,
rather than the industry-median figure alone].

## Recommended Next Actions

{{TODO — pulled from Phase 11 validation, not pre-written}}
```
