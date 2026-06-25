# Матрица навыков DevOps

Раздел построен по заполненному опроснику на `100` технологий. Это self-assessment, но он полезен не средним баллом, а тем, что даёт честный профиль сильных и слабых зон.

- Всего технологий в опроснике: `100`
- На уровне `5+` (уверенная hands-on работа): `43`
- На уровне `7+` (production-эксплуатация): `26`
- На уровне `8/10`: `12`
- Средний балл по всей матрице: `4.29`

## Как это читать правильно

- Это не попытка показать «знаю всё». Низкие оценки по нерелевантным для профиля инструментам оставлены специально, чтобы не размывать картину.
- Реальный центр тяжести смещён в `Kubernetes`, `Terraform`, `Linux`, `Docker`, `GitLab CI/CD`, `Prometheus/Grafana`, `Vault`, `PostgreSQL`, `Redis`, `Python` и смежную эксплуатацию.
- Матрицу стоит читать вместе с публичными артефактами: backup/restore toolkit, k8s-box и демо-стендом.

## Распределение оценок

- `1-2/10`: `29` технологий
- `3-4/10`: `28` технологий
- `5-6/10`: `17` технологий
- `7-8/10`: `26` технологий
- `9-10/10`: `0` технологий

## Самые сильные технологии

- `8/10`: `Helm charts, Linux, bash scripting, docker, git, gitlab, gitlab-ci, grafana, kubernetes, prometheus, ssh, terraform`
- `7/10`: `ArgoCD, Python, alert manager, ansible, cert-manager, docker-compose, hashicorp vault, nginx, node exporter, postgresql, redis, s3`

## Фокус-зоны

### Kubernetes / platform delivery

- Средний балл по зоне: `6.9/10`
- Что видно: Сильный слой по контейнерной платформе, релизам и runtime-эксплуатации.
- Опорные технологии: `Helm charts 8/10, docker 8/10, kubernetes 8/10, ArgoCD 7/10, cert-manager 7/10`

### Terraform / automation / CI

- Средний балл по зоне: `7.4/10`
- Что видно: Наиболее плотный core-набор под реальную DevOps-работу: IaC, shell, Git, CI/CD и ручная автоматизация.
- Опорные технологии: `bash scripting 8/10, git 8/10, gitlab 8/10, gitlab-ci 8/10, ssh 8/10`

### Observability / SRE

- Средний балл по зоне: `6.2/10`
- Что видно: Хорошо читается production-мониторинг: метрики, алерты, exporters и эксплуатационная диагностика.
- Опорные технологии: `grafana 8/10, prometheus 8/10, alert manager 7/10, node exporter 7/10, victoria metrics 7/10`

### Stateful services / data ops

- Средний балл по зоне: `6.2/10`
- Что видно: Подтверждается не только деплой, но и эксплуатация баз, очередей, backup/restore и S3-процессов.
- Опорные технологии: `postgresql 7/10, redis 7/10, s3 7/10, clickhouse 6/10, kafka 6/10`

### Vault / security / network basics

- Средний балл по зоне: `5.8/10`
- Что видно: Есть рабочий слой по секретам, TLS, сетевым и хостовым настройкам, без попытки раздувать профиль до security engineer.
- Опорные технологии: `cert-manager 7/10, hashicorp vault 7/10, cloudflare 6/10, iptables / nftables 6/10, sysctl 6/10`

