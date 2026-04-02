import { Button } from "./ui/button";
import useStore from "../store/useStore";

export default function WelcomeOverlay() {
  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  const recentFiles = useStore((s) => s.recentFiles);
  const loadProject = useStore((s) => s.loadProject);
  const loadProjectFromPath = useStore((s) => s.loadProjectFromPath);

  if (nodes.length > 0 || edges.length > 0) {
    return null;
  }

  async function handleOpenFromOverlay() {
    await loadProject();
  }

  return (
    <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
      <div className="pointer-events-auto bg-background border rounded-lg shadow-lg p-8 max-w-sm w-full">
        <h2 className="text-xl font-semibold">STREAM Composer</h2>

        {recentFiles.length > 0 ? (
          <>
            <p className="text-sm font-semibold text-muted-foreground mt-6">
              Recent Projects
            </p>
            <div className="mt-2">
              {recentFiles.slice(0, 5).map((fullPath) => {
                const filename = fullPath.split(/[/\\]/).pop() ?? fullPath;
                return (
                  <div
                    key={fullPath}
                    className="text-sm py-1 px-2 rounded cursor-pointer hover:bg-accent truncate"
                    onClick={() => loadProjectFromPath(fullPath)}
                    title={fullPath}
                  >
                    {filename}
                  </div>
                );
              })}
            </div>
          </>
        ) : (
          <p className="text-sm text-muted-foreground mt-6">
            Open an existing project or drag components onto the canvas to get
            started.
          </p>
        )}

        <Button
          variant="outline"
          size="sm"
          className="mt-6"
          onClick={handleOpenFromOverlay}
        >
          Open Project...
        </Button>
      </div>
    </div>
  );
}
