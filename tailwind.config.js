module.exports = {
  content: ["./docs/**/*.html", "./components/**/*.tsx", "./scripts/**/*.tsx"],
  darkMode: "class",
  theme: {
    extend: {
      fontFamily: {
        mono: ["ui-monospace", "SFMono-Regular", "monospace"],
        display: ["system-ui", "-apple-system", "BlinkMacSystemFont", "sans-serif"],
        sans: ["system-ui", "-apple-system", "BlinkMacSystemFont", "sans-serif"],
      },
      colors: {
        background: "var(--surface)",
        muted: "var(--surface-soft)",
        border: "var(--line)",
        "muted-foreground": "var(--muted)",
        accent: "var(--accent)",
        "accent-wash": "var(--accent-wash)",
        theme: {
          black: "rgb(var(--page-rgb) / <alpha-value>)",
          surface: "rgb(var(--surface-rgb) / <alpha-value>)",
          elevated: "rgb(var(--surface-soft-rgb) / <alpha-value>)",
          border: "rgb(var(--line-rgb) / <alpha-value>)",
          borderLight: "rgb(var(--line-rgb) / <alpha-value>)",
          accent: "rgb(var(--accent-rgb) / <alpha-value>)",
        },
      },
    },
  },
};
