# Типовые ошибки и принятые решения

Документ фиксирует реальные ошибки, которые возникали при выкатке, и почему в код внесены конкретные изменения.

## 1. `apply-runner`: "требуется K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN"

- Симптом:
  - `Для apply-runner требуется K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN (или K8S_BOX_GITLAB_RUNNER_TOKEN)`.
- Причина:
  - в `.env` оставался placeholder в `K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN`;
  - скрипт брал его приоритетно и не переходил к `K8S_BOX_GITLAB_RUNNER_TOKEN`.
- Решение в коде:
  - в `scripts/bootstrap-k8s-box.sh` добавлен fallback:
    - если `K8S_BOX_GITLAB_RUNNER_REGISTRATION_TOKEN` пустой/placeholder, используется `K8S_BOX_GITLAB_RUNNER_TOKEN`;
  - при загрузке `.env` runtime-переменные runner сохраняются и не затираются.
- Почему так:
  - чтобы запуск `apply-runner` работал в обоих режимах GitLab (registration token и auth token) без ручной правки скрипта.

## 2. `folder apply`: `AlreadyExists` при создании folder

- Симптом:
  - `Folder with name 'internal-k8s-box' already exists`.
- Причина:
  - state не содержал актуальный ресурс folder, но сам folder уже существовал в облаке.
- Решение в коде:
  - в `scripts/bootstrap-k8s-box.sh` исправлен поиск существующего folder по имени;
  - добавлен авто-импорт найденного folder в terraform state перед `apply`.
- Почему так:
  - это делает запуск идемпотентным и убирает ручной шаг `terragrunt import`.

## 3. `UNAUTHENTICATED: token has expired`

- Симптом:
  - `The token has expired ...`.
- Причина:
  - в `.env` находился устаревший `TF_VAR_yc_token`.
- Решение в коде:
  - в `scripts/bootstrap-k8s-box.sh` оставлен приоритет на свежий токен из `yc iam create-token` (если `AUTO_REFRESH_YC_TOKEN=true`).
- Почему так:
  - для ежедневной эксплуатации безопаснее использовать краткоживущий токен из текущего активного профиля `yc`.

## 4. `PermissionDenied` после авто-refresh токена

- Симптом:
  - `Permission denied` при создании ресурсов, несмотря на корректный код.
- Причина:
  - активный `yc` profile не имел прав в целевом `cloud_id/folder_id`.
- Принятый порядок работы:
  - перед запуском явно активировать нужный профиль:
    - `yc config profile activate <profile>`;
  - затем запускать `bootstrap`/`platform-maintenance`.
- Почему так:
  - один и тот же инженер может работать с несколькими облаками, и ошибка чаще организационная (не тот профиль), а не инфраструктурная.

## 5. Ошибка Terragrunt в `infra-runner`: `"dependency" is not defined` в `locals`

- Симптом:
  - `Can't evaluate expression ... "dependency" is not defined`.
- Причина:
  - в `infra-runner/terragrunt.hcl` ссылка на `dependency.*` была внутри блока `locals`.
- Решение в коде:
  - выражение перенесено из `locals` в `inputs` (поле `subnet_id`).
- Почему так:
  - это корректный паттерн Terragrunt: зависимости безопасно использовать в `inputs`, а не в `locals`.

## 6. Runner в GitLab `Never contacted` после успешного создания VM

- Симптом:
  - VM `infra-runner` в `RUNNING`, но в GitLab runner остается `Never contacted`, pipeline в `Pending/Stuck`.
- Причина:
  - cloud-init выполнял `gitlab-runner register` с `--tag-list`/`--description` при использовании authentication token (`glrt-*`);
  - для нового GitLab runner flow такие флаги запрещены на этапе CLI-регистрации, регистрация падает (`FATAL`).
- Решение в коде:
  - в `runner/cloud-init-gitlab-runner.yaml.tpl` добавлен отдельный скрипт регистрации:
    - для `glrt-*`: регистрация только с `--url --token --executor --name`;
    - для legacy registration token: используется совместимый legacy flow с `--registration-token` и `--tag-list`.
  - добавлена идемпотентность: при наличии текущего токена в `config.toml` повторная регистрация пропускается.
- Почему так:
  - поддерживаются оба режима GitLab (новый и legacy), а автоматизация runner перестает ломаться из-за несовместимых аргументов.

## 7. Ошибка `templatefile`: `vars map does not contain key "RUNNER_TOKEN"`

- Симптом:
  - `Invalid function argument` в `terragrunt.hcl` при рендере `cloud-init-gitlab-runner.yaml.tpl`;
  - Terraform пытается подставить `${RUNNER_TOKEN}` как переменную `templatefile`.
- Причина:
  - в cloud-init шаблоне использовались shell-переменные в виде `${...}` без экранирования;
  - `templatefile` воспринимает их как собственные placeholders.
- Решение в коде:
  - shell-переменные в шаблоне переведены в `$${...}` (escaped interpolation для Terraform template).
- Почему так:
  - это единственно корректный способ совмещать `templatefile()` и bash-переменные внутри heredoc/скриптов.

## 8. Ложные/плавающие ошибки при параллельном запуске одного Terragrunt-стека

- Симптом:
  - в одном терминале `apply`, в другом `plan`/`destroy` по связанным модулям;
  - всплывают ошибки вида:
    - `Unknown variable: dependency`,
    - `Unsupported attribute ... outputs.vpc_id`,
    - несовместимые частичные outputs зависимостей.
- Причина:
  - гонка состояний и кэша (`.terragrunt-cache`) при параллельных операциях;
  - чтение зависимостей в момент, когда другой процесс меняет state/outputs.
- Принятый порядок работы:
  - **один оператор = один активный процесс на стек**;
  - не запускать `plan/apply/destroy` параллельно на тех же `folder/vpc/security-group/cluster/runner`;
  - после аварийного прерывания:
    1. дождаться завершения активного процесса;
    2. выполнить повторный `terragrunt plan` последовательно по модулям.
- Почему так:
  - устраняет ложную диагностику и исключает принятие неверных решений на основании race-condition ошибок.

## 9. Диагностика runner до завершения cloud-init дает преждевременные выводы

- Симптом:
  - runner еще в состоянии `Never contacted`, но VM только что создана.
- Причина:
  - cloud-init еще не дошел до шага `gitlab-runner register`.
- Принятый порядок проверки:
  - сначала смотреть serial log (`yc compute instance get-serial-port-output`) до сообщений о завершении cloud-init;
  - только после этого оценивать статус runner в GitLab.
- Почему так:
  - иначе можно ошибочно считать фиксы нерабочими и начать лишние пересоздания VM.

## 10. CI job `validate:scripts` падает на `terragrunt hcl format --check`

- Симптом:
  - пайплайн падает в `validate:scripts` с сообщениями:
    - `invalid file format ./vpc/terragrunt.hcl`
    - `invalid file format ./security-group/terragrunt.hcl`
    - `invalid file format ./vpn-vm/terragrunt.hcl`
- Причина:
  - изменения в `terragrunt.hcl` внесены вручную без финального автоформатирования.
- Решение:
  - запускать в репо `k8s-box`:
    - `terragrunt hcl format`
    - `terragrunt hcl format --check`
- Почему так:
  - форматтер Terragrunt является gate в CI; без этого даже корректная логика будет блокироваться на validate-стадии.

## 11. `vpn-vm` создавалась, но VPN фактически не был готов

- Симптом:
  - `terragrunt apply` для `vpn-vm` завершался успешно;
  - при этом инженер не получал ни рабочего server config, ни client config, ни smoke-check.
- Причина:
  - cloud-init ставил пакеты `wireguard/openvpn`, но не создавал рабочий туннель и не давал способ получить клиентский конфиг.
- Решение в коде:
  - основной поддерживаемый сценарий переведен на `WireGuard`;
  - cloud-init теперь настраивает `wg0` и запускает `wg-quick@wg0`;
  - добавлены инженерные команды:
    - `./scripts/vpn-smoke-check.sh`
    - `./scripts/vpn-create-wireguard-client.sh <client-name>`
- Почему так:
  - для VPN недостаточно факта создания VM; готовность подтверждается только после проверки WireGuard и выпуска клиентского конфига.

## 12. CI на runner не видит `yc` (`yc: command not found`)

- Симптом:
  - пайплайн падает в ранних стадиях с ошибкой `yc: command not found`.
- Причина:
  - `yc` устанавливался в нестабильный путь (зависел от домашней директории root);
  - у пользователя `gitlab-runner` бинарник мог отсутствовать в `PATH`.
- Решение в коде:
  - в `runner/cloud-init-gitlab-runner.yaml.tpl` установка `yc` переведена на:
    - `curl -sSL .../install.sh | bash -s -- -i /usr/local -n`;
  - добавлены fallback-симлинки:
    - `/root/yandex-cloud/bin/yc -> /usr/local/bin/yc` (если нужен),
    - `/usr/local/bin/yc -> /usr/bin/yc`;
  - добавлена проверка в cloud-init:
    - `/usr/local/bin/yc --version`;
    - `su -s /bin/bash -c 'command -v yc && yc --version' gitlab-runner`.
- Почему так:
  - runner должен быть самодостаточен для shell-executor CI и не зависеть от user-specific путей установки.

## 13. Drift между `k8s-box` и `infrastructure` по observability-флагам

- Симптом:
  - healthcheck/redeploy/platform-maintenance продолжают ждать старые app/flags:
    - `enableExternalSecrets`,
    - `enableExternalSecretsInTest`,
    - `monitoring-victoria-secrets`;
  - при этом `infrastructure` уже переключен на:
    - `alertmanagerTelegram.secretProvider=vso|external-secrets|manual`,
    - `monitoring-vault-secrets-operator`,
    - `monitoring-alertmanager-vault-secrets`,
    - `monitoring-alertmanager-external-secrets`.
- Причина:
  - runtime-логика изменилась в Helm chart, а operational scripts в `k8s-box` не были синхронно обновлены.
- Решение в коде:
  - `healthcheck-vault-observability.sh` теперь читает ожидаемые observability-приложения из текущего Helm chart;
  - `platform-maintenance.sh` и `redeploy-gitops-apps.sh` используют объединенный список возможных дочерних app/namespace вместо жесткой привязки к старым ESO-флагам;
  - `set-observability-stack.sh` расширен: теперь умеет переключать не только stack/profile, но и `secretProvider`.
  - для Vault добавлен симметричный runtime-переключатель `set-vault-profile.sh`.
- Почему так:
  - operational-слой не должен дублировать старую бизнес-логику `values.yaml`;
  - инженер должен выбирать вариант деплоя через один понятный интерфейс, а не править несколько скриптов и Helm values вручную.

## 14. CI в `k8s-box` не видит соседний checkout `infrastructure`

- Симптом:
  - pipeline/runner запускает `platform-maintenance` или `validate-gitops`, а рядом нет каталога `../infrastructure`;
  - platform-джобы падают на чтении `INFRA_REPO_DIR`.
- Причина:
  - локально инженер обычно держит две соседние репы;
  - в CI checkout только один, поэтому GitOps-репозиторий физически отсутствует.
- Решение в коде:
  - добавлен `scripts/ensure-infra-repo.sh`, который:
    - вычисляет clone URL,
    - клонирует `infrastructure`,
    - переключает его на нужный ref;
  - добавлен `scripts/apply-platform-runtime-profile.sh`, который применяет runtime-переключатели в уже подтянутый `infrastructure`;
  - `.gitlab-ci.yml` теперь выполняет эти шаги перед `plan/apply/verify` platform-стадий.
- Почему так:
  - pipeline должен быть самодостаточным;
  - CI не должен зависеть от ручной подготовки соседней директории на runner VM.

## 15. Runner уже online, но `validate:scripts` падает на устаревшей локальной логике

- Симптом:
  - GitLab Runner уже зарегистрирован и берет jobs;
  - pipeline падает рано на `validate:scripts`;
  - в логах видны ошибки вокруг новых runtime-скриптов или неактуальных `terragrunt.hcl`.
- Причина:
  - после исправления bootstrap runner начинают проявляться уже обычные ошибки репозитория;
  - CI-валидация могла не проверять новые скрипты и не ловила рассинхрон между operational-слоем и текущей структурой GitOps.
- Решение в коде:
  - новые скрипты `ensure-infra-repo.sh` и `apply-platform-runtime-profile.sh` добавлены в `validate:scripts`;
  - platform-related changes теперь запускают подготовительный шаг `prepare:platform-runtime`;
  - перед `plan/apply/verify` pipeline приводит runtime-профиль к явному состоянию.
- Почему так:
  - runner должен падать на реальной ошибке кода, а не на неявной недопроверенной ветке логики;
  - любое расширение operational-слоя должно сразу попадать в CI-проверки.

## 16. `terragrunt plan` частично проходит, но модули с `data sources` падают на `Unauthenticated`

- Симптом:
  - `vpc` или `security-group` еще могут показать `Plan: ...`;
  - `vpn-vm`, `infra-runner` или другие модули с `data.yandex_*` падают на:
    - `Authentication failed`
    - `Unauthenticated`
    - `The token has expired`
- Причина:
  - в `.env` лежит старый `TF_VAR_YC_TOKEN`;
  - Terraform использует именно его, даже если в `yc` CLI уже активирован правильный профиль.
- Решение в работе:
  - для ручного запуска получать свежий токен перед сессией:
    - `export TF_VAR_YC_TOKEN="$(yc iam create-token)"`
    - `export TF_VAR_yc_token="$TF_VAR_YC_TOKEN"`
  - или запускать wrapper-скрипты `bootstrap-k8s-box.sh` / `platform-maintenance.sh`, которые умеют брать свежий токен из активного `yc profile`.
- Почему так:
  - короткоживущий IAM token нельзя считать постоянной конфигурацией;
  - инженер должен различать:
    - постоянные параметры окружения,
    - краткоживущие runtime-credentials.

## 17. Однострочный `export` подмешивает старый `TF_VAR_yc_token` из `.env`

- Симптом:
  - после `source .env` инженер пытается обновить токен в одной строке, например:
    - `export TF_VAR_YC_TOKEN="$(yc iam create-token)" TF_VAR_yc_token="$TF_VAR_YC_TOKEN" YC_TOKEN="$TF_VAR_YC_TOKEN"`;
  - `terragrunt apply/destroy` уходит с протухшим `TF_VAR_yc_token`;
  - Terraform падает на:
    - `Unauthenticated`
    - `The token has expired`.
- Причина:
  - shell подставляет `$TF_VAR_YC_TOKEN` из уже существующего окружения в момент разбора команды;
  - в результате `TF_VAR_yc_token` может получить старое значение, даже если `TF_VAR_YC_TOKEN` в той же строке уже обновляется.
- Решение в коде:
  - добавлен `scripts/refresh-yc-token.sh`;
  - `scripts/check-env.sh` теперь валит проверку, если `TF_VAR_YC_TOKEN`, `TF_VAR_yc_token` и `YC_TOKEN` разъехались.
- Правильный способ:
  - `source <(./scripts/refresh-yc-token.sh)`
  - или:
    - `fresh_token="$(yc iam create-token)"`
    - `export TF_VAR_YC_TOKEN="$fresh_token"`
    - `export TF_VAR_yc_token="$fresh_token"`
    - `export YC_TOKEN="$fresh_token"`
- Почему так:
  - ошибка выглядит как проблема Terraform/YC, но реально это ловушка shell expansion;
  - безопаснее всегда сначала положить токен во временную переменную, а потом экспортировать.

## 18. `CreateCluster` падает с `PermissionDenied`, хотя у пользователя есть `admin` на облако

- Симптом:
  - `yandex_kubernetes_cluster.main: Creating...`
  - `rpc error: code = PermissionDenied desc = Permission denied`
- Причина:
  - это не всегда только проблема в правах пользователя;
  - в YC действительно бывает race condition: service accounts и folder IAM bindings уже созданы Terraform, но еще не успели полностью распространиться к моменту вызова `CreateCluster`;
  - отдельно подтвержден реальный дефект в коде:
    - в test-профиле было выставлено `allow_public_load_balancers=false`,
    - но `public_access=true` для master оставался включенным,
    - при этом выдача `vpc.publicAdmin` сервисному аккаунту кластера была привязана к флагу public load balancers;
  - в результате кластер с public master пытался создаться без нужной роли `vpc.publicAdmin`, хотя пользователь имел `admin` на cloud.
- Как отличить от реальной нехватки прав:
  - если у пользователя нет прав даже на ручное создание кластера через UI/CLI, сначала проверяется RBAC/organization policy;
  - если `folder/vpc/security-group` создаются успешно, а падает только `CreateCluster`, нужно проверять две ветки:
    - задержку применения IAM bindings;
    - хватает ли ролей именно у сервисного аккаунта кластера для текущего режима сети (`public master`, `public nodes`, cross-folder VPC);
  - если повторный `apply` через 30-120 секунд проходит без изменений в коде, это race condition;
  - если не проходит стабильно у нескольких инженеров на одном и том же коде, нужно искать ошибку в модели IAM ролей модуля.
- Решение в коде:
  - в `yc-k8s-module` добавлен `time_sleep.after_cluster_iam`;
  - `yandex_kubernetes_cluster.main` теперь стартует после явной паузы `cluster_create_iam_delay_seconds` (по умолчанию `30s`) после выдачи IAM bindings.
  - выдача `vpc.publicAdmin` отвязана от `allow_public_load_balancers`:
    - для public master и public worker nodes роль теперь выдается независимо от того, разрешены ли внешние `LoadBalancer`-сервисы;
  - для cross-folder VPC добавлен явный `vpc.bridgeAdmin`.
- Почему так:
  - `public master` и `public load balancers` — это разные сценарии и их нельзя связывать одним флагом;
  - пауза закрывает плавающий IAM race condition;
  - корректная модель ролей закрывает воспроизводимый `PermissionDenied`, который не лечится повторным `apply`.

## 18. Для test-стенда не нужен внешний балансировщик по умолчанию

- Симптом:
  - инженер видит в коде `load-balancer.admin` и `nlb_hc` и делает вывод, что test-стенд обязательно поднимает LB;
  - из-за этого test воспринимается как более дорогой, чем должен быть.
- Причина:
  - раньше права и healthcheck-rule были включены без явной профильной развилки;
  - при этом сам LB создается только если уже Kubernetes-сервисы просят `type=LoadBalancer`.
- Решение в коде:
  - в профиле `test`:
    - `allow_public_load_balancers=false`
    - `enable_nlb_hc_rule=false`
  - в профилях `dev/prod` эти флаги остаются включенными по умолчанию.
- Почему так:
  - test-стенд должен проверять общую концепцию платформы с минимальными затратами;
  - внешний ingress/LB нужен только там, где действительно тестируется внешний входной контур.

## 19. Test-override должен явно перебивать storage из базовых values

- Симптом:
  - test-профиль вроде выглядит "облегченным", но в облаке все равно появляются лишние PVC/диски заметного размера.
- Причина:
  - chart наследует базовые values;
  - если в test-оверлее включить компонент, но не переопределить его storage/retention, он может тихо унаследовать production-подобный объем.
- Реальный кейс:
  - `VictoriaMetrics vmsingle` в test-профиле был включен, но без явного override storage мог унаследовать базовый PVC `20Gi`.
- Решение в коде:
  - для test-профилей всегда явно задавать:
    - storage size,
    - retention,
    - ресурсы CPU/RAM,
    - отключение необязательных компонентов.
- Почему так:
  - "облегченный профиль" должен быть дешевым не только логически, но и фактически на уровне создаваемых cloud-ресурсов.

## 20. Test-профиль кластера и test-профиль observability должны совпадать по node placement

- Симптом:
  - `Grafana`, `vmagent`, `vmsingle` не стартуют с ошибкой:
    - `node(s) didn't match Pod's node affinity/selector`
- Причина:
  - test-кластер развернут без отдельной monitoring node group;
  - но test-manifests observability все еще требовали `nodeSelector: monitoring-node=true`.
- Решение в коде:
  - для test-профиля observability убрать обязательный `nodeSelector` на monitoring nodes;
  - выделенный monitoring pool оставлять только для `dev/prod` или явного override.
- Почему так:
  - test должен быть воспроизводим на минимальном кластере из одной обычной worker-группы;
  - зависимость от отдельного monitoring node в test ломает саму идею дешевого стенда.

## 21. Loki chart по умолчанию поднимает лишние для test cache/canary компоненты

- Симптом:
  - в test-кластере появляются `loki-chunks-cache-*`, `loki-results-cache-*` и дополнительные pod'ы, которые не помещаются по CPU/RAM;
  - основной `loki` может стартовать нестабильно из-за лишней нагрузки и шума в развертывании.
- Причина:
  - chart `grafana/loki` по умолчанию включает:
    - `chunksCache.enabled=true`
    - `resultsCache.enabled=true`
    - `lokiCanary.enabled=true`
  - если test-оверлей это явно не выключает, стек перестает быть "минимальным".
- Решение в коде:
  - для test-профиля явно выключать:
    - `chunksCache`
    - `resultsCache`
    - `memcachedExporter`
    - `lokiCanary`
    - `test`
- Почему так:
  - для test нам нужно проверить базовую схему `Loki + datasource + Grafana`, а не полноразмерный runtime-набор chart defaults.

## 22. Cold `terragrunt plan` по стеку использует mock outputs и требует явного режима

- Симптом:
  - при `plan` на пустом стеке Terragrunt пишет предупреждения вида:
    - `... has no outputs, but mock outputs provided`
- Причина:
  - downstream-модуль планируется до первого `apply` upstream-модуля;
  - для такого сценария мы сознательно используем `mock_outputs`, чтобы получить список будущих ресурсов.
- Решение в коде:
  - предупреждение принимается как ожидаемое для cold-plan сценария;
  - `mock_outputs` остаются включенными, чтобы инженер видел список создаваемых ресурсов до первого `apply`.
- Почему так:
  - это дает инженерный компромисс:
    - до первого `apply` можно увидеть список создаваемых ресурсов;
    - при `apply/destroy` всегда используются уже реальные outputs/state;
    - убрать этот warning средствами Terragrunt без потери самого cold-plan сценария не удалось.

## 23. `monitoring-loki Progressing` и `monitoring-victoria-metrics-stack OutOfSync` после redeploy могут быть следствием `NodeNotReady`, а не ошибки values

- Симптом:
  - после `./scripts/redeploy-gitops-apps.sh redeploy` healthcheck пишет:
    - `monitoring-loki health status=Progressing`
    - `monitoring-victoria-metrics-stack sync status=OutOfSync`
  - в `monitoring` pod'ы висят в `Pending`, а не обязательно в реальном `CrashLoopBackOff`;
  - в events видно `FailedScheduling`, например:
    - `node(s) had untolerated taint {node.kubernetes.io/not-ready: }`
    - `cluster-autoscaler ... in backoff after failed scale-up`
- Причина:
  - старый `redeploy-gitops-apps.sh` пересоздавал app, но не доводил сценарий до устойчивого конца:
    - не ждал `Synced/Healthy` для ожидаемых child app;
    - не запускал финальный healthcheck;
    - не давал понятной диагностики по `NodeNotReady` и `FailedScheduling`.
  - на однонодовом test-кластере деградация worker node визуально маскируется под "проблему Loki/VM", хотя корень находится ниже, на уровне scheduler/node readiness.
- Решение в коде:
  - `redeploy-gitops-apps.sh` теперь:
    - рендерит ожидаемый набор child app из актуального Helm chart;
    - ждет ready по parent/child app;
    - делает один дополнительный `hard refresh + sync` для app, которые не стабилизировались;
    - по умолчанию завершает redeploy вызовом `healthcheck-vault-observability.sh`.
  - `healthcheck-vault-observability.sh` теперь:
    - отдельно проверяет `nodes ready=X/Y`;
    - падает, если в кластере нет `Ready` node;
    - печатает причины `PodScheduled=False` и последние `FailedScheduling` events для `monitoring`.
- Почему так:
  - инженер должен сразу видеть, что проблема находится в worker/node/autoscaler, а не тратить время на лишний тюнинг `Loki` values;
  - `redeploy` в runbook должен быть максимально близок к "с нуля до проверяемого состояния", а не только к удалению и пересозданию app.

## 24. `.env` не должен затирать явные runtime-overrides из shell/CI

- Симптом:
  - инженер запускает:
    - `export K8S_BOX_VPN_VM_ENABLE_OPENVPN=false`
    - `./scripts/bootstrap-k8s-box.sh apply-vpn`
  - но в результате все равно создается OpenVPN ingress rule.
- Причина:
  - `bootstrap-k8s-box.sh` повторно загружал `.env`;
  - уже экспортированные `K8S_BOX_*` переменные не восстанавливались после `source .env`;
  - из-за этого локальный `.env` мог перетирать явные runtime-overrides.
- Решение в коде:
  - при загрузке `.env` сохраняются и восстанавливаются уже экспортированные:
    - `K8S_BOX_*`
    - `TF_VAR_*`
    - `YC_TOKEN`
    - `GITLAB_TOKEN`
    - `ARGOCD_ADMIN_PASSWORD`
- Почему так:
  - `.env` — это локальный bootstrap-слой, а не абсолютный источник истины;
  - приоритет должны иметь значения, которые инженер явно задал в текущем shell или CI job.

## 25. VPN VM с `OS Login` не совпадала с operational-сценарием smoke-check и выдачи client config

- Симптом:
  - `vpn-vm` создается успешно;
  - `vpn-smoke-check.sh` и `vpn-create-wireguard-client.sh` падают на:
    - `Permission denied (publickey)`.
- Причина:
  - VM создавалась с `enable_oslogin=true`;
  - при этом operational-скрипты были рассчитаны на обычный SSH-доступ по локальному ключу до пользователя `ubuntu`;
  - в metadata VM не инжектировался SSH public key, поэтому инженер не мог зайти стандартным путем.
- Решение в коде:
  - для VPN test/dev сценария `enable_oslogin=false` по умолчанию;
  - в модуль добавлен инжект:
    - `ssh_username`
    - `ssh_public_key`
  - в `vpn-vm` добавлены переменные:
    - `K8S_BOX_VPN_VM_ENABLE_OSLOGIN`
    - `K8S_BOX_VPN_VM_SSH_USERNAME`
    - `K8S_BOX_VPN_VM_SSH_PUBLIC_KEY_PATH`
    - `K8S_BOX_VPN_VM_SSH_PRIVATE_KEY_PATH`
  - `bootstrap-k8s-box.sh apply-vpn/plan-vpn` теперь заранее проверяет наличие SSH key path в рекомендованном режиме.
- Почему так:
  - VPN VM должна быть не просто создана, а операционно доступна инженеру;
  - для test/dev сценария проще и надежнее использовать обычный SSH key path, чем требовать отдельную схему `OS Login` для smoke-check и выпуска WireGuard client config.

## 26. Организационная политика может принудительно включать `OS Login` и игнорировать `ssh-keys` metadata

- Симптом:
  - `vpn-vm` создается успешно;
  - в `terragrunt plan` видно `enable-oslogin=false` и `ssh-keys`;
  - но `yc compute instance get` показывает `serial_port_settings.ssh_authorization = OS_LOGIN`;
  - `cloud-init` пишет `no authorized SSH keys fingerprints found for user ...`;
  - обычный `ssh -i ...` не работает.
- Причина:
  - в организации или облаке может действовать enforced policy на `OS Login`;
  - в таком контуре metadata `ssh-keys` не гарантирует operational-доступ.
- Решение в коде:
  - вводим явный transport-переключатель:
    - `K8S_BOX_VPN_VM_SSH_MODE=native|yc`;
  - `native` оставляем для generic YC, где доступны обычные `ssh-keys`;
  - `yc` используем для контуров, где инженер заходит через `yc compute ssh`.
- Ограничение:
  - `yc`-режим требует, чтобы у инженера уже были настроены `OS Login profile` и SSH key в организации;
  - если прав на `organization-manager oslogin` нет, это не исправляется Terraform-модулем VPN VM.
- Почему так:
  - operational-путь до VPN VM должен учитывать не только конфигурацию VM, но и организационную модель доступа;
  - иначе получается ложное состояние "VM создана, но инженер не может работать".

## 27. Параллельная ставка на `WireGuard` и `OpenVPN` усложняет поддержку без практической пользы

- Симптом:
  - VPN-слой выглядит как будто поддерживает два равноправных сценария;
  - инженеру непонятно, какой клиент ставить, какой конфиг ожидать и что реально поддерживается.
- Причина:
  - `OpenVPN` долго оставался в коде как historical flag;
  - при этом operational-скрипты, smoke-check и выдача клиентского конфига уже строились вокруг `WireGuard`.
- Решение в документации и позиционировании:
  - `WireGuard` объявлен основным и рекомендуемым VPN-решением;
  - `OpenVPN` оставлен только как legacy-флаг, без полноценной operational-поддержки;
  - runbook'и описывают только путь через `WireGuard`.
- Почему так:
- для инженерного доступа `WireGuard` проще, быстрее и понятнее;
- один поддерживаемый сценарий дает меньше ошибок, чем две неполные реализации.

## 28. Ошибка во вложенном heredoc внутри `cloud-init` ломает весь bootstrap VPN VM

- Симптом:
  - `vpn-vm` создается и доступна по SSH;
  - `sudo` у `ubuntu` просит пароль, хотя в шаблоне указан `NOPASSWD`;
  - WireGuard-скрипты не работают;
  - в serial/cloud-init логе есть ошибки:
    - `Failed loading yaml blob`
    - `Invalid format at line ... EOF_PEER`
- Причина:
  - в `cloud-init-vpn-vm.yaml.tpl` вложенный heredoc-терминатор `EOF_PEER` оказался в начале строки YAML;
  - из-за этого `cloud-config` становился невалидным;
  - cloud-init отбрасывал проблемный блок и не применял `users`, `write_files` и `runcmd`.
- Решение в коде:
  - heredoc-терминатор должен оставаться внутри YAML-блока с корректным отступом;
  - operational-скрипты используют `sudo -n`, чтобы сразу видеть поломку bootstrap, а не зависать на запросе пароля.
- Почему так:
  - для `cloud-init` недостаточно, чтобы shell-скрипт был логически верным;
  - он еще должен оставаться валидным YAML после шаблонизации;
  - после такой правки VM нужно пересоздавать, потому что уже завершившийся cloud-init не переисполняется автоматически.

## 29. `argocd` не должен зависеть от пользовательского `helm repo` cache

- Симптом:
  - `terragrunt apply` в `argocd` на "чистой" машине или новом профиле падает с ошибкой:
    - `could not download chart: no cached repo found`
    - `... main-helm-repo-index.yaml: no such file or directory`
- Причина:
  - Helm provider читает локальные `repositories.yaml` и `repository cache`;
  - если в пользовательском `helm`-окружении уже есть старые alias или битый cache, apply начинает зависеть от мусора в `~/Library/Preferences/helm` и `~/Library/Caches/helm`.
- Решение в коде:
  - `argocd/terragrunt.hcl` теперь использует изолированный `.helm/config` и `.helm/cache` внутри стека;
  - перед `init/plan/apply/destroy` создаются локальные каталоги и пустой `repositories.yaml`.
- Почему так:
  - E2E-раскатка должна быть воспроизводима на чистой и "грязной" машине одинаково;
  - bootstrap ArgoCD не должен зависеть от ручного `helm repo add/update`, выполненного когда-то ранее на ноутбуке инженера.

## 30. Сразу после `vpn-vm apply` SSH может быть еще не готов, даже если VM уже `RUNNING`

- Симптом:
  - `terragrunt apply` завершился успешно;
  - первый же `vpn-smoke-check.sh` падает на:
    - `Connection closed by <ip> port 22`
    - или на недоступности `sudo -n` команд.
- Причина:
  - YC уже считает VM созданной, но `cloud-init` и финальная настройка `sshd`/`wireguard` еще не завершились.
- Решение:
  - operational-скрипты нужно запускать с retry/backoff после `apply`;
  - при диагностике сначала смотреть serial/cloud-init log, а не считать первый SSH-отказ дефектом Terraform.
- Почему так:
  - готовность ресурса в облаке и готовность runtime внутри VM — это разные стадии;
  - для VPN нас интересует именно вторая.

## 31. `test`-профиль Loki не должен писать в `/var/loki` без persistence

- Симптом:
  - `loki-0` уходит в `CrashLoopBackOff`;
  - в логах контейнера:
    - `mkdir /var/loki: read-only file system`
- Причина:
  - в `test`-профиле `singleBinary.persistence.enabled=false`;
  - при этом базовый `path_prefix` оставался `/var/loki`;
  - writable volume в pod есть только на `/tmp`, а не на `/var/loki`.
- Решение в коде:
  - в `observability/manifests/loki/profiles/test/loki.yaml` явно задавать:
    - `loki.commonConfig.path_prefix: /tmp/loki`
- Почему так:
  - при облегчении test-профилей нельзя ограничиваться только выключением persistence;
  - нужно отдельно проверять, куда именно приложение пишет runtime-данные.

## 32. Для `VMSingle` в `test` нужно задавать `storage.resources`, а не неподдержанный для этого пути шаблон PVC

- Симптом:
  - `monitoring-victoria-metrics-stack` остается `OutOfSync`, хотя pod'ы работают;
  - live-ресурс `VMSingle` показывает `storage.requests.storage: 20Gi` вместо ожидаемых `5Gi`.
- Причина:
  - в test-профиле использовалась форма `storage.volumeClaimTemplate.spec.resources.requests.storage`;
  - оператор VictoriaMetrics для `VMSingle` в текущем варианте chart/CRD нормализует spec иначе и оставляет effective `storage.resources.requests.storage` из базового значения.
- Решение в коде:
  - для `VMSingle` в `observability/manifests/victoria/profiles/test/victoria-metrics-k8s-stack.yaml` задавать:
    - `spec.storage.resources.requests.storage: 5Gi`
- Почему так:
  - для operator-managed CR нужно смотреть не только на chart values, но и на итоговый live spec после нормализации оператором.

## 33. `plan` не должен зависать на `kubectl get storageclass`, если кластера еще нет

- Симптом:
  - `./scripts/bootstrap-k8s-box.sh plan` на чистом стенде зависает до запуска первого `terragrunt` модуля;
  - трассировка останавливается на `kubectl get storageclass`.
- Причина:
  - сбор bootstrap-контекста пытался определить default StorageClass без проверки, есть ли вообще kube-context;
  - на cold-start стенде `kubectl` уходит в сетевой timeout или обращается к мертвому контексту.
- Решение в коде:
  - сначала проверять `kubectl config current-context`;
  - вызывать `kubectl get storageclass` только с коротким `--request-timeout=5s`;
  - при отсутствии живого контекста сразу использовать fallback `yc-network-hdd`.
- Почему так:
  - `plan` должен быть безопасным для пустого стенда;
  - сбор диагностического контекста не должен зависеть от уже созданного кластера.

## 34. Явно заданный `TF_VAR_yc_token` должен иметь приоритет над `yc iam create-token`

- Симптом:
  - локальный `plan/apply` неожиданно уходит в `yc iam create-token`;
  - запуск может зависнуть на web-login, хотя в окружении уже задан валидный токен;
  - одинаковый E2E-сценарий ведет себя по-разному в зависимости от текущей YC-сессии на ноутбуке.
- Причина:
  - bootstrap пытался обновить токен через `yc` раньше, чем использовал уже заданные `TF_VAR_YC_TOKEN` / `TF_VAR_yc_token`;
  - локальный запуск становился неявно зависимым от активного web/session состояния `yc`.
- Решение в коде:
  - если `TF_VAR_YC_TOKEN` / `TF_VAR_yc_token` уже заданы, bootstrap использует их как источник истины;
  - `yc iam create-token` вызывается только когда явного токена нет;
  - для явного обновления токена используется `source <(./scripts/refresh-yc-token.sh)`.
- Почему так:
  - bootstrap должен быть воспроизводимым и предсказуемым;
  - скрытая попытка “освежить” токен не должна ломать локальный non-CI сценарий.

## 35. YC IAM может зависать на `service account` и `folder access binding` операциях без явной ошибки

- Симптом:
  - `terraform apply` зависает на:
    - `yandex_iam_service_account.*: Still creating...`
    - `yandex_resourcemanager_folder_iam_member.*: Still creating...`
  - ручные команды `yc iam service-account create` или `yc resource-manager folder add-access-binding` ведут себя так же;
  - `yc operation get <id>` долго показывает:
    - `done = null`
    - без `error.message`.
- Причина:
  - это внешний блокер или деградация YC IAM backend;
  - проблема проявляется не только через Terraform provider, но и через прямой `yc` CLI.
- Решение в коде и процессе:
  - добавлен отдельный preflight:
    - `./scripts/bootstrap-k8s-box.sh preflight-iam`
    - или напрямую `./scripts/yc-iam-smoke-check.sh`
  - smoke-check проверяет полный короткий цикл:
    - create service account
    - add access binding
    - remove access binding
    - delete service account
  - если smoke-check завершается по timeout, не нужно продолжать `apply-cluster` или `destroy`: сначала нужно дождаться восстановления YC IAM.
- Почему так:
  - раньше инженер узнавал о проблеме только после долгого `apply-cluster`;
  - теперь этот класс внешних сбоев выявляется отдельной короткой проверкой до старта основного E2E.

## 36. После частично неудачного `apply-cluster` чаще всего остаются не VM и не кластер, а IAM/VPC-хвосты

- Симптом:
  - самого кластера нет;
  - в folder остаются:
    - `service accounts`
    - `security groups`
    - `VPC/subnet/route tables/gateway`
    - `logging group`
- Причина:
  - `CreateCluster` не стартовал или не дошел до конца;
  - часть инфраструктурных модулей успела примениться раньше.
- Принятый порядок cleanup:
  - сначала удалить network/VPC-слой;
  - затем добить оставшиеся service account и access binding операции;
  - не считать такой partial state "успешно удаленным", пока folder не проверен через `yc`.
- Почему так:
  - в частично упавшем E2E деньги обычно тратятся не на кластер, а на хвост инфраструктурных ресурсов;
  - cleanup нужно проверять отдельно, а не полагаться только на факт `destroy`.

## 37. `AlreadyExists` на `yandex_iam_service_account.master/node_account` обычно означает reuse того же folder/state, а не "магический новый каталог"

- Симптом:
  - `test-cluster-k8s` падает на:
    - `rpc error: code = AlreadyExists desc = Service account ... already exists`
  - инженер ожидает, что запуск идет в "другой каталог", но Terraform все равно натыкается на уже созданные cluster SA.
- Причина:
  - `k8s-box` хранит folder как управляемый ресурс в собственном state;
  - если использовать тот же checkout/state, стек продолжает смотреть в тот же управляемый folder, пока явно не сменены `env.hcl` и сам state;
  - отдельный "второй folder" не появляется автоматически только потому, что инженер мысленно переключился на другой каталог в YC UI.
- Решение в коде:
  - `bootstrap-k8s-box.sh preflight` теперь печатает целевой `folder name/id`, с которым реально работает текущий state;
  - перед `test-cluster-k8s plan/apply` bootstrap пытается найти уже существующие cluster SA в целевом folder и автоматически включает reuse existing SA; поддерживаются и новые имена `k8s-service-account-<folder_name>-<cluster_name>` / `k8s-node-account-<folder_name>-<cluster_name>`, и legacy-варианты старых запусков;
  - `yc-k8s-module` теперь корректно работает с existing SA: использует их ID и все равно навешивает нужные IAM роли;
  - default naming для cluster SA теперь включает и `folder_name`, и `cluster_name`, чтобы параллельные стенды в одном cloud, но в разных folders, не делили одни и те же имена service accounts.
- Почему так:
  - повторный `apply` после partially failed run не должен валиться только на том, что cluster SA уже существуют;
  - инженер должен сразу видеть, в какой folder реально направлен запуск, иначе легко лечить не ту проблему.

## Рекомендации на будущее

1. Для CI runner:
   - использовать `AUTO_REFRESH_YC_TOKEN=true` и правильный активный `yc` profile на runner VM.
2. Для локального запуска:
   - перед `apply` делать `yc config profile activate <profile>`.
3. Для диагностики:
   - сначала смотреть `folder` и `infra-runner` модули, потом остальной стек.
4. Для вариативности runtime:
   - менять stack/profile/secret provider через код и коммит:
     - `./scripts/set-observability-stack.sh <stack> --profile <profile> --secret-provider <provider>`;
   - не делать выбор варианта только в UI/веб-интерфейсе.
