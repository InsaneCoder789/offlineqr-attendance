"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  CalendarDays,
  ClipboardCheck,
  LayoutDashboard,
  QrCode,
  RefreshCw,
  Settings,
  ShieldCheck,
  TriangleAlert,
  Wifi,
  WifiOff,
} from "lucide-react";
import { facultyInitials, titleFor, dateLabel } from "@/lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { LoginPage } from "./LoginPage";
import { QrPanel } from "./QrPanel";
import { AttestationDialog } from "./AttestationDialog";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
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
  SidebarSeparator,
  SidebarTrigger,
} from "@/components/ui/sidebar";
import { StatusBadge } from "./PortalUI";

const navItems = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/classes", label: "My classes", icon: CalendarDays },
  { href: "/attendance", label: "Live attendance", icon: QrCode },
  { href: "/records", label: "Records", icon: ClipboardCheck },
  { href: "/settings", label: "Profile & security", icon: Settings },
] as const;

export function FacultyPortalShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { facultyIdentity, online, loading, error, refresh, projectorMode, session } = useFacultyPortal();
  const initials = facultyInitials(facultyIdentity);

  if (!facultyIdentity) return <LoginPage />;
  if (projectorMode && session) return <QrPanel projector />;

  const canSeeGovernance = facultyIdentity.access_role === "ICT_ADMIN" || pathname.startsWith("/admin") || [facultyIdentity.designation, facultyIdentity.org_unit]
    .filter(Boolean)
    .some((value) => /ict|admin|technology/i.test(value ?? ""));

  return (
    <SidebarProvider defaultOpen>
      <Sidebar collapsible="icon" className="border-r border-r-sidebar-border">
        <SidebarHeader className="p-3">
          <Link className="flex h-14 items-center gap-3 overflow-hidden rounded-lg px-2" href="/dashboard">
            <span className="flex size-10 shrink-0 items-center justify-center rounded-lg border bg-white">
              <Image src="/branding/kiit_logo.png" alt="KIIT" width={34} height={34} priority />
            </span>
            <span className="min-w-0 group-data-[collapsible=icon]:hidden">
              <strong className="block truncate text-sm font-semibold">KIIT Attendance</strong>
              <span className="block truncate text-xs text-muted-foreground">Faculty workspace</span>
            </span>
          </Link>
        </SidebarHeader>
        <SidebarSeparator />
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
        <header className="sticky top-0 z-20 flex h-16 items-center justify-between gap-4 border-b-2 border-b-border bg-card/95 px-4 backdrop-blur md:px-6">
          <div className="flex min-w-0 items-center gap-3">
            <SidebarTrigger />
            <div className="min-w-0">
              <p className="hidden truncate text-[11px] font-medium uppercase tracking-[0.12em] text-muted-foreground sm:block">{dateLabel(new Date())}</p>
              <h1 className="truncate text-base font-semibold tracking-tight">{pathname.startsWith("/admin") ? "Device Governance" : titleFor(pathname)}</h1>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <StatusBadge tone={online ? "success" : "warning"} icon={online ? Wifi : WifiOff}>
              <span className="hidden sm:inline">{online ? "Synced" : "Offline"}</span>
            </StatusBadge>
            <Button variant="outline" size="sm" disabled={loading} onClick={() => void refresh()} aria-label="Synchronize portal data">
              <RefreshCw data-icon="inline-start" className={loading ? "animate-spin" : undefined} />
              <span className="hidden sm:inline">{loading ? "Syncing" : "Sync"}</span>
            </Button>
            <Avatar className="size-8"><AvatarFallback>{initials}</AvatarFallback></Avatar>
          </div>
        </header>

        <main className="portal-workspace mx-auto flex w-full max-w-[1480px] flex-col gap-6 p-4 md:p-6 xl:p-8">
          {error ? (
            <Alert variant="destructive">
              <TriangleAlert />
              <AlertTitle>Some live data is unavailable</AlertTitle>
              <AlertDescription>{error}. Saved institutional data remains visible where available.</AlertDescription>
            </Alert>
          ) : null}
          {children}
        </main>
      </SidebarInset>
      <AttestationDialog />
    </SidebarProvider>
  );
}
