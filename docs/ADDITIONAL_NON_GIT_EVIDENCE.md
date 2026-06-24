# Additional Non-Git Evidence

This section exists for cases where a working archive still preserves strong technical topology, but does not preserve a readable git history.

## eusy snapshot

- Source exists: `True`
- Regular files outside `.git`: `0`
- Assessment: The snapshot preserves strong repository topology for Ansible, Terraform, FluxCD, Terragrunt, Helm, and Kafka topic management, but the working trees are mostly empty and the local .git copies are incomplete.

## Observed topology

- `ansible/roles` -> audit, certbot, common, del_users, dns, docker, filebeat, hashicorp_balancer, hashicorp_vault, java, logstash, ms-defender, nginx, opensearch, opensearch_balancer, rudder, squid, tuning, ufw
- `infra/terraform` -> app01-dev, development, dns-internal, domain-zones, opensearch, postgresql_flexible, vault, vm
- `modules` -> ansible, common, environments, hub, infra, logger, opensearch, postgresql, vault
- `fluxcd` -> apps/base, apps/dev-k8s, clusters/dev-k8s, clusters/prod-k8s, infrastructure/base, infrastructure/dev-k8s, infrastructure/monitoring, infrastructure/prod-k8s
- `terragrunt-live` -> _global/environments, _global/hub, _global/infra, _global/logger, _global/opensearch, _global/postgresql, _global/redis, _global/vault, eusy_prod/westeurope
- `charts` -> kafka-topics/templates, web/templates
- `kafka-topics` -> migrations/topics, test/examples
- `terragrunt-modules` -> opensearch

## How to interpret this

- This does not prove authorship at commit level.
- It does support the claim of hands-on exposure to the relevant toolchain and repository structure.
- In practice, this is useful as secondary evidence next to the main commit-based portfolio.

## Caveats

- This is topology-based evidence, not commit-based evidence.
- Directory modification timestamps mostly reflect copy or import time, not original authoring time.
- The local .git copies under eusy are incomplete, so git history could not be read reliably.
