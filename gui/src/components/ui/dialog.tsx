import * as React from "react"
import { XIcon } from "lucide-react"
import { Dialog as DialogPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"

// Phase 72 — primitive-layer recommit, relocked post-Preferences when the
// user banned the prior visual outright (see
// `feedback_no_grey_modal_surface_or_scrim`).
//
// Surface treatment:
//   - bg-popover → bg-[var(--dialog-surface)] (own tone, OFF the
//     chrome/panel/canvas trio — established by CommandPalette, promoted to
//     the default when the dim grey scrim was banned)
//   - rounded-md, border-[var(--dialog-border)] (own border tone matching
//     the lower-lightness surface)
//   - shadow-[var(--shadow-dialog)] now carries atmospheric 16/40 px values
//     (was 8/24 px); with no scrim, the shadow takes over the lift work
//
// Scrim:
//   - bg-foreground/40 → bg-transparent (HARD BAN on the prior dim grey).
//     The Dialog floats above its content via tone + shadow + border, never
//     by dimming the canvas behind it. Consumers can opt INTO a scrim by
//     passing `overlayClassName`, but the default is transparent.
//   - No backdrop-blur (same rule).
//
// Motion:
//   - 100 ms fade-in / 80 ms fade-out (was 200 ms duration with zoom-in-95
//     which read as a "spring" entrance)
//   - zoom-in / zoom-out removed
//   - motion-reduce → instant fade
//
// Typography:
//   - text-lg → text-title (16 px) for DialogTitle
//   - text-sm muted-foreground → text-body opacity-65 for description
function Dialog({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Root>) {
  return <DialogPrimitive.Root data-slot="dialog" {...props} />
}

function DialogTrigger({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Trigger>) {
  return <DialogPrimitive.Trigger data-slot="dialog-trigger" {...props} />
}

function DialogPortal({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Portal>) {
  return <DialogPrimitive.Portal data-slot="dialog-portal" {...props} />
}

function DialogClose({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Close>) {
  return <DialogPrimitive.Close data-slot="dialog-close" {...props} />
}

function DialogOverlay({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Overlay>) {
  return (
    <DialogPrimitive.Overlay
      data-slot="dialog-overlay"
      className={cn(
        // Transparent by default (hard ban on the dim grey scrim per
        // feedback_no_grey_modal_surface_or_scrim). The overlay still mounts
        // so click-outside-to-close works; it just paints nothing. Consumers
        // can override via DialogContent's `overlayClassName` prop.
        "fixed inset-0 z-50 bg-transparent motion-reduce:!duration-0 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:duration-[80ms] data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:duration-100",
        className
      )}
      {...props}
    />
  )
}

function DialogContent({
  className,
  children,
  showCloseButton = true,
  overlayClassName,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Content> & {
  showCloseButton?: boolean
  /** Add a custom overlay class (e.g. a faint tint) on top of the default
   *  transparent scrim. Default behavior — no dim — is what 99% of dialogs
   *  want (feedback_no_grey_modal_surface_or_scrim). */
  overlayClassName?: string
}) {
  return (
    <DialogPortal data-slot="dialog-portal">
      <DialogOverlay className={overlayClassName} />
      <DialogPrimitive.Content
        data-slot="dialog-content"
        className={cn(
          "fixed top-[50%] left-[50%] z-50 grid w-full max-w-[calc(100%-2rem)] translate-x-[-50%] translate-y-[-50%] gap-4 rounded-md border border-[var(--dialog-border)] bg-[var(--dialog-surface)] p-6 shadow-[var(--shadow-dialog)] outline-none motion-reduce:!duration-0 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:duration-[80ms] data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:duration-100 sm:max-w-lg",
          className
        )}
        {...props}
      >
        {children}
        {showCloseButton && (
          <DialogPrimitive.Close
            data-slot="dialog-close"
            className="absolute top-3 right-3 inline-flex size-6 items-center justify-center rounded-sm text-foreground/55 outline-none transition-colors duration-[80ms] motion-reduce:transition-none hover:bg-card hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-0 disabled:pointer-events-none [&_svg]:size-3.5 [&_svg]:stroke-[1.5]"
          >
            <XIcon />
            <span className="sr-only">Close</span>
          </DialogPrimitive.Close>
        )}
      </DialogPrimitive.Content>
    </DialogPortal>
  )
}

function DialogHeader({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="dialog-header"
      className={cn("flex flex-col gap-1.5 text-left", className)}
      {...props}
    />
  )
}

function DialogFooter({
  className,
  showCloseButton = false,
  children,
  ...props
}: React.ComponentProps<"div"> & {
  showCloseButton?: boolean
}) {
  return (
    <div
      data-slot="dialog-footer"
      className={cn(
        "flex flex-col-reverse gap-2 sm:flex-row sm:justify-end",
        className
      )}
      {...props}
    >
      {children}
      {showCloseButton && (
        <DialogPrimitive.Close asChild>
          <Button variant="outline">Close</Button>
        </DialogPrimitive.Close>
      )}
    </div>
  )
}

function DialogTitle({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Title>) {
  return (
    <DialogPrimitive.Title
      data-slot="dialog-title"
      className={cn("text-title leading-tight font-medium", className)}
      {...props}
    />
  )
}

function DialogDescription({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Description>) {
  return (
    <DialogPrimitive.Description
      data-slot="dialog-description"
      className={cn("text-body text-foreground/65", className)}
      {...props}
    />
  )
}

export {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogOverlay,
  DialogPortal,
  DialogTitle,
  DialogTrigger,
}
