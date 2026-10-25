The NodePool patch (spot capacity-type on gpu-training) and the
EC2NodeClass metadataOptions fix from this phase should be backfilled
into platform/karpenter/nodepools/ as the canonical manifests, not left
as imperative kubectl patches — same drift risk noted in Phase 04's
iac/README.md. checkpoint_manager.py and imds_watcher.py belong in
stacks/riskoracle/ once that stack's source layout exists, baked into the
training container image rather than mounted as a ConfigMap in
production.
