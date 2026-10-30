(() => {
  const details = {
    validate: {
      mark: "01", kicker: "Этап 1 · проверка до облака", title: "validate — поймать ошибки в конфигурации",
      copy: "Проверяются форматирование OpenTofu и корректность конфигурации. Набор validate-job выбирается по изменённым каталогам; на этом этапе инфраструктура не меняется.",
      guardrail: "Ошибки синтаксиса и структуры останавливаются до получения плана и доступа к облачным изменениям."
    },
    test: {
      mark: "02", kicker: "Этап 2 · тесты и статический анализ", title: "test — проверить логику и конфигурационные риски",
      copy: "Для Terraform/OpenTofu-модулей запускаются тесты без облака; для scheduler-функции — unit-тесты. Trivy проверяет конфигурацию на уязвимые настройки уровня HIGH и CRITICAL.",
      guardrail: "Проверки ловят часть ошибок и небезопасных настроек до plan и не требуют менять облачные ресурсы."
    },
    secrets: {
      mark: "03", kicker: "Этап 3 · GitLab security template", title: "secret-detection — проверить изменения на секреты",
      copy: "В pipeline подключён GitLab Secret Detection template и включена проверка обнаруженных секретов. Это отдельная стадия между тестами и планированием.",
      guardrail: "Проверка снижает риск случайно включить чувствительные данные в историю изменений. Она дополняет, но не заменяет безопасное хранение секретов."
    },
    plan: {
      mark: "04", kicker: "Этап 4 · предварительный план", title: "plan — увидеть предполагаемые изменения",
      copy: "OpenTofu строит plan с detailed exit code и сохраняет plan.cache вместе с JSON-отчётом. Для jobs одного state используется resource_group, чтобы не запускать конкурирующие операции.",
      guardrail: "План можно изучить до применения. Артефакт передаётся следующему job и хранится ограниченное время."
    },
    apply: {
      mark: "05", kicker: "Этап 5 · ручная контрольная точка", title: "apply — применить сохранённый план по решению инженера",
      copy: "Apply доступен как manual job на default branch для затронутых конфигураций. Он получает артефакт plan job и применяет plan.cache; в merge request этот этап не меняет инфраструктуру.",
      guardrail: "Изменение не стартует автоматически: нужен ручной запуск, а применяемый план связан с предыдущим этапом."
    },
    drift: {
      mark: "06", kicker: "Этап 6 · периодический контроль", title: "drift — обнаружить расхождение факта и кода",
      copy: "Drift-job запускается только pipeline по расписанию и выполняет plan с detailed exit code. Если найдено изменение вне IaC, job возвращает ошибку, чтобы расхождение заметили.",
      guardrail: "Drift-check только сигнализирует о diff: он не применяет план и не перезаписывает инфраструктуру."
    }
  };

  const triggers = {
    merge: {
      caption: "Изменения проверяются и получают plan; apply не запускается из merge request.",
      stages: ["validate", "test", "secrets", "plan"]
    },
    default: {
      caption: "На default branch повторяются проверки и plan; apply появляется как отдельная ручная задача при изменении соответствующей конфигурации.",
      stages: ["validate", "test", "secrets", "plan", "apply"]
    },
    schedule: {
      caption: "По расписанию запускается drift-check: он ищет незапланированные изменения и только сигнализирует о них.",
      stages: ["drift"]
    }
  };

  const stageButtons = [...document.querySelectorAll("[data-stage]")];
  const triggerButtons = [...document.querySelectorAll("[data-trigger]")];
  const setStage = (key) => {
    const detail = details[key];
    if (!detail) return;
    stageButtons.forEach((button) => {
      const active = button.dataset.stage === key;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });
    document.querySelector("[data-detail-mark]").textContent = detail.mark;
    document.querySelector("[data-detail-kicker]").textContent = detail.kicker;
    document.querySelector("[data-detail-title]").textContent = detail.title;
    document.querySelector("[data-detail-copy]").textContent = detail.copy;
    document.querySelector("[data-detail-guardrail]").textContent = detail.guardrail;
  };

  const setTrigger = (key) => {
    const trigger = triggers[key];
    if (!trigger) return;
    triggerButtons.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.trigger === key)));
    document.querySelector("[data-trigger-caption]").textContent = trigger.caption;
    document.querySelector("[data-path]").dataset.path = key;
    stageButtons.forEach((button) => button.classList.toggle("is-muted", !trigger.stages.includes(button.dataset.stage)));
  };

  stageButtons.forEach((button) => button.addEventListener("click", () => setStage(button.dataset.stage)));
  triggerButtons.forEach((button) => button.addEventListener("click", () => setTrigger(button.dataset.trigger)));
})();
