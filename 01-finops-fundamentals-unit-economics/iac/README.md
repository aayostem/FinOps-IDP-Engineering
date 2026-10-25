No infra changes this phase — cost allocation tag *activation* is an
account-level Cost Explorer setting, not a Terraform-managed resource.
Bulk resource tagging (the actual `aws ec2 create-tags` sweep) happens in
Phase 02 alongside the rest of the waste audit.
