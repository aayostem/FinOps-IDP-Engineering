# Changelog

## Unreleased

- Repo scaffolded: top-level structure, ENGAGEMENT-BRIEF, PRODUCTION-GUIDE
- Phase 00 (Engagement Kickoff), Phase 01 (Unit Economics & Tagging), and
  Phase 02 (Cloud Cost Audit) written to the reference-implementation
  standard: real command sequences, one genuine debugging moment each,
  numbers tables tied to named artifact files
- PRODUCTION-GUIDE.md §7 added: every phase not yet recorded live carries
  an explicit "Draft" notice distinguishing illustrative example output
  from actually-captured terminal output. Applied retroactively to
  Phases 00–02. Fixed a cross-phase reference bug in Phase 01 (pointed to
  "Phase 08" for the Kubecost cross-check; corrected to Phase 03)
- Phases 03–11 remain structured stubs per PRODUCTION-GUIDE.md
- `tools/finops-scan-cli/` — standalone CLI, v1 checks (tagging, waste,
  S3 lifecycle) implemented and genuinely tested (6 passing tests against
  moto-mocked AWS, not just syntax-checked); cluster-dependent checks
  (Phases 03-05, 07-10) registered as honest stubs, not faked
- Phase 11 (Capstone) updated to include shipping the CLI tool as a
  third deliverable alongside validation and the CTO report

## Unreleased (cont.)

- Phase 03 (Kubecost on EKS) written to the reference-implementation
  standard: cloud-integration-enabled install, cost-by-namespace and
  cost-by-team pulls, and a genuine debugging moment — pod labels
  (`app.kubernetes.io/part-of`) didn't match Kubecost's default
  `label:team` aggregation key, collapsing most spend into
  `__unallocated__` until an explicit `team` label was added to both
  stacks' Deployments. Fixed at the source (pod labels) rather than by
  reconfiguring Kubecost, since the Phase 07+ IDP work needs a clean
  `team` label on every pod anyway.

## Unreleased (cont. 2)

- Added `docs/walkthrough-map.md` — the original 11-series production
  blueprint's segment lists, persisted into the repo (not just chat
  history) as the permanent benchmark every phase gets checked against
  going forward, per PRODUCTION-GUIDE.md §8
- Added `docs/coverage-scorecard.md` — running phase-vs-map coverage score
- Phase 01 rewritten in full (not an addendum — a replacement): now covers
  all 14 Series 1 segments, up from 4/10 to 10/10. Added: the FinOps
  three-phase framing, full six-tags rationale, finding untagged resources
  (previously deferred to Phase 02), bulk-tagging (previously deferred to
  Phase 02), the finops-required-tags Config Rule (previously missing
  entirely), cost-by-region stray-resource scan (previously missing), the
  savings-reality expectation-setting table (previously missing), and a
  second unit-economics worked example on riskoracle (previously
  financial-rag-agent only)
- Phase 02 updated for continuity: removed the now-duplicate bulk-tagging
  step (fully owned by Phase 01 now), adjusted "Where we left off" and
  "Carries forward" accordingly. Phase 02's own coverage gap (orphaned
  EBS, old snapshots/AMIs, CloudWatch log retention, waste summary script)
  is unchanged and tracked in docs/coverage-scorecard.md as backlog

## Unreleased (cont. 3)

- Phase 02 backfilled to 10/10: added Orphaned EBS Volumes (distinct from
  stopped-instance EBS — never-attached vs. detached-when-stopped), Old
  Snapshots & unregistered AMIs, CloudWatch log group retention policy
  enforcement, and a consolidated Waste Summary Script tying gp2 + EIP +
  orphaned-EBS findings into one dollar total. That script's category
  logic is called out explicitly as the direct basis for
  `tools/finops-scan-cli`'s `waste` check.

## Unreleased (cont. 4)

- Phase 03 backfilled to 10/10: added Idle Cost Analysis (the dollar cost
  of the requested-vs-used gap, distinct from the efficiency percentage)
  and Kubecost budget-per-namespace alerts (placeholder thresholds,
  pending Phase 01's trusted baseline). UI Tour remains deliberately cut.
- Coverage backlog cleared: Phases 00-03 all at 10/10. docs/coverage-scorecard.md
  "Known backlog" section reset to empty.

## Unreleased (cont. 5)

- Phase 04 (Karpenter) written from scratch, benchmarked against the map
  from the first draft: 12/12 segments, 10/10. Covers Cluster Autoscaler
  removal, IAM/SQS setup, three NodePools (general-purpose,
  memory-optimized for pgvector, GPU for riskoracle), disruption budgets,
  live provision/consolidate demo, Karpenter+Kubecost efficiency
  cross-check, and the weekly drift-prevention report.
- Debugging moment: EC2NodeClass subnet discovery fails silently (pods
  stay Pending, no pod-level error) because this account's subnets carry
  the Cluster-Autoscaler-era tagging convention, not
  karpenter.sh/discovery — a second, distinct instance of the same
  per-AZ-networking characteristic Phase 02 found with route tables.
  Explicitly flagged as a pattern to check on every future migration
  step, not just this one.

## Unreleased (cont. 6)

- Phase 05 (Spot Instance Engineering) written from scratch against the
  map: 11/11 segments, 10/10. Covers instance-type diversification, the
  S3 checkpoint bucket, a real CheckpointManager Python class (periodic +
  SIGTERM-triggered emergency saves, load_latest on resume), a separate
  IMDS termination watcher, the Spot-tolerant Job with backoffLimit,
  financial-rag-agent's ingestion CronJob as the secondary Spot target,
  and Kubecost/interruption-metrics visibility.
- Debugging moment: the IMDS termination watcher can't reach
  169.254.169.254 from inside a pod — the shared EC2NodeClass from Phase
  04 never set metadataOptions, so it inherits AWS's default
  httpPutResponseHopLimit of 1, which blocks non-host-network pod traffic
  to IMDS. Fixed by raising the hop limit to 2 on the *shared* NodeClass,
  which also silently fixes the same latent issue for any future
  IMDS-dependent workload on the other two NodePools.

## Unreleased (cont. 7)

- Phase 06 (Storage & Database Controls) written from scratch against the
  map: 12/12 segments, 10/10. Covers S3 lifecycle on both stacks, ECR
  cleanup (with a real tagging-convention check before applying, not
  after), EBS snapshot lifecycle via DLM, RDS stop/start scheduling for
  non-production, RDS storage autoscaling with a ceiling, a narrowly
  cost-scoped look at financial-rag-agent's pgvector ef_search setting,
  ElastiCache rightsizing, an RI recommendation explicitly NOT
  auto-purchased, and a monthly storage audit script.
- Debugging moment: the naive S3 lifecycle policy on riskoracle's
  checkpoint bucket makes IA cost go UP, not down. Root cause: Standard-IA
  bills a 30-day minimum storage duration per object; riskoracle's active
  checkpoints get superseded every few hours, so transitioning them to IA
  at day 7 means paying the 30-day minimum on objects that don't live
  that long. Fixed by scoping the IA transition to run-status=archived
  checkpoints only, leaving actively-rotating ones on Standard where
  Phase 05's version-expiration rule already controls cost correctly.
- This closes the audit-and-fix arc (Phases 02-06). Phase 07 onward is
  the platform work that keeps it from reverting.

## Unreleased (cont. 8)

- Phase 07 (IDP Fundamentals) written from scratch against the map:
  10/10 segments. Covers Team Topologies framing, the golden-path
  definition, the Backstage-vs-alternatives reasoning scoped to this
  use case, Backstage architecture, Postgres-backed install on EKS,
  catalog registration, GitHub auto-discovery config, a first-look
  Kubecost API reachability check, and an honest platform-maturity
  self-assessment (Stage 1, not further).
- Debugging moment: a genuinely different kind from Phases 02-06 —
  Backstage catalog referential integrity, not AWS networking. The
  financial-rag-agent Component references owner: group:financial-rag,
  but no Group entity by that name was ever registered — the string
  matching Phase 01/03's tag and label convention doesn't satisfy
  Backstage's actual ownership model. Fixed by registering Group entities
  before the Components that reference them; carried forward explicitly
  as a requirement Phase 08's golden-path template must handle for
  brand-new teams.
- This starts the platform arc (Phases 07-11) — the first phase of this
  engagement that isn't primarily an AWS resource audit.

## Unreleased (cont. 9)

- Phase 08 (Backstage Scaffolder) written from scratch against the map:
  11/11 segments, 10/10. Covers the scaffolder architecture, the 5-input
  template, workload-type-to-NodePool selection, cost estimates
  calibrated against real Phase 03 Kubecost data (not placeholder
  numbers), the Karpenter/S3/Kubecost-label templates built correctly
  from the start (inheriting Phase 04/06/03's fixes rather than
  repeating their mistakes), ArgoCD app creation, multi-arch Docker
  builds, and a real end-to-end test.
- Explicitly closes Phase 07's carried-forward requirement: the template
  has an ensure-team-group step so a new team's Group entity is created
  before any Component references it as owner.
- Debugging moment: ArgoCD Application stuck Unknown/auth-required on the
  first-ever scaffolder-created repo — the GitHub App's installation
  scope doesn't automatically extend to repos created after the App was
  installed. Only surfaces on the first real run, since every repo
  touched in Phases 00-07 already existed before ArgoCD was configured.
  Fixed by adding an explicit scope-extension step to the template.

## Unreleased (cont. 10)

- Phase 09 (Golden Path Operations) written from scratch against the map:
  10/10 segments. Covers the day-two problem framing, read-only
  Kubernetes plugin RBAC, scale action with a real cost preview
  (cross-checked against Kubecost), rollback via ArgoCD (validated
  against Phase 08's GitHub App fix), CloudWatch-based log streaming
  with no kubeconfig, restart with disruption-budget awareness, the
  riskoracle cancel-training-job action, a Postgres-persisted audit log,
  and the full deployment trace tying every prior phase together.
- Debugging moment: cancel-training-job returns Forbidden using the
  general Kubernetes plugin credentials — correctly, since that RBAC is
  deliberately read-only. The mistake was reaching for the convenient
  existing credential instead of building scoped write access. Fixed
  with a narrowly-scoped Role (delete on batch/v1 jobs, riskoracle
  namespace only) used solely by this one action — the general RBAC
  stays untouched, reinforcing the least-privilege posture established
  since Phase 01 rather than trading it away for convenience.

## Unreleased (cont. 11)

- Phase 10 (FinOps Data Inside the IDP) written from scratch against the
  map: 8/8 segments, 10/10. Covers the cost API, the cost card, the
  budget alert scheduler, the chargeback CSV, the anomaly webhook, and
  the homepage dashboard.
- The map's own note on segment 7 ("Troubleshooting — 6 Common Problems")
  is honored as intent, not literally — two real, fully-explained
  cross-phase issues instead of six shallow ones: (1) the cost card
  queried the catalog entity name instead of the
  backstage.io/kubernetes-namespace annotation's actual value, echoing
  the exact financial-rag-agent-vs-financial-rag distinction Phase 03
  flagged three phases earlier; (2) budget alert thresholds were still
  Phase 03's placeholders, never updated once a real baseline existed
  after Phase 06 — a placeholder with no explicit owner for retiring it
  quietly became permanent.
- Confirmed as a payoff, not just a note: the chargeback CSV works
  correctly out of the box for any Phase 08-created service, because that
  template's automatic team pod label means it was never at risk of the
  __unallocated__ problem Phase 03 had to fix by hand.

## Unreleased (cont. 12) — ALL 12 PHASES NOW AT 10/10

- Phase 11 (Capstone) fully rewritten against the map: 9/9 segments,
  10/10 — supersedes the earlier draft that predated the benchmark rule.
  Resolved a small inconsistency in docs/walkthrough-map.md itself:
  segments 6 and 8 both referenced the CLI tool; split into 6 (the
  client-facing forward-look narrative) and 8 (the literal build/test/
  ship work) so neither is a duplicate of the other.
- Covers: the platform org model in retrospect, one final capstone
  service built end-to-end, a production readiness check run across
  every prior phase TOGETHER (not one at a time), the ROI calculation,
  CTO report generation, the 18-month savings projection, and
  finops-scan validated against the real demo stacks (not just mocked
  AWS) before being called shipped.
- Debugging moment, deliberately different from every prior phase's: not
  a new bug introduced this phase, but an existing one only visible when
  everything is checked together. Two Group entities named "riskoracle"
  exist in the catalog — one from Phase 07's groups.yaml, one defined
  inline inside riskoracle's own catalog-info.yaml at some later point
  (plausibly during Phase 08's template testing). Every individual
  phase's own verification step confirmed "a riskoracle Group resolves"
  — none checked whether it was the only one. This is the intended
  capstone lesson: integration validation catches what per-phase
  validation structurally cannot.
- Coverage scorecard: Phases 00 through 11 all at 10/10. This closes the
  full 12-phase benchmark-compliance pass across the entire repo.

## Unreleased (cont. 13)

- Added production/ — video production planning, separate from the
  engagement/course-content phases. VIDEO-PRODUCTION-RULES.md amends the
  cross-course Manim/Remotion/isostate constitution for this course
  specifically: a 60% hands-on floor (per phase, not just course-wide),
  Live Capture as a fourth, non-tool content category exempt from the
  40s/5-beat scene rules, and a draft-until-recorded discipline for every
  animated asset (mirrors PRODUCTION-GUIDE.md §7's convention, extended
  from repo docs to video assets).
- Added production/phase-01-decomposition.md — the actual Phase 1 plan:
  4 lectures, 23 items (8 Live Capture, 11 Remotion, 2 Manim, 1
  isostate), all rendered items marked provisional/unbuilt.

## Unreleased (cont. 14)

- Added production/phase-01-live-capture-shotlist.md — the actual
  recording guide for Phase 1's 8 Live Capture segments. Not a script:
  each segment has on-screen setup, narration beats in plain language,
  and explicit "let this go wrong on camera" notes for the two segments
  that are supposed to show a real failure (the Cost Explorer IAM error,
  the QueryCount metric gap) rather than cutting around them.

## Unreleased (cont. 15) — Phase 1 scene assets: built AND verified

- Built all 15 rendered assets for Phase 1 (2 Manim, 1 isostate, 12
  Remotion) — not just written, actually installed real toolchains and
  ran them in this environment:
  - Manim: installed manim 0.21.0 (required fixing missing system libs
    — pangocairo dev headers, then dvisvgm for MathTex — both genuine
    environment gaps, not code bugs). Both scenes' first drafts were
    3-4x under the 40s minimum because their docstrings' duration
    claims were never checked against a render; both rewritten with
    real additional content (not padding) and re-measured until they
    passed: 45.7s and 41.9s. Two real visual defects found via contact
    sheets and fixed: a traveling dot obscuring node labels (z-index),
    and a payoff comparison overflowing the frame edge (sizing/spacing).
  - isostate: the original scene file was wrong on nearly every field
    — written from a loose reading of the constitution's generic
    description rather than the real package schema. Rewritten against
    the actual shipped type definitions, then iterated against the real
    CLI's validate/compile errors (kebab-case IDs, integer-only size,
    normalized rx, connections-not-line-primitives for connectors).
    Validates clean, compiles to a working bundle, and beat 1 is
    confirmed correct via an actual jsdom-mounted SVG render converted
    to PNG. Beats 2-4 compiled but not yet visually confirmed (found and
    documented the AnimationEngine/AnimationController split that
    explains why — see RENDER-LOG.md).
  - Remotion: 4 reusable components (StaticSlide, DynamicSlide,
    ManimEmbed, IsostateEmbed) plus a new LiveCapture component (not in
    the base constitution — added per this course's amendment) and
    Phase1.tsx assembling all 23 decomposition items via TransitionSeries.
    Strict-mode type-checks clean against real remotion@4/react@18
    packages. Not yet rendered — headless Chromium wasn't obtainable in
    this sandbox.
- Added production/scenes/phase-01/RENDER-LOG.md — measured facts,
  replacing every estimated duration in the scene docstrings with what
  was actually rendered. Explicit about which of the three tools has
  full visual confidence (Manim), partial (isostate), and type-only
  (Remotion) — these are not being presented as equivalent.

## Unreleased (cont. 16) — isostate: full 4-beat verification closed out

- Closed the open item from the previous pass: all 4 beats of
  lecture3_aws_tags_vs_k8s_labels.isostate.yaml are now rendered and
  visually confirmed, not just beat 1.
- Found and fixed the real reason multi-beat playback wasn't working:
  `controller.setSceneIndex()` updates an internal pointer but doesn't
  trigger a DOM update by itself; `controller.setProgress()` against
  each beat's resolved progress value does. Also needed: explicit
  `controller: {}` in mountScene options, a ~700ms wait past the
  internal transition animation before reading the DOM, and a guard
  around an unrelated scroll-tracking timer that throws in jsdom's
  zero-dimension viewport.
- Found and fixed three real layout defects via actual visual inspection
  of each beat, not assumed from the YAML: the gap connector was
  originally nearly invisible (spanned two inner shapes sitting close
  together, not the two separated plane boxes); a label overlap and,
  separately, a 4-attempt struggle to place the final payoff line
  (overlap, left-edge clipping, an ELEMENT_OUTSIDE_FLOOR validator
  warning, then a contrast problem against the light floor) — each
  attempt grounded in what the previous real render actually showed,
  not a bigger guess. Full account in RENDER-LOG.md.
- Replaced the single stale beat-0-only evidence screenshot with
  production/scenes/phase-01/isostate/render-evidence/ (4 PNGs, one per
  beat, all post-fix).
- Isostate is now at the same full visual-confidence level as both
  Manim scenes. Remotion remains the one asset type still only
  type-checked, not rendered — flagged as the expected next gap, not
  papered over.

## Unreleased (cont. 17)

- Added production/phase-02-decomposition.md — Phase 2 (The Cloud Cost
  Audit) scene decomposition, benchmarked against Series 2's 12
  segments (docs/walkthrough-map.md) and the real runbook (section
  numbers confirmed against the actual file before citing them).
  5 lectures, 24 items: 11 Live Capture (~18 min, estimated — includes
  deliberate room for the route-table debugging moment, not compressed
  to make time), 1 Manim (gp2-vs-gp3 IOPS behavior — a genuine
  abstraction, not a disguised dashboard), 1 isostate (NAT Gateway vs.
  VPC Endpoint traffic flow), 11 Remotion. Live share ~76%, clearing the
  60% floor with more margin than Phase 1 — consistent with this being
  a more audit-command-dense phase. Nothing built yet, decomposition
  only, same stage Phase 1 started from.

## Unreleased (cont. 18)

- Added production/phase-02-live-capture-shotlist.md — recording guide
  for Phase 2's 11 Live Capture segments. Same discipline as Phase 1's:
  beats, not scripts; explicit setup/success criteria per segment.
  L3-S3 (the NAT Gateway route-table failure) is called out as the
  phase's real debugging moment with the same "let it play out, don't
  pre-fix" instruction as Phase 1's equivalent segments — and flagged
  as the longest live segment in the phase (3-4 min), not to be
  compressed. Also notes the dependency direction for post-recording
  reconciliation: the isostate/Manim draft scenes that set up L3-S1 and
  L1-S3 get revised to match what the live takes actually show, not the
  other way around.

## Unreleased (cont. 19) — Phase 03 correction, and a sandbox reset

- Found, while building Phase 3's video decomposition, that Phase 03's
  prior "10/10" coverage claim was wrong. Re-checking docs/walkthrough-map.md
  Series 3 line by line against the actual README (not against memory of
  having fixed it) found: Cost by Deployment and Network Cost Attribution
  were entirely absent, and Efficiency Score / Rightsizing Recommendations
  existed only in the numbers table and carries-forward, never narrated
  as real beats in "The work." All four fixed now — see
  phases/03-kubecost-eks-visibility/README.md and runbook.md (steps
  renumbered 8-13 to fit the two new ones in logically).
- Added a standing note to docs/coverage-scorecard.md: a score must come
  from re-reading the section against the map, not from recalling that
  the phase was already fixed. That's the actual mistake here, not the
  content being hard to write.
- Mid-correction, this working environment reset — every file under
  /home/claude was gone, with only the last exported zip in
  /mnt/user-data/outputs surviving. Restored the repo from that zip and
  redid every edit made since (this correction included) from scratch.
  Noting this plainly since it means anything between the last present_files
  call and the reset would have been silently lost if the zip hadn't
  already captured it — worth keeping export frequency high for exactly
  this reason.

## Unreleased (cont. 20)

- Added production/phase-03-decomposition.md — built only after
  correcting Phase 03's source content (prior entry), so every runbook
  reference actually exists. 4 lectures, 19 items: 11 Live Capture
  (~16.5 min — the highest live share of any phase so far, ~86%,
  reflecting that this phase is mostly querying a live Kubecost API and
  reading real output), 1 Manim (requested-vs-used gap, a genuine
  abstraction), 0 isostate, 7 Remotion.
- Deliberate choice: no new isostate scene for the __unallocated__
  debugging moment, even though it's this phase's centerpiece — it's
  the exact AWS-tags-vs-K8s-labels concept Phase 1's isostate diagram
  already covers. Reusing that callback instead of building a redundant
  second diagram, per VIDEO-PRODUCTION-RULES.md §6.

## Unreleased (cont. 21) — Phase 2 built end to end (depth-first, per request)

- Switched from breadth-first (decompose every phase, then shot-list
  every phase) to depth-first: complete one phase fully, then the next.
  Phase 2 now has decomposition + shot list (earlier) + rendered assets.
- Built and ran: 1 Manim scene (41.3s, rendered/measured/inspected),
  1 isostate scene (4 beats, validated + compiled first try, rendered,
  one real legibility defect fixed), and Phase2.tsx assembling all 24
  items (type-checked; real render blocked by sandbox network, same as
  Phase 1 — see production/scenes/phase-02/RENDER-LOG.md).
- Applied the new speed-first instruction deliberately: single blanket
  cosmetic fixes instead of multi-round pixel tuning; one contact sheet
  per asset instead of per-iteration; known minor issues logged rather
  than chased.
- Fixed a counting slip in phase-02-decomposition.md: Remotion items are
  5 scenes + 6 bumpers (11), not 6 + 5.

## Unreleased (cont. 22) — Recording walkthroughs

- Added production/walkthroughs/: two full technical hands-on walkthroughs
  (Phases 1-6 FinOps, 8:00; Phases 7-11 platform engineering, 10:00).
  Each has pre-flight, a corrections register, time-boxed segments with
  code, checkpoints, and failure paths.
- The corrections registers record real defects found in the draft
  runbooks (cost metric semantics, month-boundary cost windows, JMESPath
  string comparison, overwriting bulk tags, gp3 IOPS, DLM interval units,
  Karpenter v1 API, non-existent scaffolder actions, ArgoCD rollback with
  auto-sync, Backstage catalog conflict behaviour). The repo runbooks and
  READMEs are NOT yet synced to these - the walkthroughs take precedence.
