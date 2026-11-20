"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";
import { cn } from "@/lib/utils";
import {
  CalendarDays,
  ClipboardCheck,
  LayoutDashboard,
  QrCode,
  RefreshCw,
  Settings,
  ShieldCheck,
  Wifi,
  WifiOff,
} from "lucide-react";
import { facultyInitials, titleFor, dateLabel } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { useProjectorUi } from "./PortalUiState";
import { PortalErrorAlert } from "./PortalErrorAlert";
import { LoginPage } from "./LoginPage";
import { QrPanel } from "./QrPanel";
import { AttestationDialog } from "./AttestationDialog";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
  SidebarRail,
  SidebarTrigger,
  useSidebar,
} from "@/components/ui/sidebar";
import { StatusBadge } from "./PortalUI";

const navItems = [
  { href: "/dashboard", label: "Dashboard", short: "Home", icon: LayoutDashboard },
  { href: "/classes", label: "My classes", short: "Classes", icon: CalendarDays },
  { href: "/attendance", label: "Live attendance", short: "Live", icon: QrCode },
  { href: "/records", label: "Records", short: "Records", icon: ClipboardCheck },
  { href: "/settings", label: "Profile & security", short: "Profile", icon: Settings },
] as const;

/** Collapses the sidebar to an icon rail below the desktop breakpoint. */
function TabletRail() {
  const { setOpen, isMobile } = useSidebar();
  useEffect(() => {
    if (isMobile) return;
    const query = window.matchMedia("(min-width: 1024px)");
    setOpen(query.matches);
    const onChange = () => setOpen(query.matches);
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, [isMobile, setOpen]);
  return null;
}

function BottomNav({ pathname }: { pathname: string }) {
  return (
    <nav aria-label="Primary" className="bottom-nav-safe fixed inset-x-0 bottom-0 z-30 border-t bg-card/95 backdrop-blur md:hidden">
      <ul className="mx-auto grid max-w-xl grid-cols-5">
        {navItems.map((item) => {
          const active = pathname === item.href || (item.href !== "/dashboard" && pathname.startsWith(item.href));
          const Icon = item.icon;
          return (
            <li key={item.href} className="min-w-0">
              <Link href={item.href} aria-current={active ? "page" : undefined} className={cn("flex min-h-16 flex-col items-center justify-center gap-1 px-1 text-[11px] font-medium leading-tight outline-offset-[-2px]", active ? "text-primary" : "text-muted-foreground")}>
                <Icon className="size-5" aria-hidden="true" />
                <span className="max-w-full truncate">{item.short}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

export function FacultyPortalShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { facultyIdentity, online, loading, error, errorKind, passwordChangeRequired, refresh, session } = usePortalData();
  const { projectorMode } = useProjectorUi();
  const mustChangePassword = Boolean(facultyIdentity) && passwordChangeRequired;
  useEffect(() => {
    if (mustChangePassword && pathname !== "/settings") router.replace("/settings");
  }, [mustChangePassword, pathname, router]);
  const initials = facultyInitials(facultyIdentity);

  if (!facultyIdentity) return <LoginPage />;
  if (projectorMode && session) return <QrPanel projector />;

  const canSeeGovernance = facultyIdentity.access_role === "ICT_ADMIN";
  if (pathname.startsWith("/admin") && !canSeeGovernance) {
    return <main className="mx-auto max-w-lg p-10"><h1 className="text-2xl font-semibold">Administrator access required</h1><p className="mt-3">Device governance is available to authorized institution administrators.</p><Link className="mt-6 inline-block underline" href="/dashboard">Return to workspace</Link></main>;
  }

  return (
    <SidebarProvider defaultOpen>
      <TabletRail />
      <a href="#main-content" className="sr-only focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:z-50 focus:rounded-md focus:bg-background focus:px-3 focus:py-2 focus:text-sm focus:font-medium focus:shadow-lg">Skip to main content</a>
      <Sidebar collapsible="icon" className="border-r border-r-sidebar-border/70">
        <SidebarHeader className="h-[4.5rem] shrink-0 flex-row items-center gap-2 border-b border-sidebar-border/70 p-2.5">
          <Link className="flex min-w-0 flex-1 items-center gap-2.5 overflow-hidden px-1 group-data-[collapsible=icon]:hidden" href="/dashboard">
            <span className="flex size-9 shrink-0 items-center justify-center border border-sidebar-border bg-white">
              <Image src="/branding/offlineqr-mark.svg" alt="OfflineQR" width={30} height={30} priority />
            </span>
            <span className="min-w-0">
              <strong className="block truncate text-[13px] font-semibold leading-5">OfflineQR</strong>
              <span className="block truncate text-[11px] leading-4 text-muted-foreground">Faculty workspace</span>
            </span>
          </Link>
          <SidebarTrigger className="size-8 shrink-0 border border-sidebar-border bg-sidebar hover:bg-sidebar-accent" />
        </SidebarHeader>
        <SidebarContent>
          <SidebarGroup>
            <SidebarGroupLabel>Teaching operations</SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {navItems.map((item) => {
                  const active = pathname === item.href || (item.href !== "/dashboard" && pathname.startsWith(item.href));
                  const Icon = item.icon;
                  return (
                    <SidebarMenuItem key={item.href}>
                      <SidebarMenuButton render={<Link href={item.href} />} isActive={active} tooltip={item.label} className="h-10">
                        <Icon />
                        <span>{item.label}</span>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  );
                })}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
          {canSeeGovernance ? (
            <SidebarGroup>
              <SidebarGroupLabel>Institution controls</SidebarGroupLabel>
              <SidebarGroupContent>
                <SidebarMenu>
                  <SidebarMenuItem>
                    <SidebarMenuButton render={<Link href="/admin" />} isActive={pathname.startsWith("/admin")} tooltip="Device governance" className="h-10">
                      <ShieldCheck />
                      <span>Device governance</span>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          ) : null}
        </SidebarContent>
        <SidebarFooter className="p-3">
          <div className="flex items-center gap-3 overflow-hidden rounded-lg border bg-card p-2 group-data-[collapsible=icon]:border-transparent group-data-[collapsible=icon]:bg-transparent group-data-[collapsible=icon]:p-0">
            <Avatar className="size-9 shrink-0"><AvatarFallback>{initials}</AvatarFallback></Avatar>
            <div className="min-w-0 group-data-[collapsible=icon]:hidden">
              <strong className="block truncate text-xs font-semibold">{facultyIdentity.display_name}</strong>
              <span className="flex items-center gap-1 truncate text-[11px] text-muted-foreground">
                {online ? <Wifi className="size-3" /> : <WifiOff className="size-3" />}
                {online ? "Connected" : "Offline ready"}
              </span>
            </div>
          </div>
        </SidebarFooter>
        <SidebarRail />
      </Sidebar>

      <SidebarInset className="min-w-0 bg-background">
        <header className="sticky top-0 z-20 flex h-[4.5rem] items-center justify-between gap-2 sm:gap-4 border-b border-b-border/70 bg-card/95 px-4 backdrop-blur md:px-6">
          <div className="flex min-w-0 items-center gap-3">
            <SidebarTrigger className="size-10 border border-border bg-card md:hidden" aria-label="Open navigation menu" />
            <span className="hidden h-7 w-0.5 bg-border md:block" aria-hidden="true" />
            <div className="min-w-0">
              <p className="hidden truncate text-[10px] font-semibold uppercase text-muted-foreground sm:block">{dateLabel(new Date())}</p>
              <h1 className="truncate text-base font-semibold">{pathname.startsWith("/admin") ? "Device Governance" : titleFor(pathname)}</h1>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <span role="status" aria-live="polite">
              <StatusBadge tone={online ? "success" : "warning"} icon={online ? Wifi : WifiOff}>
                <span className="hidden sm:inline">{online ? "Synced" : "Offline"}</span>
                <span className="sr-only sm:hidden">{online ? "Synced" : "Offline"}</span>
              </StatusBadge>
            </span>
            <Button variant="outline" size="sm" disabled={loading} onClick={() => void refresh()} aria-label="Synchronize portal data">
              <RefreshCw data-icon="inline-start" className={loading ? "animate-spin" : undefined} />
              <span className="hidden sm:inline">{loading ? "Syncing" : "Sync"}</span>
            </Button>
            <Avatar className="hidden size-8 sm:flex"><AvatarFallback>{initials}</AvatarFallback></Avatar>
          </div>
        </header>

        {!online ? (
          <div role="status" className="sticky top-[4.5rem] z-10 flex items-center justify-center gap-2 border-b border-warning/40 bg-warning/15 px-4 py-2 text-center text-xs font-medium text-foreground">
            <WifiOff className="size-3.5 shrink-0" aria-hidden="true" />Offline. Saved data stays available and changes reconcile when you reconnect.
          </div>
        ) : null}
        <main id="main-content" tabIndex={-1} className="portal-workspace mx-auto flex w-full min-w-0 max-w-[1480px] flex-col gap-5 p-4 pb-[calc(var(--bottom-nav-h)+1.5rem)] md:p-6 md:pb-6 xl:p-8">
          {mustChangePassword && errorKind !== "password_change_required" ? (
            <PortalErrorAlert kind="password_change_required" message="Your account uses a temporary password. Set a new password below before using the portal." showSettingsLink={pathname !== "/settings"} />
          ) : null}
          {error ? (
            <PortalErrorAlert kind={errorKind} message={error} title={errorKind === "generic" || errorKind === null ? "Some live data is unavailable" : undefined} showSettingsLink={pathname !== "/settings"} />
          ) : null}
          {children}
        </main>
      </SidebarInset>
      <BottomNav pathname={pathname} />
      <AttestationDialog />
    </SidebarProvider>
  );
}
