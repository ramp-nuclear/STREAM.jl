import { Toaster as SonnerToaster, toast } from "sonner"
import type { ToasterProps } from "sonner"

import { useTheme } from "@/hooks/useTheme"

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
      {...props}
    />
  )
}

export { Toaster, toast }
