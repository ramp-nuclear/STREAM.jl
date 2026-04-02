import { ChevronDown } from "lucide-react";
import { Button } from "./ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import useStore from "../store/useStore";

interface Props {
  onUnsavedCheck: () => Promise<"save" | "discard" | "cancel">;
}

export default function FileMenu({ onUnsavedCheck }: Props) {
  const isDirty = useStore((s) => s.isDirty);
  const saveProject = useStore((s) => s.saveProject);
  const saveProjectAs = useStore((s) => s.saveProjectAs);
  const loadProject = useStore((s) => s.loadProject);
  const newProject = useStore((s) => s.newProject);

  async function handleNew() {
    if (isDirty) {
      const action = await onUnsavedCheck();
      if (action === "cancel") return;
      if (action === "save") await saveProject();
    }
    await newProject();
  }

  async function handleOpen() {
    if (isDirty) {
      const action = await onUnsavedCheck();
      if (action === "cancel") return;
      if (action === "save") await saveProject();
    }
    await loadProject();
  }

  async function handleSave() {
    await saveProject();
  }

  async function handleSaveAs() {
    await saveProjectAs();
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm">
          File
          <ChevronDown className="h-3.5 w-3.5 ml-1" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start">
        <DropdownMenuItem onClick={handleNew}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>New</span>
            <span className="text-muted-foreground text-xs">Ctrl+N</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuItem onClick={handleOpen}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Open...</span>
            <span className="text-muted-foreground text-xs">Ctrl+O</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuItem onClick={handleSave}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Save</span>
            <span className="text-muted-foreground text-xs">Ctrl+S</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuItem onClick={handleSaveAs}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Save As...</span>
            <span className="text-muted-foreground text-xs">Ctrl+Shift+S</span>
          </span>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
