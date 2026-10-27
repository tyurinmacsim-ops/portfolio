# yc-vpn-vm-module

Terraform-модуль, который создает VPN VM в `Yandex Cloud`.

## Что создает модуль

1. Опциональный service account для VPN VM.
2. Опциональную отдельную security group.
3. `yandex_compute_instance` с cloud-init `user-data`.

## Что модуль делает сейчас

- поднимает VM;
- открывает SSH и WireGuard порт;
- передает cloud-init для настройки WireGuard server;
- умеет инжектировать SSH public key в metadata при `enable_oslogin=false`;
- допускает два operational-сценария поверх VM:
  - `native` с обычным SSH по ключу,
  - `yc` через `yc compute ssh` в контурах с enforced `OS Login`;
- возвращает внешний и внутренний IP.

## Что модуль не делает сам по себе

- не выдает локальный клиентский конфиг инженеру;
- не настраивает внешний ingress в кластер;
- не делает VPN обязательной частью bootstrap.
- не поддерживает OpenVPN на том же уровне, что и WireGuard.

Эти шаги находятся на уровне `k8s-box/scripts` и runbook'ов.
