#cloud-config
# Template for bootstrap of external infra-runner VM.
# Replace placeholders before use:
#   ${gitlab_url}
#   ${runner_registration_token}
#   ${runner_name}
#   ${runner_tags}
# Optional:
#   ${terraform_version} (default 1.12.2)
#   ${terragrunt_version} (default 0.82.0)

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash

package_update: true
package_upgrade: true

write_files:
  - path: /root/.terraformrc
    content: |
      provider_installation {
        network_mirror {
          url     = "https://terraform-mirror.yandexcloud.net/"
          include = ["registry.terraform.io/*/*", "registry.opentofu.org/*/*"]
        }
        direct {
          exclude = ["registry.terraform.io/*/*", "registry.opentofu.org/*/*"]
        }
      }
  - path: /usr/local/bin/register-gitlab-runner.sh
    permissions: "0755"
    content: |
      #!/usr/bin/env bash
      set -euo pipefail

      GITLAB_URL="${gitlab_url}"
      RUNNER_TOKEN="${runner_registration_token}"
      RUNNER_NAME="${runner_name}"
      RUNNER_TAGS="${runner_tags}"

      if [[ -z "$${RUNNER_TOKEN}" ]]; then
        echo "Runner token is empty"
        exit 1
      fi

      # Idempotency: if this token is already present in config, skip re-register.
      if [[ -f /etc/gitlab-runner/config.toml ]] && grep -q "$${RUNNER_TOKEN}" /etc/gitlab-runner/config.toml; then
        echo "Runner token already present in config.toml, skip registration"
        exit 0
      fi

      # GitLab new runner workflow (authentication token, usually glrt-*)
      # forbids setting tag-list/locked/etc via CLI register command.
      if [[ "$${RUNNER_TOKEN}" == glrt-* ]]; then
        gitlab-runner register \
          --non-interactive \
          --url "$${GITLAB_URL}" \
          --token "$${RUNNER_TOKEN}" \
          --executor "shell" \
          --name "$${RUNNER_NAME}"
        exit 0
      fi

      # Legacy registration token flow (kept for backward compatibility).
      gitlab-runner register \
        --non-interactive \
        --url "$${GITLAB_URL}" \
        --registration-token "$${RUNNER_TOKEN}" \
        --executor "shell" \
        --description "$${RUNNER_NAME}" \
        --tag-list "$${RUNNER_TAGS}"

packages:
  - curl
  - unzip
  - jq
  - git
  - docker.io
  - docker-compose

runcmd:
  - curl -fsSL https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | bash
  - apt-get install -y gitlab-runner
  - curl -fsSL "https://hashicorp-releases.yandexcloud.net/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip" -o /tmp/terraform.zip
  - unzip -o /tmp/terraform.zip -d /usr/local/bin/
  - chmod +x /usr/local/bin/terraform
  - curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/v${terragrunt_version}/terragrunt_linux_amd64" -o /usr/local/bin/terragrunt
  - chmod +x /usr/local/bin/terragrunt
  - curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash -s -- -i /usr/local -n
  - if [ ! -x /usr/local/bin/yc ] && [ -x /root/yandex-cloud/bin/yc ]; then ln -sf /root/yandex-cloud/bin/yc /usr/local/bin/yc; fi
  - ln -sf /usr/local/bin/yc /usr/bin/yc
  - /usr/local/bin/yc --version
  - su -s /bin/bash -c 'command -v yc && yc --version' gitlab-runner
  - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  - cp /root/.terraformrc /home/gitlab-runner/.terraformrc
  - chown gitlab-runner:gitlab-runner /home/gitlab-runner/.terraformrc
  - usermod -aG docker gitlab-runner
  - systemctl enable docker
  - systemctl start docker
  - /usr/local/bin/register-gitlab-runner.sh
  - systemctl restart gitlab-runner

final_message: "Infra runner bootstrap completed. Terraform/Terragrunt/YC/Kubectl tools are ready."
