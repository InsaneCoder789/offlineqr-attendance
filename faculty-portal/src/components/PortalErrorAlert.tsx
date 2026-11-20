import Link from "next/link";
import { KeyRound, LogIn, TriangleAlert, Timer, WifiOff, ServerCrash } from "lucide-react";
import type { PortalErrorKind } from "../lib/portal-errors";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";

const presentation: Record<PortalErrorKind, { title: string; icon: typeof TriangleAlert }> = {
  password_change_required: { title: "Change your temporary password", icon: KeyRound },
  session_expired: { title: "Your session has ended", icon: LogIn },
  rate_limited: { title: "Too many requests", icon: Timer },
  offline: { title: "You are offline", icon: WifiOff },
  service_unavailable: { title: "Attendance service unavailable", icon: ServerCrash },
  generic: { title: "Something went wrong", icon: TriangleAlert },
};

/** Shows the real server message with a title and action that match the failure category. */
export function PortalErrorAlert({
  message,
  kind,
  title,
  showSettingsLink = true,
}: {
  message: string;
  kind: PortalErrorKind | null;
  title?: string;
  showSettingsLink?: boolean;
}) {
  const view = presentation[kind ?? "generic"];
  const Icon = view.icon;
  return (
    <Alert role={kind === "offline" ? "status" : "alert"} variant={kind === "offline" ? "warning" : "destructive"}>
      <Icon />
      <AlertTitle>{title ?? view.title}</AlertTitle>
      <AlertDescription>
        {message}
        {kind === "password_change_required" && showSettingsLink ? (
          <> <Link href="/settings" className="font-medium underline underline-offset-2">Go to password settings</Link></>
        ) : null}
        {kind === "offline" ? " Saved institutional data remains visible where available." : null}
      </AlertDescription>
    </Alert>
  );
}
