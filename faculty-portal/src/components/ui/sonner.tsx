"use client"

import { useTheme } from "next-themes"
import { Toaster as Sonner, type ToasterProps } from "sonner"
import { CircleCheckIcon, InfoIcon, TriangleAlertIcon, OctagonXIcon, Loader2Icon } from "lucide-react"

const Toaster = ({ ...props }: ToasterProps) => {
  const { resolvedTheme } = useTheme()

  return (
    <Sonner
      theme={resolvedTheme === "dark" ? "dark" : "light"}
      closeButton
      offset={{ top: "5.25rem", right: "1.25rem" }}
      mobileOffset={{ top: "calc(5rem + env(safe-area-inset-top))", left: "1rem", right: "1rem" }}
      className="toaster group"
      icons={{
        success: (
          <CircleCheckIcon className="size-4" />
        ),
        info: (
          <InfoIcon className="size-4" />
        ),
        warning: (
          <TriangleAlertIcon className="size-4" />
        ),
        error: (
          <OctagonXIcon className="size-4" />
        ),
        loading: (
          <Loader2Icon className="size-4 motion-safe:animate-spin" />
        ),
      }}
      style={
        {
          "--normal-bg": "var(--popover)",
          "--normal-text": "var(--popover-foreground)",
          "--normal-border": "var(--border)",
          "--border-radius": "1rem",
        } as React.CSSProperties
      }
      toastOptions={{
        classNames: {
          toast: "cn-toast !min-h-14 !gap-2 !border-border !py-2 !shadow-lg",
          closeButton: "!static !order-last !ml-auto !size-8 !shrink-0 !transform-none !rounded-lg !border-border !bg-popover !text-popover-foreground hover:!bg-muted focus-visible:!outline-2 focus-visible:!outline-ring",
        },
      }}
      {...props}
    />
  )
}

export { Toaster }
