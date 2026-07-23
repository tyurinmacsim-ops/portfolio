# Дополнительные данные по tgbot/tgbots

Этот раздел собран по локальному архиву `ZeroOneTech`, но намеренно ограничен только путями `tgbot` и `tgbots`. Здесь не используются чужие проектные контуры и любые зоны вне реальной области работы. Также не публикуются raw-конфиги с секретами, рабочие `.env`, `vault-export` целиком, точные хосты и клиентские доступы.

## Что входит в доказательную базу

Ниже только те пути, которые безопасно и честно можно относить к Telegram-контуру:

- `ops/terraform/tgbot/...`
- `rnd-argocd/clusters/tgbots-dev/...`
- `tgbot-сharts/dev/`
- `tgbot-сharts/prod/`
- `it-incubator-terraform/tgbots/...` только как инфраструктурный контекст FortiGate VPN, без публикации raw-конфигурации
- связанные рабочие backup/restore-артефакты, если они явно привязаны к `tgbot`-задаче

## Retool

По архиву читается отдельный эксплуатационный след вокруг `Retool` именно в `tgbot`-контуре, а не просто случайное упоминание в одном конфиге.

Опорные пути:

- `ops/terraform/tgbot/prod/ec2/retool2/main.tf`
- `ops/terraform/tgbot/prod/ec2/retool2/sg.tf`
- `ops/terraform/tgbot/prod/vpc/route53_bestbots_cc_records.tf`
- `sckript-program/db-backup/move-to-another-postgres/sh-script-export-manuall-target-retool.sh`
- `sckript-program/db-backup/pg-17-client-docker/deployment.yaml`

Что это подтверждает:

- был отдельный infra-контур под `Retool` с Terraform-описанием инстанса, security group и DNS-записями;
- были практические задачи вокруг `PostgreSQL dump/restore` и переноса базы `Retool`;
- рядом есть operational tooling под backup/restore и клиентские pg-утилиты, а не только deployment-манифесты.

Корректная формулировка для собеседования:

- `Есть подтверждаемый опыт adjacent internal tooling вокруг Retool: инфраструктура, DNS/SG, postgres dump/restore и перенос базы.`

## Debezium / CDC в tgbots

По `tgbots`-пути виден не только факт знакомства с термином `Debezium`, а именно operational след в `ArgoCD`-infra-apps.

Опорные пути:

- `rnd-argocd/clusters/tgbots-dev/infra-apps/debezium-postgres/application.yaml`
- `rnd-argocd/clusters/tgbots-dev/infra-apps/debezium-postgres/manifests/debezium.yaml`
- `rnd-argocd/clusters/tgbots-dev/infra-apps/debezium-mongo/application.yaml`
- `rnd-argocd/clusters/tgbots-dev/infra-apps/debezium-mongo/manifests/debezium.yaml`

Что видно:

- есть отдельный `debezium-postgres` application в `tgbots-dev`;
- есть отдельный `debezium-mongo` application в `tgbots-dev`;
- в manifest-файлах прямо читаются коннекторы `io.debezium.connector.postgresql.PostgresConnector` и `io.debezium.connector.mongodb.MongoDbConnector`.

Что это подтверждает:

- опыт рядом с `CDC`-контурами внутри Telegram-платформы;
- понимание operational-слоя вокруг `Debezium` в `ArgoCD`-managed инфраструктуре;
- участие не только в delivery приложений, но и в соседних данных / интеграционных компонентах.

Корректная формулировка:

- `Есть подтверждаемый adjacent experience вокруг Debezium / CDC в tgbots-контуре, без попытки продавать это как deep data-engineering специализацию.`

## Migration jobs в tgbot-сharts

Это один из самых чистых tgbot-specific следов: migrations читаются прямо в `tgbot-сharts`.

Опорные пути:

- `rnd-charts/custom/tgbots/app/values.yaml`
- `tgbot-сharts/dev/`
- `tgbot-сharts/prod/`

Что видно:

- в chart values есть отдельные `job` / `revertJob` команды под `apply-migrations` и `migration:revert`;
- в `tgbot-сharts` есть deployment-конфиги, где вызываются `prod:apply-migrations` и `prod:migration:revert`;
- это видно, например, в `match-career.yaml`, `concierge-sng.yaml`, `lab-views.yaml`, `adult.yaml` и ряде других файлов в `dev/prod`;
- по этим chart values безопасно видно именно наличие migration flow, но не конкретный движок БД.

Что это подтверждает:

- сопровождение не только runtime-сервисов, но и `schema migration`-контуров;
- понимание того, как migrations живут в `Helm`, `ArgoCD`, release flow и rollback/revert-процедурах;
- практический опыт вокруг сервисных БД, а не только вокруг deployment YAML.

Корректная формулировка:

- `Есть подтверждаемый опыт с migration jobs и apply/revert flow для сервисных БД в Helm/ArgoCD-контурах.`
- `По этим values корректнее говорить о миграциях схемы приложения, а не жёстко приписывать их конкретно PostgreSQL или MariaDB.`

## FortiGate / FortiClient VPN в tgbots

В Terraform-архиве есть технический след FortiGate VPN, связанный с сетевыми контурами `tgbots`: адресные объекты для `infra`, `dev`, `test` и `prod`, а также инструкции по добавлению сети и firewall policy при развёртывании VPC.

Опорные пути:

- `it-incubator-terraform/tgbots/dev/eu-central-1/vpc/README.md`
- `it-incubator-terraform/tgbots/prod-1/eu-central-1/vpc/README.md`
- `it-incubator-terraform/tgbots/infra/eu-central-1/vpc/README.md`
- `it-incubator-terraform/infra/prod/eu-north-1/ec2/fortigate/private-address.tf`
- `it-incubator-terraform/infra/prod/eu-north-1/ec2/fortigate/client-guide.md`

Что подтверждает технический контекст:

- FortiGate использовался как точка VPN-доступа и сетевой политики для окружений;
- при появлении или изменении tgbots-сети требовалось согласовать VPC, firewall address objects и policy;
- эксплуатационный слой включал подключение пользователей через FortiClient и проверку маршрутизации.

Ограничение доказательства:

- git-история именно этих путей содержит коммиты нескольких инженеров, поэтому она не используется как доказательство индивидуального авторства;
- в публичное портфолио не выносятся адреса сетей, FQDN, правила доступа, учётные данные или экспорт FortiGate-конфигурации.

Корректная формулировка:

- `Администрировал FortiGate/FortiClient VPN для доступа к tgbots-контурам: сопровождение сетевых объектов, маршрутизации и политик доступа; реальные конфигурации не публикую.`

## Как это усиливает блок 01.tech

Что можно добавлять в резюме безопасно:

- `Retool` как adjacent internal tooling;
- `Debezium` как adjacent CDC-layer в `tgbots`;
- `migration jobs`, `apply/revert migrations`, `schema/data migration workflows`;
- `PostgreSQL dump/restore`, перенос отдельных БД и operational data tooling.
- `FortiGate/FortiClient VPN`: эксплуатация VPN-доступа, маршрутизация и сетевые политики для tgbots-контуров.

Что не стоит писать:

- `эксперт по Debezium` или `глубокий Data Engineer`;
- `проектировал CDC-платформу с нуля`, если это не так;
- `отвечал за всю data-platform архитектуру`, если роль была DevOps / Platform.

## Что принципиально не публикуется

- raw `vault-export` и connection json-файлы;
- реальные значения секретов, логинов, паролей и FQDN;
- полные внутренние migration-конфиги с чувствительными env var;
- любые файлы, по которым можно восстановить приватный runtime-контекст клиента.
