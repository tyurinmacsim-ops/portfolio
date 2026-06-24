# VPN Runbook

## Назначение

Этот сценарий нужен, когда для test/dev-стенда не хочется поднимать внешний балансировщик и достаточно безопасной точки входа в private-контур.

Поддерживаемый режим:
- `WireGuard` — основной и рекомендуемый;
- `OpenVPN` — legacy-режим, не является основным путем эксплуатации и не доведен до того же уровня автоматизации.

## Что поднимается кодом

`vpn-vm` создает:

1. VM с внешним IP.
2. Security group для SSH и WireGuard.
3. WireGuard server через cloud-init.

## Какие переменные важны

Основные:

- `K8S_BOX_VPN_VM_ADMIN_CIDRS`
- `K8S_BOX_VPN_VM_ENABLE_WIREGUARD`
- `K8S_BOX_VPN_VM_SSH_MODE`
- `K8S_BOX_VPN_VM_ENABLE_OSLOGIN`
- `K8S_BOX_VPN_VM_SSH_USERNAME`
- `K8S_BOX_VPN_VM_SSH_PUBLIC_KEY_PATH`
- `K8S_BOX_VPN_VM_SSH_PRIVATE_KEY_PATH`
- `K8S_BOX_VPN_VM_WIREGUARD_PORT`
- `K8S_BOX_VPN_VM_WIREGUARD_NETWORK_CIDR`
- `K8S_BOX_VPN_VM_WIREGUARD_SERVER_ADDRESS`
- `K8S_BOX_VPN_VM_WIREGUARD_NETWORK_PREFIX`
- `K8S_BOX_VPN_VM_WIREGUARD_ALLOWED_IPS`

Рекомендуемая схема для инженерного test/dev доступа:
- `K8S_BOX_VPN_VM_SSH_MODE=native`
- `K8S_BOX_VPN_VM_ENABLE_OSLOGIN=false`
- в metadata VM инжектируется локальный SSH public key;
- smoke-check и выпуск client config выполняются тем же SSH key локально.

Если организация принудительно включает `OS Login`, используй:
- `K8S_BOX_VPN_VM_SSH_MODE=yc`

В этом режиме operational-скрипты работают через `yc compute ssh`. Сам Terraform-модуль не настраивает `OS Login profile` за инженера: профиль и SSH key должны уже существовать в организации.

## Развертывание

```bash
./scripts/bootstrap-k8s-box.sh apply-vpn
```

## Проверка после развертывания

```bash
./scripts/vpn-smoke-check.sh
```

Ожидаемый результат:
- `wg-quick@wg0` в статусе `active`;
- `wg show wg0` возвращает конфигурацию интерфейса;
- на интерфейсе `wg0` есть адрес из VPN-пула.

## Получение клиентского конфига

```bash
./scripts/vpn-create-wireguard-client.sh laptop
```

Результат:
- локально появится файл `.artifacts/vpn-clients/laptop.conf`;
- его можно импортировать в клиент WireGuard.

## Как выдать конфиг инженеру

1. Сгенерировать отдельный peer под конкретного человека или устройство:

```bash
./scripts/vpn-create-wireguard-client.sh <engineer-name>
```

2. Передать только итоговый клиентский конфиг:

```text
.artifacts/vpn-clients/<engineer-name>.conf
```

3. Не переиспользовать один и тот же конфиг на несколько инженеров.
4. Не хранить клиентские конфиги в Git-репозитории.

## Подключение с macOS

1. Установить `WireGuard` из App Store.
2. Открыть приложение `WireGuard`.
3. Выбрать `Add Tunnel` -> `Import tunnel(s) from file`.
4. Импортировать файл `*.conf`.
5. Поднять туннель и проверить доступ до приватных ресурсов.

## Подключение с Windows

1. Установить `WireGuard for Windows`.
2. Открыть клиент.
3. Выбрать `Import tunnel(s) from file`.
4. Импортировать файл `*.conf`.
5. Активировать туннель и проверить доступ до приватных ресурсов.

## Что делать инженеру дальше

1. Импортировать `*.conf` в WireGuard клиент.
2. Поднять туннель.
3. Проверить доступ до private-ресурсов:
   - Kubernetes API
   - приватные VM
   - внутренние ingress/ClusterIP маршруты, если они доступны по сети

## Ограничения текущей реализации

- Основной сценарий рассчитан на инженерный доступ, а не на массовую выдачу конфигов.
- Ротация клиентов пока ручная: отдельный client config на каждого инженера.
- OpenVPN не доведен до такого же уровня автоматизации и используется только как legacy-опция.
- Если включить `OS Login` или он навязан организационной политикой, нужно переключить `K8S_BOX_VPN_VM_SSH_MODE=yc`; режим `native` в таком контуре не сработает.

## Ротация и отзыв клиента

Текущая модель простая и ручная:

1. Если нужен новый конфиг, создать новый peer:

```bash
./scripts/vpn-create-wireguard-client.sh <new-name>
```

2. Старый конфиг считать скомпрометированным и больше не использовать.
3. На стороне сервера удалить старый peer вручную из `/etc/wireguard/wg0.conf` и перезагрузить интерфейс:

```bash
sudo editor /etc/wireguard/wg0.conf
sudo systemctl restart wg-quick@wg0
```

4. После ручного изменения повторно запустить smoke-check:

```bash
./scripts/vpn-smoke-check.sh
```

Пока это не автоматизированный lifecycle management. Для внутреннего инженерного стенда этого достаточно, но для массовой эксплуатации потребуется отдельный слой управления peer'ами.
