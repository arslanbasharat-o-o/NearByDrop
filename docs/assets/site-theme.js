(() => {
  const key = "nearby-drop-theme";
  const media = matchMedia("(prefers-color-scheme: dark)");
  let saved;
  try { saved = localStorage.getItem(key); } catch {}
  let followsSystem = saved !== "light" && saved !== "dark";
  let theme = followsSystem ? (media.matches ? "dark" : "light") : saved;

  const apply = () => {
    document.documentElement.dataset.theme = theme;
    const next = theme === "dark" ? "light" : "dark";
    document.querySelectorAll("[data-theme-toggle]").forEach(button => {
      const label = "Switch to " + next + " mode";
      button.setAttribute("aria-label", label);
      button.setAttribute("title", label);
    });
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = theme === "dark" ? "#070707" : "#ffffff";
    window.dispatchEvent(new Event("themechange"));
  };

  apply();
  document.addEventListener("DOMContentLoaded", () => {
    apply();
    document.querySelectorAll("[data-theme-toggle]").forEach(button => {
      button.addEventListener("click", () => {
        theme = theme === "dark" ? "light" : "dark";
        followsSystem = false;
        try { localStorage.setItem(key, theme); } catch {}
        apply();
      });
    });
    media.addEventListener("change", () => {
      if (followsSystem) {
        theme = media.matches ? "dark" : "light";
        apply();
      }
    });
    window.addEventListener("storage", event => {
      if (event.key !== key && event.key !== null) return;
      followsSystem = event.newValue !== "light" && event.newValue !== "dark";
      theme = followsSystem ? (media.matches ? "dark" : "light") : event.newValue;
      apply();
    });
  });
})();
