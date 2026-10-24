(() => {
  const key = "nearby-drop-theme";
  const choices = ["system", "light", "dark"];
  let theme = "system";

  try {
    const saved = localStorage.getItem(key);
    if (choices.includes(saved)) theme = saved;
  } catch {}

  const apply = (value) => {
    theme = choices.includes(value) ? value : "system";
    document.documentElement.dataset.theme = theme;
    try { localStorage.setItem(key, theme); } catch {}
    const color = theme === "light" ? "#f8f7fa" : theme === "dark" ? "#17141c" : "";
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta && color) meta.content = color;
    if (meta && !color) meta.content = matchMedia("(prefers-color-scheme: dark)").matches ? "#17141c" : "#f8f7fa";
  };

  document.documentElement.dataset.theme = theme;
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.content = theme === "light" ? "#f8f7fa" : theme === "dark" ? "#17141c" : matchMedia("(prefers-color-scheme: dark)").matches ? "#17141c" : "#f8f7fa";
  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("[data-theme-select]").forEach((select) => {
      select.value = theme;
      select.addEventListener("change", () => apply(select.value));
    });
    matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      if (theme === "system") apply("system");
    });
  });
})();
