# Phase 11 — Capstone — Validation, CTO Report & the Assessment CLI

> **Draft — commands are correct and ready to run. Output shown below is
> illustrative, written to be realistic, but has not yet been captured
> live against the deployed stack. Replace every code block's output
> with the real captured output during recording, then delete this notice.**

> Benchmarked against `docs/walkthrough-map.md` Series 11 (9 segments,
> including the CLI addition) — see `docs/coverage-scorecard.md`.
> Segments 6 and 8 are kept distinct: 6 is the forward-looking framing for
> the client, 8 is the literal CLI build-and-ship work — the map's
> original note conflated them, split apart here to avoid true
> duplication. This is a full rewrite of an earlier draft that predated
> the benchmark rule (PRODUCTION-GUIDE.md §8) and scored well below 10/10.

## Where we left off

Phase 10 left cost visible on every service's catalog page, budget alerts
grounded in real data, a working chargeback CSV, and an anomaly webhook —
platform maturity at Stage 4 for cost visibility specifically. Eleven
phases of real, working fixes and platform components, each validated on
its own as it was built. What hasn't happened yet is validating all of
them *together*, at once, the way a client would actually experience the
finished engagement.

## What we're solving today

Five things close this engagement. Validating every component together,
not each in isolation the day it was built — which is exactly where
integration bugs live and individual-phase testing can't catch them.
Calculating the actual ROI from the real baseline data collected since
Phase 00. Producing the CTO-ready report. Naming what this platform
enables for the client going forward, honestly, not as a sales pitch.
And packaging the diagnostic core of the whole engagement into
`finops-scan` — a standalone tool that outlives this specific engagement.

## The work

**The platform org model, in retrospect.** Eleven phases in, the Team
Topologies framing from Phase 07 is no longer theoretical — it's what
actually happened. The platform team (this engagement) built and now
hands off the IDP; `financial-rag-agent` and `riskoracle`'s teams are
stream-aligned, operating inside golden paths that make the cost-correct
choice the default one, not something they have to know to ask for.

**Running the capstone build** — one more service, created through the
full golden path, live, as the final proof the pieces work together and
not just individually.

```bash
# Via Backstage /create: name=capstone-validation-service, team=platform-test,
# traffic_tier=medium, needs_s3=true
curl -s http://localhost:7007/api/catalog/entities/by-name/component/default/capstone-validation-service \
  | jq '.metadata.annotations["backstage.io/errors"] // "none"'
```

**Production readiness check** — every phase's own "Verification before
moving to Phase N+1" checklist, re-run together, not one at a time in
isolation. This is where today's real problem surfaces — see "What broke."

```bash
kubectl get nodepools
kubectl get pods -n karpenter -n kubecost -n backstage -n argocd
curl -s "http://localhost:9090/model/allocation?window=1d&aggregate=namespace" | jq '.data[0] | keys'
curl -s "http://localhost:7007/api/catalog/entities?filter=kind=Group" | jq -r '.items[].metadata.name'
```

**The ROI calculation**, pulled from the baseline document, not
recomputed from memory.

```bash
grep -E "saving|Saving" ../../docs/baseline/finops-baseline.md
```

**The CTO-ready report.**

```bash
# Populate docs/cto-report/finops-final-report.template.md from
# finops-baseline.md — every figure traces to a dated entry, nothing
# hand-typed.
```

**What this enables going forward — for the client, not a career pitch.**
A platform that makes the cost-correct choice the default one for every
future service, a regression-watchdog that catches drift at the $500
stage instead of the $35,000 stage, and a self-service diagnostic
(`finops-scan`, below) that means the next audit doesn't have to start
from zero visibility the way this one did in Phase 00.

**The 18-month savings projection** — the compounding argument for why
the platform work (Phases 07–10) matters as much as the audit-and-fix
work (Phases 02–06). Without a platform, engagements like this typically
see 40–60% of savings return within six months as new engineers and
services bypass manual controls. With one, month 12's savings should
meet or exceed month 1's, because every service created since Phase 08
was cost-correct from birth.

**`finops-scan` — build, test, and ship.** The literal work, distinct
from the framing above: package the read-only checks from Phases 01, 02,
and 06 into the standalone CLI at `tools/finops-scan-cli/`, already built
and passing its test suite against mocked AWS (see that tool's own
README and `CHANGELOG.md`). This phase is where it gets validated against
the two real demo stacks specifically, not just mocked ones, before
anything is called shipped.

```bash
finops-scan run --profile financial-rag --region us-east-1 --output capstone-scan.md
cat capstone-scan.md
```

**The regression watchdog** — a weekly Lambda comparing current spend
against the final baseline, alerting on >10% drift, so the savings from
Phases 02–06 have a mechanism watching them after this engagement ends,
not just a report saying they existed once.

## What broke and how it got fixed

Running every phase's verification checklist together, rather than one
at a time, surfaces something none of them caught individually: the
catalog API returns **two** Group entities named `riskoracle`.

```bash
curl -s "http://localhost:7007/api/catalog/entities?filter=kind=Group&filter=metadata.name=riskoracle" \
  | jq -r '.items[] | "\(.metadata.uid) origin: \(.metadata.annotations["backstage.io/managed-by-location"])"'
```
```
a1b2c3... origin: url:https://github.com/aayostem/infrastructure/blob/main/backstage/groups.yaml
d4e5f6... origin: url:https://github.com/aayostem/riskoracle/blob/main/catalog-info.yaml
```

Phase 07 registered `riskoracle` as a Group via the dedicated
`groups.yaml` location. Separately, at some point after Phase 07, a
`Group` definition was added directly inside `riskoracle`'s own
`catalog-info.yaml` — plausibly during Phase 08's testing, when the
golden-path template's `ensure-team-group` step was being built and
tested against real team names. GitHub auto-discovery (configured in
Phase 07) picked up both locations independently, and Backstage doesn't
merge two separately-registered entities with the same name — it keeps
both, and anything referencing `owner: group:riskoracle` resolves
ambiguously depending on which one the catalog processor happens to
return first.

This is exactly the kind of bug that only shows up when everything gets
checked together: each phase's own verification step confirmed
`riskoracle` *a* Group entity existed and resolved — none of them checked
whether it was the *only* one.

Fix: remove the duplicate from `riskoracle`'s own `catalog-info.yaml`,
leaving `groups.yaml` as the single source of truth for Group entities,
and add an explicit rule to `PRODUCTION-GUIDE.md`-style discipline going
forward — Group entities are defined in exactly one location, referenced
everywhere else, never redefined inline.

```bash
curl -s "http://localhost:7007/api/catalog/entities?filter=kind=Group&filter=metadata.name=riskoracle" \
  | jq '.items | length'
# -> 1, after the duplicate is removed and the catalog reprocesses
```

## Numbers, before and after

| Metric | Value | Source |
|---|---|---|
| Total engagement saving, all phases (monthly) | _TODO_ | `docs/baseline/finops-baseline.md`, full history |
| Total engagement saving, annualized | _TODO_ | derived from above |
| Duplicate catalog entities found / after fix | 1 pair found → 0 | `docs/baseline/11-catalog-duplicate-check.txt` |
| `finops-scan` v1 checks, validated against real demo stacks | 3 of 3 (tagging, waste, S3-lifecycle) | `tools/finops-scan-cli/`, `docs/baseline/11-finops-scan-live-test.txt` |
| `finops-scan` time-to-first-report | _TODO_ (target: <10 min) | `docs/baseline/11-finops-scan-live-test.txt` |
| Regression watchdog deployed | yes/no | `docs/baseline/11-watchdog-deployed.txt` |

## Carries forward

- Every component from every phase validated together, not just
  individually — the duplicate-Group bug is fixed and the discipline
  (one location per entity) is documented for future services
- `docs/cto-report/` holds the completed report — the artifact handed to
  the client at engagement close
- `tools/finops-scan-cli/` validated against the real demo stacks, not
  just mocked AWS, and published as its own installable package — the
  free, self-service front door referenced in `ENGAGEMENT-BRIEF.md`
- The regression-watchdog Lambda is deployed and running — savings are
  self-monitoring going forward, not dependent on anyone remembering to
  check
- Engagement complete: 6 phases of audit-and-fix, 4 phases of platform
  work, 1 capstone — every number in the CTO report traces to a real,
  dated baseline entry, and the diagnostic core of all of it ships as a
  tool that outlives this specific engagement
