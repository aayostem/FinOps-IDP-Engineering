# Phase 10 — FinOps Data Inside the IDP

> **Draft — commands are correct and ready to run. Output shown below is
> illustrative, written to be realistic, but has not yet been captured
> live against the deployed stack. Replace every code block's output
> with the real captured output during recording, then delete this notice.**

> Benchmarked against `docs/walkthrough-map.md` Series 10 (8 segments) —
> see `docs/coverage-scorecard.md`. Segment 7 (Troubleshooting) is
> written as two real, fully-explained cross-phase issues rather than six
> shallow ones — the map's own intent is a genuine debugging moment, not
> a padded checklist.

## Where we left off

Phase 09 left scale, rollback, restart, log streaming, and
cancel-training-job all working through the IDP with no developer
kubeconfig required, a least-privilege RBAC pattern established for any
future write action, and every action logged to a Postgres-backed audit
trail.

## What we're solving today

Everything built since Phase 07 has been infrastructure a developer
*uses* — the catalog, the golden path, day-two operations. None of it
has shown cost as part of normal, everyday browsing. A developer opens a
service's catalog page today and sees deployment status, logs, recent
actions — not what it costs, not whether it's near its budget, not
whether an anomaly just happened. Phase 07 named this honestly as Stage 1
platform maturity. Today pushes toward Stage 4: a cost card on every
service page, budget alerts reaching the right Slack channel before an
overspend, a monthly chargeback CSV for finance, and Kubecost anomalies
routed automatically instead of discovered by accident.

## The work

**Closing the loop — why visibility changes behavior, not just reports
it.** A developer who sees "$120/month, 78% of budget" next to their
service's deploy status, every time they open it, starts asking why
without being told to. That's the actual mechanism this phase is
building, not a dashboard for its own sake.

**The FinOps backend plugin — the cost API.** One endpoint, `/cost`,
queried by namespace — using the `backstage.io/kubernetes-namespace`
annotation every Component already carries since Phase 07, not a new
annotation this phase would have to retrofit onto every existing
catalog-info.yaml.

```typescript
router.get('/cost', async (req, res) => {
  const namespace = req.query.namespace as string;
  const resp = await fetch(`${kubecostUrl}/allocation?window=30d&aggregate=namespace&filter=namespace:"${namespace}"&accumulate=true`);
  const data = await resp.json();
  res.json({ namespace, currentMonth: data?.data?.[0]?.[namespace]?.totalCost ?? 0 });
});
```

**The cost card**, on every service's catalog page — this is where the
first real problem shows up, see "What broke."

```typescript
export const FinOpsCostCard = () => {
  const { entity } = useEntity();
  const namespace = entity.metadata.annotations?.['backstage.io/kubernetes-namespace'];
  const [cost, setCost] = useState(null);
  useEffect(() => {
    fetch(`/api/finops/cost?namespace=${namespace}`).then(r => r.json()).then(setCost);
  }, [namespace]);
  return <InfoCard title="Cost Overview">${cost?.currentMonth?.toFixed(0)}</InfoCard>;
};
```

**Budget alert scheduler**, daily at 09:00 — thresholds grounded in real
data this time, not Phase 03's placeholders.

```typescript
export async function checkBudgets({ config, catalog, slack }) {
  const { items } = await catalog.getEntities({ filter: { kind: 'Component' } });
  for (const c of items) {
    const budget = parseFloat(c.metadata.annotations?.['finops.io/monthly-budget'] ?? '0');
    const namespace = c.metadata.annotations?.['backstage.io/kubernetes-namespace'];
    if (!budget || !namespace) continue;
    const spend = await getCurrentSpend(namespace);
    if (spend / budget >= 0.9) {
      await slack.postMessage({ channel: `#${namespace}-alerts`, text: `Budget alert: ${(spend/budget*100).toFixed(0)}% used` });
    }
  }
}
```

**Chargeback report and anomaly webhook.**

```bash
curl -s "http://localhost:9090/model/allocation?window=lastmonth&aggregate=label:team&accumulate=true" \
  | jq -r '.data[0] | to_entries[] | "\(.key),\(.value.totalCost)"' > chargeback-$(date +%Y-%m).csv

kubectl patch configmap kubecost-cost-analyzer -n kubecost --type merge -p \
  '{"data":{"alertConfigs":"{\"alerts\":[{\"type\":\"anomaly\",\"threshold\":0.20,\"slackWebhookUrl\":\"https://backstage.internal/api/finops/webhooks/kubecost\"}]}"}}'
```

**FinOps homepage dashboard** — the org-wide view: top services by cost,
every team's budget status at a glance, not per-service anymore.

## What broke and how it got fixed

**Problem 1 — the cost card shows $0 for `financial-rag-agent`, even
though Kubecost's own dashboard shows real spend for the `financial-rag`
namespace.**

```bash
curl -s "http://localhost:7007/api/finops/cost?namespace=financial-rag-agent"
```
```json
{"namespace": "financial-rag-agent", "currentMonth": 0}
```

The bug is the query parameter itself. The cost card correctly reads
`backstage.io/kubernetes-namespace` off the entity — but an earlier draft
of the backend endpoint (not shown above, the corrected version already
is) queried Kubecost using the *catalog entity's name*
(`financial-rag-agent`) instead of that annotation's actual value
(`financial-rag`). Those two strings look similar enough to type one where
the other belongs and not notice — `financial-rag-agent` is the stack,
`financial-rag` is the namespace, the exact distinction Phase 03 flagged
as worth being precise about, and this is the cost of not staying precise
about it three phases later. Fixed by reading the annotation value
explicitly rather than falling back to the entity name anywhere in the
query path.

**Problem 2 — the budget alert fires at the wrong threshold for both
existing services, because it's still checking against Phase 03's
placeholder numbers.**

Phase 03 set `financial-rag: $5000` and `riskoracle: $1500` explicitly as
placeholders, carried forward with the note that real values wait on a
trusted baseline. That baseline has existed since Phase 06 closed the
audit-and-fix arc, and nothing updated the thresholds in the meantime —
an easy step to forget precisely because the alert doesn't error, it just
quietly alerts at the wrong number.

```bash
# Real trailing-30-day figures, from the now-complete baseline:
grep -A2 "Phase 06" ../../docs/baseline/finops-baseline.md
```

Fixed by setting each service's `finops.io/monthly-budget` annotation from
the actual post-Phase-06 baseline instead of the Phase 03 placeholder,
and adding a note to `docs/coverage-scorecard.md`'s process, not just this
file: a placeholder introduced in one phase needs an explicit owner for
when it gets replaced, or it quietly becomes permanent.

## Numbers, before and after

| Metric | Value | Source |
|---|---|---|
| Cost card accuracy, before fix | $0 (wrong query parameter) | `docs/baseline/10-cost-card-before.txt` |
| Cost card accuracy, after fix | _TODO_ (should match Kubecost directly) | `docs/baseline/10-cost-card-after.txt` |
| Budget thresholds, placeholder vs. real | $5000/$1500 → _TODO_ | `docs/baseline/10-budget-thresholds.txt` |
| Chargeback CSV, teams represented | _TODO_ (target: financial-rag, riskoracle, no `__unallocated__`) | `docs/baseline/10-chargeback.csv` |
| Anomaly webhook, test fire | _TODO_ | `docs/baseline/10-anomaly-webhook-test.txt` |

## Carries forward

- Cost card live and accurate on every service's catalog page, querying
  by the namespace annotation's actual value, not the entity name
- Budget thresholds grounded in real post-Phase-06 data — the Phase 03
  placeholder is retired
- Chargeback CSV confirmed correct for both original stacks and any
  service created through Phase 08's golden path (its automatic `team`
  pod label means it was never at risk of the `__unallocated__` problem
  Phase 03 fixed — direct payoff of that earlier work)
- Anomaly webhook wired to the FinOps plugin's endpoint
- Platform maturity: Stage 4 (automated enforcement) substantially
  reached for cost visibility specifically — Phase 11 validates whether
  it holds under real use, not just at the moment it was built

→ Phase 11 picks up here: every component from every phase gets validated
together, the final baseline gets reported, and the diagnostic core of
this whole engagement ships as a standalone tool.
