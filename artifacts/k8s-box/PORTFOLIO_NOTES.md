# K8s-box в портфолио

Этот каталог добавлен в публичное портфолио как отдельный подтверждающий артефакт.

Что он показывает:

- `Terraform` + `Terragrunt` для `Yandex Cloud`;
- модульную сборку `VPC`, `security group`, `VPN VM`, `infra runner`, `Kubernetes cluster`, `Vault infra`, `ArgoCD`;
- `GitLab CI/CD` для `validate/plan/apply/verify/destroy`;
- profile-driven конфигурацию окружений `test/dev/prod`;
- эксплуатационные runbook-документы и bootstrap/maintenance automation;
- связку `ArgoCD` + соседний GitOps/runtime repo.

Что исключено из публичной копии:

- `.git`, `.env`, `.generated`, локальные runtime-файлы;
- клиентские VPN-конфиги;
- дублирующие рабочие каталоги;
- соседний приватный runtime-репозиторий `infrastructure`.

Состав текущей публичной копии:

- `136` файлов;
- `50` Terraform-файлов;
- `20` shell-скриптов;
- `10` HCL-файлов;
- `31` Markdown-документ.
