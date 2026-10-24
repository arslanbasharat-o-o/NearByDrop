import * as React from "react"
import { QrCode, Usb, Wifi } from "lucide-react"
import { cn } from "@/lib/utils"

interface DisplayCardProps {
  className?: string
  icon?: React.ReactNode
  title?: string
  description?: string
  date?: string
  iconClassName?: string
  titleClassName?: string
}

function DisplayCard({
  className,
  icon = <Wifi className="size-4" />,
  title = "Quick Share",
  description = "Send and receive nearby",
  date = "Both ways",
  iconClassName,
  titleClassName,
}: DisplayCardProps) {
  return (
    <article
      className={cn(
        "display-card relative flex h-36 w-[22rem] -skew-y-[8deg] select-none flex-col justify-between rounded-xl border-2 bg-muted px-4 py-3 backdrop-blur-sm transition-all duration-700 after:absolute after:-right-1 after:top-[-5%] after:h-[110%] after:w-[20rem] after:bg-gradient-to-l after:from-background after:to-transparent after:content-[''] hover:border-accent hover:bg-muted [&>*]:flex [&>*]:items-center [&>*]:gap-2",
        className,
      )}
    >
      <div>
        <span className={cn("display-card__icon relative inline-flex rounded-full bg-accent-wash p-1 text-accent", iconClassName)}>
          {icon}
        </span>
        <p className={cn("text-lg font-medium", titleClassName)}>{title}</p>
      </div>
      <p className="whitespace-nowrap text-base">{description}</p>
      <p className="text-sm text-muted-foreground">{date}</p>
    </article>
  )
}

interface DisplayCardsProps {
  cards?: DisplayCardProps[]
}

const defaultCards: DisplayCardProps[] = [
  {
    icon: <Wifi className="size-4" />,
    title: "Quick Share",
    description: "Send and receive nearby",
    date: "Both ways",
    className: "[grid-area:stack] -translate-x-8 -translate-y-12 hover:-translate-y-16",
  },
  {
    icon: <QrCode className="size-4" />,
    title: "QR Share",
    description: "Connect with a quick scan",
    date: "Camera ready",
    className: "[grid-area:stack] translate-x-3 translate-y-1 hover:-translate-y-2",
  },
  {
    icon: <Usb className="size-4" />,
    title: "USB MTP",
    description: "Browse files over cable",
    date: "Direct access",
    className: "[grid-area:stack] translate-x-14 translate-y-14 hover:translate-y-8",
  },
]

export default function DisplayCards({ cards = defaultCards }: DisplayCardsProps) {
  return (
    <div className="display-cards grid [grid-template-areas:'stack'] place-items-center" role="group" aria-label="Nearby Drop sharing methods">
      {cards.map((card, index) => <DisplayCard key={card.title ?? index} {...card} />)}
    </div>
  )
}
