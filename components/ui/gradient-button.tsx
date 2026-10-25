import * as React from "react"
import { cn } from "@/lib/utils"

type GradientAnchorProps = { href: string; variant?: "default" | "variant"; className?: string } & React.AnchorHTMLAttributes<HTMLAnchorElement>
type GradientNativeButtonProps = { href?: undefined; variant?: "default" | "variant"; className?: string } & React.ButtonHTMLAttributes<HTMLButtonElement>
type GradientButtonProps = GradientAnchorProps | GradientNativeButtonProps

function isAnchorButton(props: GradientButtonProps): props is GradientAnchorProps {
  return typeof props.href === "string"
}

export function GradientButton(props: GradientButtonProps) {
  const className = cn("gradient-button", props.variant === "variant" && "gradient-button--variant", props.className)

  if (isAnchorButton(props)) {
    const { href, variant, className: _, ...attributes } = props
    return <a {...attributes} href={href} className={className} />
  }

  const { variant, className: _, type, ...attributes } = props
  return <button {...attributes} type={type ?? "button"} className={className} />
}
