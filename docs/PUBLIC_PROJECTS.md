# Публичные демо-проекты

## 1. platform-engineering-demo

- Путь: [projects/platform-engineering-demo](../projects/platform-engineering-demo/README.md)
- Что показывает: `Terraform`, `Helm`, `Kubernetes`, `GitHub Actions`, `Prometheus`, `Grafana`, `Loki`, `kind`

### Что внутри

- bootstrap `kind`-кластера;
- Terraform-установка observability-стека;
- деплой демонстрационного приложения с `/healthz`, `/readyz`, `/metrics`;
- `ServiceMonitor`, `HPA`, `PDB`;
- CI-пайплайн с validate и smoke-этапами.

### Зачем это в портфолио

- это уже не описание опыта, а рабочий воспроизводимый артефакт;
- техлид может быстро увидеть подход к platform engineering;
- репозиторий можно приложить как прямую ссылку в отклике или реферальной форме.
