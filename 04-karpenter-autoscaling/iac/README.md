The EC2NodeClass and three NodePool manifests from this phase belong in
platform/karpenter/nodepools/ once that directory is populated for real.
The subnet/security-group karpenter.sh/discovery tags applied via AWS CLI
here should be backfilled into stacks/financial-rag-agent/terraform (the
VPC module) so a fresh `terraform apply` doesn't silently lose them — the
same drift risk flagged in Phase 02's iac/README.md for the VPC endpoints.
