(() => {
  const modes = {
    hr: {
      label: "Кратко для HR",
      description: "Короткая выжимка о роли, стеке и сильных доказательствах.",
      intro: "Максим Тюрин — DevOps / SRE / Platform Engineer. Kubernetes, GitOps, Terraform, CI/CD, observability и production automation. В портфолио — публичные артефакты, демо-стенд, код и документация."
    },
    tech: {
      label: "Подробно для технического специалиста",
      description: "Приоритет — кейсы, стек, архитектурные решения, артефакты и воспроизводимый стенд.",
      intro: "DevOps / SRE / Platform Engineer с опытом Kubernetes, GitOps, Terraform, CI/CD, observability, backup/recovery и cloud infrastructure. Технические доказательства: k8s-box, GitOps-конфигурации, backup toolkit и воспроизводимый demo stand."
    },
    interview: { label: "Подготовка к собеседованию", description: "Темы, по которым можно быстро перейти к конкретному кейсу и техническому разговору." },
    ai: { label: "AI / Data / MLOps infrastructure", description: "Только инфраструктурная применимость: Kubernetes, очереди, CI/CD, observability, storage, автоматизация и надёжность." }
  };
  const copy = async (text, button) => {
    try {
      await navigator.clipboard.writeText(text);
      const old = button.textContent;
      button.textContent = "Скопировано";
      window.setTimeout(() => { button.textContent = old; }, 1600);
    } catch { window.prompt("Скопируйте текст:", text); }
  };
  const setMode = (mode, updateHash = true) => {
    const current = modes[mode] ? mode : "hr";
    document.documentElement.dataset.mode = current;
    document.querySelectorAll("[data-mode]").forEach((button) => {
      const active = button.dataset.mode === current;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });
    const description = document.querySelector("[data-mode-description]");
    if (description) description.textContent = modes[current].description;
    try { localStorage.setItem("portfolio-mode", current); } catch {}
    if (updateHash) history.replaceState(null, "", `#mode=${current}`);
  };
  const fromHash = () => new URLSearchParams(location.hash.replace(/^#/, "")).get("mode");
  document.querySelectorAll("[data-mode]").forEach((button) => button.addEventListener("click", () => setMode(button.dataset.mode)));
  document.querySelectorAll("[data-set-mode]").forEach((link) => link.addEventListener("click", () => setMode(link.dataset.setMode)));
  document.querySelectorAll("[data-copy]").forEach((button) => button.addEventListener("click", () => copy(modes[button.dataset.copy].intro, button)));
  document.querySelectorAll(".filter-bar").forEach((bar) => {
    const target = document.querySelector(bar.dataset.filterTarget);
    if (!target) return;
    bar.addEventListener("click", (event) => {
      const button = event.target.closest("[data-filter]");
      if (!button) return;
      const needle = button.dataset.filter.toLowerCase().split(" ");
      target.querySelectorAll("[data-filter-item]").forEach((item) => {
        const tags = item.dataset.tags || "";
        item.hidden = button.dataset.filter !== "all" && !needle.some((tag) => tags.includes(tag));
      });
      bar.querySelectorAll(".filter-button").forEach((item) => item.classList.toggle("is-active", item === button));
    });
  });
  let initial = fromHash();
  if (!initial) { try { initial = localStorage.getItem("portfolio-mode"); } catch {} }
  setMode(initial || "hr", false);
})();
