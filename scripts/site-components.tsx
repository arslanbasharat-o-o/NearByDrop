import { createRoot } from "react-dom/client"
import Demo from "@/components/ui/demo"
import DisplayCardsDemo from "@/components/ui/display-cards-demo"
import { GradientButton } from "@/components/ui/gradient-button"
import { FeatureSteps } from "@/components/ui/feature-section"
import { scrollDrawProgress } from "./scroll-draw-progress.mjs"

const footerRoot = document.getElementById("site-footer-root")
if (footerRoot) createRoot(footerRoot).render(<Demo />)

const cardsRoot = document.getElementById("display-cards-root")
if (cardsRoot) createRoot(cardsRoot).render(<DisplayCardsDemo />)

const appPreviewRoot = document.getElementById("app-preview-root")
if (appPreviewRoot) createRoot(appPreviewRoot).render(
  <FeatureSteps
    features={[
      { step: "Send", content: "Choose files and find nearby devices.", image: "assets/screenshots/send.jpg", alt: "Nearby Drop Send screen with file selection and nearby device controls" },
      { step: "Receive", content: "Get ready to receive or scan a QR code.", image: "assets/screenshots/receive.jpg", alt: "Nearby Drop Receive screen with QR scan and connection instructions" },
      { step: "Transfers", content: "See sent and received files in one place.", image: "assets/screenshots/transfers.jpg", alt: "Nearby Drop Transfers screen showing no transfers yet" },
      { step: "USB", content: "Connect an Android phone for file transfer.", image: "assets/screenshots/usb.jpg", alt: "Nearby Drop USB screen with Android file transfer instructions" },
    ]}
  />,
)

const headerDownloadRoot = document.getElementById("header-download-root")
if (headerDownloadRoot) createRoot(headerDownloadRoot).render(
  <GradientButton href="https://github.com/arslanbasharat-o-o/NearByDrop/releases/download/v2.3.4/Nearby-Drop-2.3.4.dmg" className="gradient-button--small">
    <span>GET .DMG</span><span aria-hidden="true">→</span>
  </GradientButton>,
)

const heroDownloadRoot = document.getElementById("hero-download-root")
if (heroDownloadRoot) createRoot(heroDownloadRoot).render(
  <GradientButton href="https://github.com/arslanbasharat-o-o/NearByDrop/releases/download/v2.3.4/Nearby-Drop-2.3.4.dmg">
    <svg width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24" aria-hidden="true"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /><polyline points="7 10 12 15 17 10" /><line x1="12" y1="15" x2="12" y2="3" /></svg>
    <span>DOWNLOAD FOR MAC · V2.3.4</span>
  </GradientButton>,
)

const heroGithubRoot = document.getElementById("hero-github-root")
if (heroGithubRoot) createRoot(heroGithubRoot).render(
  <GradientButton href="https://github.com/arslanbasharat-o-o/NearByDrop" target="_blank" rel="noopener" variant="variant">
    <span>VIEW ON GITHUB</span><span aria-hidden="true">↗</span>
  </GradientButton>,
)

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
