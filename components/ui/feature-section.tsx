import * as React from "react"
import { AnimatePresence, motion, useReducedMotion } from "framer-motion"
import { cn } from "@/lib/utils"

export interface FeatureStep {
  step: string
  title?: string
  content: string
  image: string
  alt: string
}

interface FeatureStepsProps {
  features: FeatureStep[]
  className?: string
}

export function FeatureSteps({ features, className }: FeatureStepsProps) {
  const [currentFeature, setCurrentFeature] = React.useState(0)
  const reduceMotion = useReducedMotion()
  const activeFeature = features[currentFeature]

  if (!activeFeature) return null

  return (
    <div className={cn("app-tour", className)}>
      <div className="app-tour-steps" role="group" aria-label="Nearby Drop app screens">
        {features.map((feature, index) => (
          <button
            key={feature.step}
            type="button"
            className="app-tour-step"
            aria-pressed={index === currentFeature}
            onClick={() => setCurrentFeature(index)}
          >
            <span className="app-tour-step-index">{String(index + 1).padStart(2, "0")}</span>
            <span className="app-tour-step-copy">
              <strong>{feature.title || feature.step}</strong>
              <span>{feature.content}</span>
            </span>
          </button>
        ))}
      </div>

      <div className="app-tour-preview border border-theme-border bg-theme-surface p-2">
        <AnimatePresence mode="wait" initial={false}>
          <motion.figure
            key={activeFeature.image}
            className="app-tour-motion-screen"
            initial={reduceMotion ? false : { opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={reduceMotion ? undefined : { opacity: 0, y: -10 }}
            transition={{ duration: reduceMotion ? 0 : 0.24, ease: "easeOut" }}
          >
            <a href={activeFeature.image} target="_blank" rel="noopener" aria-label={`Open the ${activeFeature.title || activeFeature.step} screenshot`}
              className="block">
              <img
                src={activeFeature.image}
                alt={activeFeature.alt}
                width="772"
                height="1012"
                loading={currentFeature === 0 ? "eager" : "lazy"}
                decoding="async"
              />
            </a>
          </motion.figure>
        </AnimatePresence>
      </div>
    </div>
  )
}
