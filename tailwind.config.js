module.exports = {
  content: ["./docs/**/*.html"],
  darkMode: "class",
  theme: {
    extend: {
      fontFamily: {
        mono: ['"IBM Plex Mono"', "ui-monospace", "monospace"],
        display: ['"Space Grotesk"', "sans-serif"],
        sans: ["Inter", "sans-serif"],
      },
      colors: {
        theme: {
          black: "#070707",
          surface: "#0e0e0e",
          elevated: "#151515",
          border: "#222222",
          borderLight: "#333333",
          accent: "#22c55e",
        },
      },
    },
  },
};
