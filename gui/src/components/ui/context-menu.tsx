import * as React from "react"
import { CheckIcon, ChevronRightIcon } from "lucide-react"
import { ContextMenu as ContextMenuPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

// NOTE: The shadcn new-york upstream `ContextMenuItem` does NOT have a built-in
// `destructive` variant. Per Phase 62 UI-SPEC §"Per-row context menu", the
// Delete row should use `text-destructive` styling, but this shim mirrors the
// `dropdown-menu.tsx` convention that supports a `variant="destructive"` prop
// via `data-variant` for parity with that sibling shim.
//
// Phase 72 — primitive-layer recommit. Mirrors dropdown-menu.tsx visual
// vocabulary: h-7 items, text-body, rounded-sm, hover/focus bg-card, plain
// fade animation, no shadow, no zoom/slide. Sub-content uses --shadow-dialog
// loadout? — no; sub-menus still float on tonal step alone like the parent.

const CONTENT_CLASS =
  "z-50 max-h-(--radix-context-menu-content-available-height) min-w-[8rem] overflow-x-hidden overflow-y-auto rounded-md border border-border bg-popover p-1 text-foreground motion-reduce:!duration-0 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:duration-[80ms] data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:duration-100"

const ITEM_CLASS =
  "relative flex h-7 cursor-default items-center gap-1.5 rounded-sm px-2 text-body outline-hidden select-none transition-colors duration-[80ms] motion-reduce:transition-none focus:bg-card data-[disabled]:pointer-events-none data-[disabled]:opacity-50 data-[inset]:pl-7 data-[variant=destructive]:text-destructive data-[variant=destructive]:focus:bg-destructive/15 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-3.5 [&_svg]:stroke-[1.5] [&_svg:not([class*='text-'])]:text-foreground/55 data-[variant=destructive]:*:[svg]:text-destructive!"

export function ContextMenu({
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.Root>) {
  return <ContextMenuPrimitive.Root data-slot="context-menu" {...props} />
}

export function ContextMenuTrigger({
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.Trigger>) {
  return (
    <ContextMenuPrimitive.Trigger data-slot="context-menu-trigger" {...props} />
  )
}

export function ContextMenuGroup({
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.Group>) {
  return (
    <ContextMenuPrimitive.Group data-slot="context-menu-group" {...props} />
  )
}

export function ContextMenuPortal({
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.Portal>) {
  return (
    <ContextMenuPrimitive.Portal data-slot="context-menu-portal" {...props} />
  )
}

export function ContextMenuSub({
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.Sub>) {
  return <ContextMenuPrimitive.Sub data-slot="context-menu-sub" {...props} />
}

export function ContextMenuRadioGroup({
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.RadioGroup>) {
  return (
    <ContextMenuPrimitive.RadioGroup
      data-slot="context-menu-radio-group"
      {...props}
    />
  )
}

export function ContextMenuSubTrigger({
  className,
  inset,
  children,
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.SubTrigger> & {
  inset?: boolean
}) {
  return (
    <ContextMenuPrimitive.SubTrigger
      data-slot="context-menu-sub-trigger"
      data-inset={inset}
      className={cn(ITEM_CLASS, "data-[state=open]:bg-card", className)}
      {...props}
    >
      {children}
      <ChevronRightIcon className="ml-auto size-3.5 stroke-[1.5]" />
    </ContextMenuPrimitive.SubTrigger>
  )
}

export function ContextMenuSubContent({
  className,
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.SubContent>) {
  return (
    <ContextMenuPrimitive.SubContent
      data-slot="context-menu-sub-content"
      className={cn(CONTENT_CLASS, className)}
      {...props}
    />
  )
}

export function ContextMenuContent({
  className,
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.Content>) {
  return (
    <ContextMenuPrimitive.Portal>
      <ContextMenuPrimitive.Content
        data-slot="context-menu-content"
        className={cn(CONTENT_CLASS, className)}
        {...props}
      />
    </ContextMenuPrimitive.Portal>
  )
}

/**
 * PopoverMenuItem / PopoverMenuSeparator — Radix-context-free menu item primitives
 * styled identically to ContextMenuItem / ContextMenuSeparator. Use these inside a
 * Popover (Phase 65 Plan 05 canvas context menus) where a ContextMenu.Root ancestor
 * is absent and we cannot use ContextMenuPrimitive.Item (which requires
 * MenuContentContext). Pure HTML + Tailwind — no Radix Item wrapper.
 */

export function PopoverMenuItem({
  className,
  inset,
  variant = "default",
  disabled,
  onSelect,
  children,
  ...props
}: React.HTMLAttributes<HTMLDivElement> & {
  inset?: boolean
  variant?: "default" | "destructive"
  disabled?: boolean
  onSelect?: () => void
}) {
  return (
    <div
      role="menuitem"
      data-slot="popover-menu-item"
      data-inset={inset}
      data-variant={variant}
      data-disabled={disabled || undefined}
      aria-disabled={disabled || undefined}
      tabIndex={disabled ? undefined : 0}
      // hover: mouse-over highlight. focus-visible: keyboard-only highlight.
      // Plain `focus:` would persist after Radix Popover's autoFocus-on-open
      // (programmatic focus counts as :focus but not :focus-visible), making
      // the first item appear "selected" before the mouse arrives.
      className={cn(
        "relative flex h-7 cursor-default items-center gap-1.5 rounded-sm px-2 text-body outline-hidden select-none transition-colors duration-[80ms] motion-reduce:transition-none",
        "hover:bg-card focus-visible:bg-card",
        "data-[disabled]:pointer-events-none data-[disabled]:opacity-50",
        "data-[inset]:pl-7",
        "data-[variant=destructive]:text-destructive data-[variant=destructive]:hover:bg-destructive/15 data-[variant=destructive]:focus-visible:bg-destructive/15",
        "[&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-3.5 [&_svg]:stroke-[1.5] [&_svg:not([class*='text-'])]:text-foreground/55",
        className
      )}
      onClick={disabled ? undefined : onSelect}
      onKeyDown={disabled ? undefined : (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect?.();
        }
      }}
      {...props}
    >
      {children}
    </div>
  )
}

export function PopoverMenuSeparator({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      role="separator"
      data-slot="popover-menu-separator"
      className={cn("-mx-1 my-1 h-px bg-border", className)}
      {...props}
    />
  )
}

export function ContextMenuItem({
  className,
  inset,
  variant = "default",
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.Item> & {
  inset?: boolean
  variant?: "default" | "destructive"
}) {
  return (
    <ContextMenuPrimitive.Item
      data-slot="context-menu-item"
      data-inset={inset}
      data-variant={variant}
      className={cn(ITEM_CLASS, className)}
      {...props}
    />
  )
}

export function ContextMenuCheckboxItem({
  className,
  children,
  checked,
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.CheckboxItem>) {
  return (
    <ContextMenuPrimitive.CheckboxItem
      data-slot="context-menu-checkbox-item"
      className={cn(ITEM_CLASS, "pl-7", className)}
      checked={checked}
      {...props}
    >
      <span className="pointer-events-none absolute left-2 flex size-3 items-center justify-center">
        <ContextMenuPrimitive.ItemIndicator>
          <CheckIcon className="size-3 stroke-[2]" />
        </ContextMenuPrimitive.ItemIndicator>
      </span>
      {children}
    </ContextMenuPrimitive.CheckboxItem>
  )
}

export function ContextMenuRadioItem({
  className,
  children,
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.RadioItem>) {
  return (
    <ContextMenuPrimitive.RadioItem
      data-slot="context-menu-radio-item"
      className={cn(ITEM_CLASS, "pl-7", className)}
      {...props}
    >
      <span className="pointer-events-none absolute left-2 flex size-3 items-center justify-center">
        <ContextMenuPrimitive.ItemIndicator>
          <span className="size-1.5 rounded-full bg-foreground" />
        </ContextMenuPrimitive.ItemIndicator>
      </span>
      {children}
    </ContextMenuPrimitive.RadioItem>
  )
}

export function ContextMenuLabel({
  className,
  inset,
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.Label> & {
  inset?: boolean
}) {
  return (
    <ContextMenuPrimitive.Label
      data-slot="context-menu-label"
      data-inset={inset}
      className={cn(
        "px-2 py-1 text-micro font-medium uppercase tracking-wider text-foreground/55 data-[inset]:pl-7",
        className
      )}
      {...props}
    />
  )
}

export function ContextMenuSeparator({
  className,
  ...props
}: React.ComponentProps<typeof ContextMenuPrimitive.Separator>) {
  return (
    <ContextMenuPrimitive.Separator
      data-slot="context-menu-separator"
      className={cn("-mx-1 my-1 h-px bg-border", className)}
      {...props}
    />
  )
}

export function ContextMenuShortcut({
  className,
  ...props
}: React.ComponentProps<"span">) {
  return (
    <span
      data-slot="context-menu-shortcut"
      className={cn(
        "ml-auto text-micro font-mono text-foreground/55",
        className
      )}
      {...props}
    />
  )
}
