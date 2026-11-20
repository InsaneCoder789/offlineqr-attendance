import { FacultyPortalProvider } from "@/components/FacultyPortalProvider";
import { FacultyPortalShell } from "@/components/FacultyPortalShell";
import { OfflineRuntime } from "@/components/OfflineRuntime";

export default function WorkspaceLayout({ children }: { children: React.ReactNode }) {
  return <FacultyPortalProvider><OfflineRuntime /><FacultyPortalShell>{children}</FacultyPortalShell></FacultyPortalProvider>;
}
