"use client"

import * as React from "react"
import { Command as CommandPrimitive } from "cmdk"
import { SearchIcon } from "lucide-react"

import { cn } from "@/lib/utils"

// Phase 69 Plan 01 — shadcn `command.tsx` shim around cmdk primitives.
//
// Verbatim adaptation of the canonical shadcn template
// (apps/v4/registry/new-york-v4/ui/command.tsx from github.com/shadcn-ui/ui,
// verified 2026-05-18). The only deviation from the canonical file is that
// the centering dialog wrapper is intentionally omitted — the canonical
// wrapper composes a centered DialogContent, which would defeat D-02
// (top-anchored overlay). Plan 02 rolls a top-anchored variant directly in
// CommandPalette.tsx using radix Dialog primitives + this shim's parts.
//
// Phase 72 — primitive-layer recommit:
//   - Container rounded-md, bg-popover (unchanged at this layer)
//   - Input wrapper h-8 (was h-9), text-[12px] (was text-sm), placeholder
//     foreground/45 (was muted-foreground)
//   - Group heading: text-micro uppercase tracking-wider opacity-55
//   - Item h-7, hover/selected bg-card (was bg-accent)
//   - Shortcut: text-micro font-mono opacity-55 (was text-xs tracking-widest)
//   - Empty: text-[12px] opacity-65 (was text-sm)

function Command({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive>) {
  return (
    <CommandPrimitive
      data-slot="command"
      className={cn(
        "flex h-full w-full flex-col overflow-hidden rounded-md bg-popover text-foreground",
        className
      )}
      {...props}
    />
  )
}

function CommandInput({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Input>) {
  return (
    <div
      data-slot="command-input-wrapper"
      className="flex h-8 items-center gap-1.5 border-b border-border px-3"
    >
      <SearchIcon className="size-3.5 shrink-0 stroke-[1.5] text-foreground/85" />
      <CommandPrimitive.Input
        data-slot="command-input"
        className={cn(
          "flex h-8 w-full bg-transparent text-[12px] outline-hidden placeholder:text-foreground/45 disabled:cursor-not-allowed disabled:opacity-50",
          className
        )}
        {...props}
      />
    </div>
  )
}

function CommandList({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.List>) {
  return (
    <CommandPrimitive.List
      data-slot="command-list"
      className={cn(
        "max-h-[400px] scroll-py-1 overflow-x-hidden overflow-y-auto",
        className
      )}
      {...props}
    />
  )
}

function CommandEmpty({
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Empty>) {
  return (
    <CommandPrimitive.Empty
      data-slot="command-empty"
      className="py-6 text-center text-[12px] text-foreground"
      {...props}
    />
  )
}

function CommandGroup({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Group>) {
  return (
    <CommandPrimitive.Group
      data-slot="command-group"
      className={cn(
        "overflow-hidden p-1 text-foreground [&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:py-1 [&_[cmdk-group-heading]]:text-micro [&_[cmdk-group-heading]]:font-medium [&_[cmdk-group-heading]]:uppercase [&_[cmdk-group-heading]]:tracking-wider [&_[cmdk-group-heading]]:text-foreground/55",
        className
      )}
      {...props}
    />
  )
}

function CommandSeparator({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Separator>) {
  return (
    <CommandPrimitive.Separator
      data-slot="command-separator"
      className={cn("-mx-1 h-px bg-border", className)}
      {...props}
    />
  )
}

function CommandItem({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Item>) {
  return (
    <CommandPrimitive.Item
      data-slot="command-item"
      className={cn(
        "relative flex h-7 cursor-default items-center gap-1.5 rounded-sm px-2 text-[12px] outline-hidden select-none transition-colors duration-[80ms] motion-reduce:transition-none data-[disabled=true]:pointer-events-none data-[disabled=true]:opacity-50 data-[selected=true]:bg-card [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-3.5 [&_svg]:stroke-[1.5] [&_svg:not([class*='text-'])]:text-foreground/85",
        className
      )}
      {...props}
    />
  )
}

function CommandShortcut({
  className,
  ...props
}: React.ComponentProps<"span">) {
  return (
    <span
      data-slot="command-shortcut"
      className={cn(
        "ml-auto text-micro font-mono text-foreground/55",
        className
      )}
      {...props}
    />
  )
}

export {
  Command,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
  CommandItem,
  CommandSeparator,
  CommandShortcut,
}
