import { useState } from "react";
import { Button } from "./ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import AboutDialog from "./AboutDialog";

/**
 * Help menu (Phase 67 D-12).
 *
 * - About STREAM Composer opens AboutDialog (controlled via local state).
 * - Keyboard Shortcuts is a disabled stub deferred to Phase 72.
 *
 * The AboutDialog is rendered as a sibling AFTER the closing </DropdownMenu>
 * to keep JSX flat — Radix Portal handles z-order either way.
 */
export default function HelpMenu() {
  const [aboutOpen, setAboutOpen] = useState(false);

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="sm" className="h-7 px-2 text-xs font-normal">
            Help
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start">
          <DropdownMenuItem onClick={() => setAboutOpen(true)}>
            <span>About STREAM Composer</span>
          </DropdownMenuItem>
          <DropdownMenuItem disabled>
            <span>Keyboard Shortcuts</span>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <AboutDialog open={aboutOpen} onOpenChange={setAboutOpen} />
    </>
  );
}
