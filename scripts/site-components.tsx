import { createRoot } from "react-dom/client"
import Demo from "@/components/ui/demo"
import DisplayCardsDemo from "@/components/ui/display-cards-demo"
import { scrollDrawProgress } from "./scroll-draw-progress.mjs"

const footerRoot = document.getElementById("site-footer-root")
if (footerRoot) createRoot(footerRoot).render(<Demo />)

const cardsRoot = document.getElementById("display-cards-root")
if (cardsRoot) createRoot(cardsRoot).render(<DisplayCardsDemo />)

const drawnPaths = [...document.querySelectorAll<SVGPathElement>("[data-scroll-draw]")]
if (drawnPaths.length && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  for (const path of drawnPaths) {
    path.style.strokeDasharray = "1"
    path.style.strokeDashoffset = "1"
  }

  let frame = 0
  const update = () => {
    frame = 0
    const viewport = window.innerHeight
    for (const path of drawnPaths) {
      const top = path.getBoundingClientRect().top
      const progress = scrollDrawProgress(top, viewport)
      path.style.strokeDashoffset = String(1 - progress)
    }
  }
  const scheduleUpdate = () => {
    if (!frame) frame = window.requestAnimationFrame(update)
  }

  window.addEventListener("scroll", scheduleUpdate, { passive: true })
  window.addEventListener("resize", scheduleUpdate, { passive: true })
  update()
}
