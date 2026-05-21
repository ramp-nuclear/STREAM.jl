import * as React from "react"
import { CheckIcon, ChevronRightIcon } from "lucide-react"
import { Menubar as MenubarPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

// Phase 72 — primitive-layer recommit:
//   - Menubar root: h-9 → h-8, bg-background → bg-panel, shadow-xs removed,
//     no border (the panel surface already sits a tone below chrome)
//   - Trigger: text-body, hover bg-card, data-[state=open]:bg-card
//   - Content/SubContent: shared CONTENT_CLASS (bg-popover, no shadow, fade)
//   - Items: h-7, rounded-sm, hover bg-card, text-body
//   - Shortcuts: text-micro font-mono opacity-55
//   - Icons size-3.5 stroke-1.5
//   - rounded-xs for checkbox/radio items → rounded-sm (consistent w/ scale)

const CONTENT_CLASS =
  "z-50 min-w-[12rem] overflow-hidden rounded-md border border-border bg-popover p-1 text-foreground motion-reduce:!duration-0 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:duration-[80ms] data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:duration-100"

const ITEM_CLASS =
  "relative flex h-7 cursor-default items-center gap-1.5 rounded-sm px-2 text-body outline-hidden select-none transition-colors duration-[80ms] motion-reduce:transition-none focus:bg-card data-[disabled]:pointer-events-none data-[disabled]:opacity-50 data-[inset]:pl-7 data-[variant=destructive]:text-destructive data-[variant=destructive]:focus:bg-destructive/15 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-3.5 [&_svg]:stroke-[1.5] [&_svg:not([class*='text-'])]:text-foreground/55 data-[variant=destructive]:*:[svg]:text-destructive!"

function Menubar({
  className,
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.Root>) {
  return (
    <MenubarPrimitive.Root
      data-slot="menubar"
      className={cn(
        "flex h-8 items-center gap-1 bg-panel px-1",
        className
      )}
      {...props}
    />
  )
}

function MenubarMenu({
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.Menu>) {
  return <MenubarPrimitive.Menu data-slot="menubar-menu" {...props} />
}

function MenubarGroup({
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.Group>) {
  return <MenubarPrimitive.Group data-slot="menubar-group" {...props} />
}

function MenubarPortal({
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.Portal>) {
  return <MenubarPrimitive.Portal data-slot="menubar-portal" {...props} />
}

function MenubarRadioGroup({
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.RadioGroup>) {
  return (
    <MenubarPrimitive.RadioGroup data-slot="menubar-radio-group" {...props} />
  )
}

function MenubarTrigger({
  className,
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.Trigger>) {
  return (
    <MenubarPrimitive.Trigger
      data-slot="menubar-trigger"
      // Phase 68 UAT 2026-05-17 — `focus:bg-accent` was removed. After the
      // open menu is closed (either by user action or by the CustomTitlebar
      // mouse-leave handler), Radix re-focuses the trigger via
      // onCloseAutoFocus; the focus: styling then kept the trigger
      // highlighted indefinitely. data-[state=open] is the canonical
      // "menu is actually open" signal; that's what should highlight.
      // focus-visible:ring-1 still gives keyboard users a focus cue.
      className={cn(
        "flex h-6 items-center rounded-sm px-2 text-body font-medium outline-hidden select-none transition-colors duration-[80ms] motion-reduce:transition-none hover:bg-card data-[state=open]:bg-card focus-visible:ring-1 focus-visible:ring-ring",
        className
      )}
      {...props}
    />
  )
}

function MenubarContent({
  className,
  align = "start",
  alignOffset = 0,
  sideOffset = 0,
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.Content>) {
  return (
    <MenubarPortal>
      <MenubarPrimitive.Content
        data-slot="menubar-content"
        align={align}
        alignOffset={alignOffset}
        sideOffset={sideOffset}
        className={cn(CONTENT_CLASS, className)}
        {...props}
      />
    </MenubarPortal>
  )
}

function MenubarItem({
  className,
  inset,
  variant = "default",
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.Item> & {
  inset?: boolean
  variant?: "default" | "destructive"
}) {
  return (
    <MenubarPrimitive.Item
      data-slot="menubar-item"
      data-inset={inset}
      data-variant={variant}
      className={cn(ITEM_CLASS, className)}
      {...props}
    />
  )
}

function MenubarCheckboxItem({
  className,
  children,
  checked,
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.CheckboxItem>) {
  return (
    <MenubarPrimitive.CheckboxItem
      data-slot="menubar-checkbox-item"
      className={cn(ITEM_CLASS, "pl-7", className)}
      checked={checked}
      {...props}
    >
      <span className="pointer-events-none absolute left-2 flex size-3 items-center justify-center">
        <MenubarPrimitive.ItemIndicator>
          <CheckIcon className="size-3 stroke-[2]" />
        </MenubarPrimitive.ItemIndicator>
      </span>
      {children}
    </MenubarPrimitive.CheckboxItem>
  )
}

function MenubarRadioItem({
  className,
  children,
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.RadioItem>) {
  return (
    <MenubarPrimitive.RadioItem
      data-slot="menubar-radio-item"
      className={cn(ITEM_CLASS, "pl-7", className)}
      {...props}
    >
      <span className="pointer-events-none absolute left-2 flex size-3 items-center justify-center">
        <MenubarPrimitive.ItemIndicator>
          <span className="size-1.5 rounded-full bg-foreground" />
        </MenubarPrimitive.ItemIndicator>
      </span>
      {children}
    </MenubarPrimitive.RadioItem>
  )
}

function MenubarLabel({
  className,
  inset,
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.Label> & {
  inset?: boolean
}) {
  return (
    <MenubarPrimitive.Label
      data-slot="menubar-label"
      data-inset={inset}
      className={cn(
        "px-2 py-1 text-micro font-medium uppercase tracking-wider text-foreground/55 data-[inset]:pl-7",
        className
      )}
      {...props}
    />
  )
}

function MenubarSeparator({
  className,
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.Separator>) {
  return (
    <MenubarPrimitive.Separator
      data-slot="menubar-separator"
      className={cn("-mx-1 my-1 h-px bg-border", className)}
      {...props}
    />
  )
}

function MenubarShortcut({
  className,
  ...props
}: React.ComponentProps<"span">) {
  return (
    <span
      data-slot="menubar-shortcut"
      className={cn(
        "ml-auto text-micro font-mono text-foreground/55",
        className
      )}
      {...props}
    />
  )
}

function MenubarSub({
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.Sub>) {
  return <MenubarPrimitive.Sub data-slot="menubar-sub" {...props} />
}

function MenubarSubTrigger({
  className,
  inset,
  children,
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.SubTrigger> & {
  inset?: boolean
}) {
  return (
    <MenubarPrimitive.SubTrigger
      data-slot="menubar-sub-trigger"
      data-inset={inset}
      className={cn(ITEM_CLASS, "data-[state=open]:bg-card", className)}
      {...props}
    >
      {children}
      <ChevronRightIcon className="ml-auto h-3.5 w-3.5 stroke-[1.5]" />
    </MenubarPrimitive.SubTrigger>
  )
}

function MenubarSubContent({
  className,
  ...props
}: React.ComponentProps<typeof MenubarPrimitive.SubContent>) {
  return (
    <MenubarPrimitive.SubContent
      data-slot="menubar-sub-content"
      className={cn(CONTENT_CLASS, className)}
      {...props}
    />
  )
}

export {
  Menubar,
  MenubarPortal,
  MenubarMenu,
  MenubarTrigger,
  MenubarContent,
  MenubarGroup,
  MenubarSeparator,
  MenubarLabel,
  MenubarItem,
  MenubarShortcut,
  MenubarCheckboxItem,
  MenubarRadioGroup,
  MenubarRadioItem,
  MenubarSub,
  MenubarSubTrigger,
  MenubarSubContent,
}
