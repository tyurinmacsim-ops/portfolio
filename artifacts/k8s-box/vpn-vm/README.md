# vpn-vm (Terragrunt stack)

Terragrunt-стек для VPN VM в `Yandex Cloud`.

Текущий поддерживаемый сценарий:
- основной режим: `WireGuard`;
- `OpenVPN` оставлен как legacy-флаг и по умолчанию не используется;
- operational-документация и клиентские сценарии описаны только для `WireGuard`.

## Что создает стек

1. VPN VM с внешним IP.
2. Отдельную security group для SSH и WireGuard.
3. Выделенный service account для VM (если включен).
4. Cloud-init bootstrap, который настраивает WireGuard server на самой VM.

## Что нужно до запуска

1. Должны быть применены `folder` и `vpc`.
2. Нужен токен YC:
   - `TF_VAR_YC_TOKEN`, или
   - `TF_VAR_yc_token`, или
   - `YC_TOKEN`.
3. SSH CIDR в `K8S_BOX_VPN_VM_ADMIN_CIDRS` должен включать IP инженера.
4. Для текущего operational-сценария рекомендуем:
   - `K8S_BOX_VPN_VM_SSH_MODE=native`
   - `K8S_BOX_VPN_VM_ENABLE_OSLOGIN=false`
   - `K8S_BOX_VPN_VM_SSH_PUBLIC_KEY_PATH=~/.ssh/id_ed25519.pub`
   - `K8S_BOX_VPN_VM_SSH_PRIVATE_KEY_PATH=~/.ssh/id_ed25519`
5. Если организация принудительно включает `OS Login`, переключить operational-доступ на:
   - `K8S_BOX_VPN_VM_SSH_MODE=yc`
   - и убедиться, что у инженера уже настроены `OS Login profile` и SSH key в организации.

## Команды

```bash
cd vpn-vm
terragrunt init
terragrunt plan
terragrunt apply
terragrunt output
```

## После применения

1. Проверить состояние VPN:

```bash
cd ..
./scripts/vpn-smoke-check.sh
```

2. Сгенерировать клиентский конфиг WireGuard:

```bash
./scripts/vpn-create-wireguard-client.sh laptop
```

Конфиг будет сохранен локально:

```bash
.artifacts/vpn-clients/laptop.conf
```

## Важно

- Если нужен новый изолированный VPN-клиент, для него создается отдельный client config.
- VM не считается готовой только по факту `terragrunt apply`: инженер должен дополнительно выполнить smoke-check и выпустить хотя бы один client config.
- Если включен `OS Login` или он навязан организационной политикой, локальные SSH-скрипты нужно запускать через `K8S_BOX_VPN_VM_SSH_MODE=yc`; режим `native` в этом случае неприменим.
- Подробный порядок выдачи конфигурации инженеру, подключения с macOS/Windows и ручной ротации описан в [docs/vpn-runbook.md](../docs/vpn-runbook.md).
