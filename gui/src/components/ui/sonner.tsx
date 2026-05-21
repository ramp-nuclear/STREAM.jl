import { Toaster as SonnerToaster, toast } from "sonner"
import type { ToasterProps } from "sonner"

import { useTheme } from "@/hooks/useTheme"

// Phase 72 — primitive-layer recommit. Sonner's per-toast styling is wired
// via the `toastOptions.classNames` block so each toast renders with the
// project's vocabulary instead of sonner's default shadcn theme.
//
// Surface posture: bg-popover, 1 px --border, rounded-md, NO shadow. Toasts
// sit on top of the canvas tonal step; the contrast does the lift work.
// (Deliberate hold-the-line — the audit would flag a shadow here as the
// most generic "toast notification" tell.)
//
// Position bottom-right matches Linear/Raycast convention (per shape brief
// Q1 — confirmed). Duration 2 s for quick acks; consumers passing longer
// content override per call.

const TOAST_CLASSES = {
  toast:
    "group toast group-[.toaster]:bg-popover group-[.toaster]:text-foreground group-[.toaster]:border group-[.toaster]:border-border group-[.toaster]:rounded-md group-[.toaster]:p-3 group-[.toaster]:text-body group-[.toaster]:shadow-none",
  title: "text-body font-medium",
  description: "text-label text-foreground/65",
  actionButton:
    "group-[.toast]:bg-primary group-[.toast]:text-primary-foreground group-[.toast]:rounded-sm group-[.toast]:text-label group-[.toast]:h-6 group-[.toast]:px-2",
  cancelButton:
    "group-[.toast]:bg-transparent group-[.toast]:text-foreground/65 group-[.toast]:rounded-sm group-[.toast]:text-label group-[.toast]:h-6 group-[.toast]:px-2 group-[.toast]:hover:bg-card",
  closeButton:
    "group-[.toast]:bg-transparent group-[.toast]:border-border group-[.toast]:text-foreground/55 group-[.toast]:hover:bg-card",
}

function Toaster({ className, ...props }: ToasterProps) {
  const { resolvedTheme } = useTheme()

  return (
    <SonnerToaster
      theme={resolvedTheme as ToasterProps["theme"]}
      position="bottom-right"
      duration={2000}
      closeButton={false}
      richColors={false}
      className={className}
      toastOptions={{
        classNames: TOAST_CLASSES,
        ...(props.toastOptions ?? {}),
      }}
      {...props}
    />
  )
}

export { Toaster, toast }
