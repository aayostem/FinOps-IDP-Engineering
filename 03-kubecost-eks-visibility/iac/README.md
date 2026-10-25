Kubecost's Helm values (kubecostToken placeholder, cloudIntegration
config) belong in platform/kubecost/ once that directory is populated —
not committed here as literal values since the token is a credential.
The two `kubectl patch` label fixes from this phase should be backfilled
into each stack's Helm chart (stacks/financial-rag-agent/helm,
stacks/riskoracle's equivalent) so the `team` label is set by the chart
itself, not left as an imperative patch that a fresh deploy would lose.
