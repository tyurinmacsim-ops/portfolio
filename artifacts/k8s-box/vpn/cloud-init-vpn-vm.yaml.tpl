#cloud-config
hostname: ${hostname}

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
%{ if ssh_public_key != "" ~}
    ssh_authorized_keys:
      - ${ssh_public_key}
%{ endif ~}

package_update: true
package_upgrade: true

packages:
  - curl
  - jq
  - git
  - wireguard

write_files:
  - path: /etc/sysctl.d/99-vpn-forwarding.conf
    content: |
      net.ipv4.ip_forward=1
  - path: /usr/local/bin/configure-wireguard.sh
    permissions: "0755"
    content: |
      #!/usr/bin/env bash
      set -euo pipefail

      WG_INTERFACE="wg0"
      WG_NETWORK_CIDR="${wireguard_network_cidr}"
      WG_SERVER_ADDRESS="${wireguard_server_address}"
      WG_PORT="${wireguard_port}"
      WG_CLIENT_DNS="${wireguard_client_dns}"

      install -d -m 700 /etc/wireguard /etc/wireguard/clients

      if [[ ! -f /etc/wireguard/server.key ]]; then
        umask 077
        wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
      fi

      DEFAULT_IFACE="$(ip route get 1.1.1.1 | awk '/dev/ {for (i = 1; i <= NF; i++) if ($i == "dev") print $(i+1)}' | head -n1)"
      if [[ -z "$${DEFAULT_IFACE}" ]]; then
        echo "Не удалось определить основной сетевой интерфейс" >&2
        exit 1
      fi

      cat > /etc/wireguard/$${WG_INTERFACE}.conf <<EOF_WG
      [Interface]
      Address = $${WG_SERVER_ADDRESS}
      ListenPort = $${WG_PORT}
      PrivateKey = $(cat /etc/wireguard/server.key)
      SaveConfig = false
      PostUp = iptables -t nat -A POSTROUTING -s $${WG_NETWORK_CIDR} -o $${DEFAULT_IFACE} -j MASQUERADE
      PostDown = iptables -t nat -D POSTROUTING -s $${WG_NETWORK_CIDR} -o $${DEFAULT_IFACE} -j MASQUERADE
      EOF_WG

      chmod 600 /etc/wireguard/$${WG_INTERFACE}.conf
      systemctl enable wg-quick@$${WG_INTERFACE}
      systemctl restart wg-quick@$${WG_INTERFACE}
  - path: /usr/local/bin/vpn-create-client.sh
    permissions: "0755"
    content: |
      #!/usr/bin/env bash
      set -euo pipefail

      if [[ $# -lt 1 ]]; then
        echo "Usage: vpn-create-client.sh <client-name> [endpoint-host]" >&2
        exit 1
      fi

      CLIENT_NAME="$1"
      ENDPOINT_HOST="$${2:-}"
      WG_INTERFACE="wg0"
      WG_NETWORK_PREFIX="${wireguard_network_prefix}"
      WG_CLIENT_DNS="${wireguard_client_dns}"
      WG_ALLOWED_IPS="${wireguard_allowed_ips}"
      WG_PORT="${wireguard_port}"
      CLIENTS_DIR="/etc/wireguard/clients"
      CLIENT_DIR="$${CLIENTS_DIR}/$${CLIENT_NAME}"
      CLIENT_CONF="$${CLIENT_DIR}/$${CLIENT_NAME}.conf"
      REGISTRY_FILE="$${CLIENTS_DIR}/registry.txt"

      install -d -m 700 "$${CLIENT_DIR}" "$${CLIENTS_DIR}"

      if [[ ! -f /etc/wireguard/server.pub || ! -f /etc/wireguard/server.key ]]; then
        echo "WireGuard server is not configured" >&2
        exit 1
      fi

      if [[ ! -f "$${REGISTRY_FILE}" ]]; then
        touch "$${REGISTRY_FILE}"
        chmod 600 "$${REGISTRY_FILE}"
      fi

      if grep -q "^$${CLIENT_NAME} " "$${REGISTRY_FILE}"; then
        CLIENT_IP="$(awk -v name="$${CLIENT_NAME}" '$1 == name {print $2}' "$${REGISTRY_FILE}")"
      else
        LAST_SUFFIX="$(awk '{print $2}' "$${REGISTRY_FILE}" | awk -F. 'NF == 4 {print $4}' | sort -n | tail -n1)"
        if [[ -z "$${LAST_SUFFIX}" ]]; then
          NEXT_SUFFIX=2
        else
          NEXT_SUFFIX=$(($${LAST_SUFFIX} + 1))
        fi

        if (( NEXT_SUFFIX > 254 )); then
          echo "VPN client address pool is exhausted" >&2
          exit 1
        fi

        CLIENT_IP="$${WG_NETWORK_PREFIX}.$${NEXT_SUFFIX}"
        echo "$${CLIENT_NAME} $${CLIENT_IP}" >> "$${REGISTRY_FILE}"
      fi

      if [[ ! -f "$${CLIENT_DIR}/private.key" ]]; then
        umask 077
        wg genkey | tee "$${CLIENT_DIR}/private.key" | wg pubkey > "$${CLIENT_DIR}/public.key"
        chmod 600 "$${CLIENT_DIR}/private.key" "$${CLIENT_DIR}/public.key"
      fi

      CLIENT_PUBLIC_KEY="$(cat "$${CLIENT_DIR}/public.key")"
      SERVER_PUBLIC_KEY="$(cat /etc/wireguard/server.pub)"

      PEER_BEGIN="# BEGIN $${CLIENT_NAME}"
      PEER_END="# END $${CLIENT_NAME}"
      if ! grep -qF "$${PEER_BEGIN}" /etc/wireguard/$${WG_INTERFACE}.conf; then
        cat >> /etc/wireguard/$${WG_INTERFACE}.conf <<EOF_PEER

        $${PEER_BEGIN}
        [Peer]
        PublicKey = $${CLIENT_PUBLIC_KEY}
        AllowedIPs = $${CLIENT_IP}/32
        $${PEER_END}
      EOF_PEER
        chmod 600 /etc/wireguard/$${WG_INTERFACE}.conf
        wg syncconf $${WG_INTERFACE} <(wg-quick strip $${WG_INTERFACE})
      fi

      if [[ -z "$${ENDPOINT_HOST}" ]]; then
        ENDPOINT_HOST="$(hostname -I | awk '{print $1}')"
      fi

      cat > "$${CLIENT_CONF}" <<EOF_CLIENT
      [Interface]
      PrivateKey = $(cat "$${CLIENT_DIR}/private.key")
      Address = $${CLIENT_IP}/32
      DNS = $${WG_CLIENT_DNS}

      [Peer]
      PublicKey = $${SERVER_PUBLIC_KEY}
      Endpoint = $${ENDPOINT_HOST}:$${WG_PORT}
      AllowedIPs = $${WG_ALLOWED_IPS}
      PersistentKeepalive = 25
      EOF_CLIENT

      chmod 600 "$${CLIENT_CONF}"
      cat "$${CLIENT_CONF}"
  - path: /usr/local/bin/vpn-wireguard-status.sh
    permissions: "0755"
    content: |
      #!/usr/bin/env bash
      set -euo pipefail
      systemctl is-active --quiet wg-quick@wg0
      wg show wg0
      ip addr show wg0
      ip route
  - path: /etc/motd
    permissions: "0644"
    content: |
      WireGuard VPN VM готова.
      Клиентский конфиг:
        sudo /usr/local/bin/vpn-create-client.sh <client-name> <endpoint-host>
      Проверка состояния:
        sudo /usr/local/bin/vpn-wireguard-status.sh

runcmd:
  - sysctl --system
  - /usr/local/bin/configure-wireguard.sh
  - echo "VPN VM bootstrap complete" > /var/log/vpn-bootstrap.log

final_message: "VPN VM bootstrap completed. WireGuard server is configured."
