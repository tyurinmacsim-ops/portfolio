# Публичные Demo-Проекты

## 1. platform-engineering-demo

- Путь: [projects/platform-engineering-demo](../projects/platform-engineering-demo/README.md)
- Что показывает: `Terraform`, `Helm`, `Kubernetes`, `GitHub Actions`, `Prometheus`, `Grafana`, `Loki`, `kind`
- Что внутри:
  - bootstrap `kind`-кластера;
  - Terraform-установка observability stack;
  - деплой sample app с `/healthz`, `/readyz`, `/metrics`;
  - `ServiceMonitor`, `HPA`, `PDB`;
  - CI pipeline с validate и smoke этапами.
- Зачем это в портфолио:
  - это уже не описание опыта, а рабочий воспроизводимый артефакт;
  - техлид может быстро понять твой подход к platform engineering;
  - repo можно дать как прямую ссылку в отклике или рефералке.

## Как использовать в отклике

- Если нужен короткий аргумент: "В портфолио есть не только агрегированная статистика по рабочим репозиториям, но и отдельный публичный demo-проект, который воспроизводит мой стек на локальном kind-кластере."
- Если нужен технический аргумент: "В demo показал Terraform bootstrap, Helm-based observability, Kubernetes manifests, CI validate/smoke и эксплуатационные детали вроде изоляции kubeconfig и helm cache."
