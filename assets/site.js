(() => {
  "use strict";

  const modes = {
    hr: {
      label: "Кратко для HR",
      description: "Роль, ключевой стек, сильные факты и контакты — без технической перегрузки.",
      intro: "Максим Тюрин — DevOps / SRE / Platform Engineer из Перми. Kubernetes, GitOps, Terraform, CI/CD, observability и production automation. В портфолио доступны публичные кейсы, код, демо-стенд и эксплуатационная документация."
    },
    tech: {
      label: "Технический разбор",
      description: "Архитектурные потоки, вклад, ограничения, стек и прямые ссылки на доказательства.",
      intro: "DevOps / SRE / Platform Engineer с опытом Kubernetes, GitOps, Terraform, CI/CD, observability, backup/recovery и cloud infrastructure. Публичные доказательства включают k8s-box, GitOps-конфигурации, backup toolkit и воспроизводимый Platform Engineering стенд."
    },
    interview: {
      label: "Подготовка к интервью",
      description: "Кейсы раскрыты как темы для разговора: решение, компромиссы, ограничения и следующий шаг."
    },
    ai: {
      label: "AI / Data / MLOps infrastructure",
      description: "Инфраструктурная применимость: Kubernetes, workloads, очереди, storage, delivery и надёжность."
    }
  };

  const root = document.documentElement;
  root.classList.add("js-ready");

  const announce = (message) => {
    let toast = document.querySelector("[data-toast]");
    if (!toast) {
      toast = document.createElement("div");
      toast.className = "toast";
      toast.dataset.toast = "";
      toast.setAttribute("role", "status");
      toast.setAttribute("aria-live", "polite");
      document.body.append(toast);
    }
    toast.textContent = message;
    toast.classList.add("is-visible");
    window.clearTimeout(announce.timer);
    announce.timer = window.setTimeout(() => toast.classList.remove("is-visible"), 2200);
  };

  const filterGroup = (bar, category, silent = false) => {
    const target = document.querySelector(bar.dataset.filterTarget);
    if (!target) return;

    const items = [...target.querySelectorAll("[data-filter-item]")];
    let visible = 0;
    items.forEach((item) => {
      const categories = (item.dataset.categories || "").split(/\s+/);
      const show = category === "all" || categories.includes(category);
      item.hidden = !show;
      if (show) visible += 1;
    });

    bar.querySelectorAll("[data-filter]").forEach((button) => {
      const active = button.dataset.filter === category;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });

    const count = bar.querySelector("[data-filter-count]");
    if (count) {
      const noun = target.id === "cases" ? (visible === 1 ? "кейс" : "кейсов") : (visible === 1 ? "артефакт" : "артефактов");
      count.textContent = `${visible} ${noun}`;
    }
    if (!silent) announce(`Показано: ${visible}`);
  };

  const setMode = (requestedMode, options = {}) => {
    const mode = modes[requestedMode] ? requestedMode : "hr";
    root.dataset.mode = mode;

    document.querySelectorAll("[data-mode]").forEach((button) => {
      const active = button.dataset.mode === mode;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });

    document.querySelectorAll(".audience-section").forEach((section) => {
      const audiences = (section.dataset.audiences || "").split(/\s+/);
      section.hidden = !audiences.includes(mode);
    });

    const label = document.querySelector("[data-mode-label]");
    const description = document.querySelector("[data-mode-description]");
    if (label) label.textContent = modes[mode].label;
    if (description) description.textContent = modes[mode].description;

    document.querySelectorAll(".filter-bar").forEach((bar) => {
      filterGroup(bar, mode === "ai" ? "mlops" : "all", true);
    });

    try {
      localStorage.setItem("portfolio-mode", mode);
    } catch {}

    if (options.updateUrl !== false) {
      const url = new URL(window.location.href);
      url.searchParams.set("view", mode);
      history.replaceState({ mode }, "", url);
    }

    if (options.announce !== false) {
      announce(`Режим: ${modes[mode].label}`);
    }
  };

  const copyText = async (text, button) => {
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.append(textarea);
      textarea.select();
      document.execCommand("copy");
      textarea.remove();
    }
    const previous = button.textContent;
    button.textContent = "Скопировано ✓";
    announce("Текст скопирован");
    window.setTimeout(() => {
      button.textContent = previous;
    }, 1800);
  };

  document.querySelectorAll("[data-mode]").forEach((button) => {
    button.addEventListener("click", () => setMode(button.dataset.mode));
  });

  document.querySelectorAll("[data-set-mode]").forEach((link) => {
    link.addEventListener("click", () => setMode(link.dataset.setMode));
  });

  document.querySelectorAll("[data-copy]").forEach((button) => {
    button.addEventListener("click", () => {
      const mode = modes[button.dataset.copy];
      if (mode?.intro) copyText(mode.intro, button);
    });
  });

  document.querySelectorAll(".filter-bar").forEach((bar) => {
    bar.querySelectorAll("[data-filter]").forEach((button) => {
      button.addEventListener("click", () => filterGroup(bar, button.dataset.filter));
    });
  });

  const menuButton = document.querySelector("[data-menu-toggle]");
  const navigation = document.querySelector("#site-navigation");
  if (menuButton && navigation) {
    menuButton.addEventListener("click", () => {
      const open = navigation.classList.toggle("is-open");
      menuButton.setAttribute("aria-expanded", String(open));
      menuButton.textContent = open ? "Закрыть" : "Меню";
    });
    navigation.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => {
        navigation.classList.remove("is-open");
        menuButton.setAttribute("aria-expanded", "false");
        menuButton.textContent = "Меню";
      });
    });
  }

  const queryMode = new URL(window.location.href).searchParams.get("view");
  let savedMode = "";
  try {
    savedMode = localStorage.getItem("portfolio-mode") || "";
  } catch {}
  setMode(queryMode || savedMode || "hr", { updateUrl: false, announce: false });
})();
