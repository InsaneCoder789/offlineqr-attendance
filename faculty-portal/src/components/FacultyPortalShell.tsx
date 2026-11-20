"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { cn } from "@/lib/utils";
import {
  CalendarDays,
  ClipboardCheck,
  CornerDownLeft,
  LayoutDashboard,
  Moon,
  QrCode,
  RefreshCw,
  Search,
  Settings,
  ShieldCheck,
  Sun,
  Wifi,
  WifiOff,
} from "lucide-react";
import { useTheme } from "next-themes";
import { facultyInitials, titleFor, dateLabel } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { useProjectorUi } from "./PortalUiState";
import { PortalErrorAlert } from "./PortalErrorAlert";
import { LoginPage } from "./LoginPage";
import { QrPanel } from "./QrPanel";
import { AttestationDialog } from "./AttestationDialog";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
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

const navItems = [
  { href: "/dashboard", label: "Preview", short: "Preview", icon: LayoutDashboard },
  { href: "/classes", label: "My classes", short: "Classes", icon: CalendarDays },
  { href: "/attendance", label: "Live attendance", short: "Live", icon: QrCode },
  { href: "/records", label: "Records", short: "Records", icon: ClipboardCheck },
  { href: "/settings", label: "Profile & security", short: "Profile", icon: Settings },
] as const;

function isActivePath(pathname: string, href: string): boolean {
  return pathname === href || (href !== "/dashboard" && pathname.startsWith(href));
}

function CloseMobileNavigation({ pathname }: { pathname: string }) {
  const { setOpenMobile } = useSidebar();
  useEffect(() => { setOpenMobile(false); }, [pathname, setOpenMobile]);
  return null;
}

function BottomNav({ pathname }: { pathname: string }) {
  const admin = pathname.startsWith("/admin");
  const items = admin
    ? [{ href: "/admin", short: "Devices", icon: ShieldCheck }, { href: "/dashboard", short: "Faculty", icon: LayoutDashboard }]
    : navItems;
  return (
    <nav aria-label="Primary" className="bottom-nav-safe fixed inset-x-0 bottom-0 z-30 px-3 pb-2 md:hidden">
      <ul className={cn("mx-auto grid max-w-xl gap-1 rounded-lg border bg-card p-1.5", admin ? "grid-cols-2" : "grid-cols-5")}>
        {items.map((item) => {
          const active = isActivePath(pathname, item.href);
          const Icon = item.icon;
          return (
            <li key={item.href} className="min-w-0">
              <Link
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "flex min-h-14 flex-col items-center justify-center gap-0.5 rounded-2xl px-1 text-[11px] font-semibold leading-tight transition-colors",
                  active ? "pill-neon" : "text-muted-foreground hover:text-foreground",
                )}
              >
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

const subscribeNoop = () => () => {};
function useMounted(): boolean {
  return useSyncExternalStore(subscribeNoop, () => true, () => false);
}

const toolbarButton = "size-10 rounded-lg";

function ThemeToggle() {
  const { resolvedTheme, setTheme } = useTheme();
  const mounted = useMounted();
  const dark = mounted ? resolvedTheme !== "light" : true;
  return (
    <Button
      variant="outline"
      size="icon"
      className={toolbarButton}
      aria-label={dark ? "Switch to light theme" : "Switch to dark theme"}
      onClick={() => setTheme(dark ? "light" : "dark")}
    >
      {dark ? <Sun /> : <Moon />}
    </Button>
  );
}

type Command = { id: string; label: string; hint: string; href: string; icon: typeof LayoutDashboard };

function CommandPalette({ open, onOpenChange, admin }: { open: boolean; onOpenChange: (open: boolean) => void; admin: boolean }) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [cursor, setCursor] = useState(0);
  const listRef = useRef<HTMLUListElement>(null);
  const commands = useMemo<Command[]>(() => {
    const list: Command[] = [
      { id: "dashboard", label: "Preview", hint: "Today’s teaching desk", href: "/dashboard", icon: LayoutDashboard },
      { id: "classes", label: "Classes", hint: "Schedule and assigned courses", href: "/classes", icon: CalendarDays },
      { id: "attendance", label: "Live attendance", hint: "QR session and roster", href: "/attendance", icon: QrCode },
      { id: "records", label: "Records", hint: "Registers and export", href: "/records", icon: ClipboardCheck },
      { id: "settings", label: "Settings", hint: "Profile and security", href: "/settings", icon: Settings },
    ];
    if (admin) list.push({ id: "admin", label: "Device governance", hint: "Approvals and device inventory", href: "/admin", icon: ShieldCheck });
    return list;
  }, [admin]);
  const results = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return needle ? commands.filter((item) => `${item.label} ${item.hint}`.toLowerCase().includes(needle)) : commands;
  }, [commands, query]);
  const active = Math.min(cursor, Math.max(0, results.length - 1));

  function go(item: Command | undefined) {
    if (!item) return;
    onOpenChange(false);
    router.push(item.href);
  }

  return (
    <Dialog open={open} onOpenChange={(next) => { onOpenChange(next); if (!next) { setQuery(""); setCursor(0); } }}>
      <DialogContent showCloseButton={false} className="gap-0 p-0 sm:top-[18%] sm:max-w-lg sm:translate-y-0">
        <DialogTitle className="sr-only">Command palette</DialogTitle>
        <DialogDescription className="sr-only">Type to jump to a page. Use arrow keys and Enter.</DialogDescription>
        <div className="flex items-center gap-3 border-b border-border px-4">
          <Search className="size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
          <input
            autoFocus
            role="combobox"
            aria-expanded="true"
            aria-controls="command-list"
            aria-activedescendant={results[active] ? `cmd-${results[active].id}` : undefined}
            aria-label="Search pages"
            placeholder="Jump to a page"
            value={query}
            onChange={(event) => { setQuery(event.target.value); setCursor(0); }}
            onKeyDown={(event) => {
              if (event.key === "ArrowDown") { event.preventDefault(); setCursor((active + 1) % Math.max(1, results.length)); }
              else if (event.key === "ArrowUp") { event.preventDefault(); setCursor((active - 1 + results.length) % Math.max(1, results.length)); }
              else if (event.key === "Enter") { event.preventDefault(); go(results[active]); }
            }}
            className="h-14 min-w-0 flex-1 bg-transparent text-base outline-none placeholder:text-muted-foreground"
          />
          <kbd className="hidden rounded-md border border-border px-1.5 py-0.5 text-[10px] font-semibold text-muted-foreground sm:block">ESC</kbd>
        </div>
        <ul id="command-list" role="listbox" aria-label="Pages" ref={listRef} className="scroll-thin max-h-[min(22rem,50dvh)] overflow-y-auto p-2">
          {results.length === 0 ? <li className="px-3 py-8 text-center text-sm text-muted-foreground">No matching pages.</li> : null}
          {results.map((item, index) => {
            const Icon = item.icon;
            return (
              <li
                key={item.id}
                id={`cmd-${item.id}`}
                role="option"
                aria-selected={index === active}
                onMouseMove={() => setCursor(index)}
                onClick={() => go(item)}
                className={cn("flex min-h-12 cursor-pointer items-center gap-3 rounded-xl px-3 py-2", index === active ? "bg-primary/14 text-foreground" : "text-muted-foreground")}
              >
                <span className={cn("flex size-9 shrink-0 items-center justify-center rounded-xl", index === active ? "pill-neon" : "bg-muted")}><Icon className="size-4" aria-hidden="true" /></span>
                <span className="min-w-0 flex-1">
                  <strong className="block truncate text-sm font-semibold text-foreground">{item.label}</strong>
                  <span className="block truncate text-xs">{item.hint}</span>
                </span>
                {index === active ? <CornerDownLeft className="size-4 shrink-0" aria-hidden="true" /> : null}
              </li>
            );
          })}
        </ul>
      </DialogContent>
    </Dialog>
  );
}

function crumbsFor(pathname: string): string[] {
  if (pathname.startsWith("/admin/devices")) return ["Device governance", "Device"];
  if (pathname.startsWith("/admin")) return ["Device governance"];
  return [titleFor(pathname)];
}

export function FacultyPortalShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { facultyIdentity, authReady, online, loading, error, errorKind, passwordChangeRequired, refresh, session } = usePortalData();
  const { projectorMode } = useProjectorUi();
  const [paletteOpen, setPaletteOpen] = useState(false);
  const mustChangePassword = Boolean(facultyIdentity) && passwordChangeRequired;
  useEffect(() => {
    if (!authReady) return;
    if (!facultyIdentity && pathname !== "/login") router.replace("/login");
    else if (mustChangePassword && pathname !== "/settings") router.replace("/settings");
    else if (facultyIdentity && pathname === "/login") router.replace("/dashboard");
  }, [authReady, facultyIdentity, mustChangePassword, pathname, router]);
  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setPaletteOpen((open) => !open);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  const initials = facultyInitials(facultyIdentity);
  const connectionLabel = !online ? "Offline" : loading ? "Updating" : error ? "Needs attention" : "Network available";

  if (authReady && !facultyIdentity && pathname === "/login") return <LoginPage />;
  if (!authReady || !facultyIdentity || pathname === "/login" || (mustChangePassword && pathname !== "/settings")) {
    return <main className="grid min-h-dvh place-items-center text-sm text-muted-foreground" role="status">Opening workspace…</main>;
  }
  if (projectorMode && session) return <QrPanel projector />;

  const canSeeGovernance = facultyIdentity.access_role === "ICT_ADMIN";
  if (pathname.startsWith("/admin") && !canSeeGovernance) {
    return <main className="mx-auto max-w-lg p-10"><h1 className="text-2xl font-semibold">Administrator access required</h1><p className="mt-3">Device governance is available to authorized institution administrators.</p><Link className="mt-6 inline-block underline" href="/dashboard">Return to workspace</Link></main>;
  }
  const crumbs = crumbsFor(pathname);
  const adminWorkspace = pathname.startsWith("/admin");
  const pageTitle = adminWorkspace ? "Device governance" : titleFor(pathname);

  return (
    <SidebarProvider defaultOpen className="silk-workspace">
      <CloseMobileNavigation pathname={pathname} />
      <a href="#main-content" className="sr-only focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:z-50 focus:rounded-xl focus:bg-background focus:px-4 focus:py-2.5 focus:text-sm focus:font-semibold focus:shadow-lg">Skip to main content</a>
      <Sidebar collapsible="icon" className="border-r border-r-sidebar-border">
        <SidebarHeader className="h-[4.5rem] shrink-0 flex-row items-center gap-2 border-b border-sidebar-border p-3 group-data-[collapsible=icon]:justify-center">
          <Link className="flex min-w-0 flex-1 items-center gap-3 overflow-hidden px-1 group-data-[collapsible=icon]:hidden" href={adminWorkspace ? "/admin" : "/dashboard"} aria-label={adminWorkspace ? "IT workspace" : "Faculty workspace"}>
            <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-white shadow-[0_0_20px_-6px_var(--glow)]">
              <Image src="/branding/offlineqr-mark.svg" alt="" width={30} height={30} priority />
            </span>
            <span className="min-w-0">
              <strong className="block truncate text-sm font-bold leading-5 tracking-tight">OfflineQR</strong>
              <span className="block truncate text-[11px] leading-4 text-muted-foreground">{adminWorkspace ? "IT administration" : "Faculty workspace"}</span>
            </span>
          </Link>
          <SidebarTrigger className={`${toolbarButton} shrink-0 border border-sidebar-border md:hidden`} aria-label="Close navigation menu" />
        </SidebarHeader>
        <SidebarContent className="px-2 py-3">
          {!adminWorkspace && <SidebarGroup>
            <SidebarGroupLabel className="eyebrow !text-[10px]">Teaching operations</SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu className="gap-1">
                {navItems.map((item) => {
                  const active = isActivePath(pathname, item.href);
                  const Icon = item.icon;
                  return (
                    <SidebarMenuItem key={item.href}>
                      <SidebarMenuButton render={<Link href={item.href} aria-current={active ? "page" : undefined} />} isActive={active} tooltip={item.label} className="h-11">
                        <Icon />
                        <span>{item.label}</span>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  );
                })}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>}
          {canSeeGovernance ? (
            <SidebarGroup>
              <SidebarGroupLabel className="eyebrow !text-[10px]">Institution controls</SidebarGroupLabel>
              <SidebarGroupContent>
                <SidebarMenu>
                  <SidebarMenuItem>
                    <SidebarMenuButton render={<Link href="/admin" aria-current={pathname.startsWith("/admin") ? "page" : undefined} />} isActive={pathname.startsWith("/admin")} tooltip="Device governance" className="h-11">
                      <ShieldCheck />
                      <span>Device governance</span>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                  {adminWorkspace && <SidebarMenuItem>
                    <SidebarMenuButton render={<Link href="/dashboard" />} tooltip="Faculty workspace" className="h-11">
                      <LayoutDashboard />
                      <span>Faculty workspace</span>
                    </SidebarMenuButton>
                  </SidebarMenuItem>}
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          ) : null}
        </SidebarContent>
        <SidebarFooter className="p-3">
          <div className="flex items-center gap-3 overflow-hidden rounded-2xl border border-sidebar-border bg-foreground/[0.03] p-2.5 group-data-[collapsible=icon]:justify-center group-data-[collapsible=icon]:border-transparent group-data-[collapsible=icon]:bg-transparent group-data-[collapsible=icon]:p-0">
            <Avatar className="size-9 shrink-0"><AvatarFallback>{initials}</AvatarFallback></Avatar>
            <div className="min-w-0 group-data-[collapsible=icon]:hidden">
              <strong className="block truncate text-xs font-semibold">{facultyIdentity.display_name}</strong>
              <span className="flex items-center gap-1 truncate text-[11px] text-muted-foreground">
                {online ? <Wifi className="size-3" aria-hidden="true" /> : <WifiOff className="size-3" aria-hidden="true" />}
                {connectionLabel}
              </span>
            </div>
          </div>
        </SidebarFooter>
        <SidebarRail />
      </Sidebar>

      <SidebarInset className="portal-canvas min-w-0">
        <header className="sticky top-0 z-20 flex h-[4.5rem] items-center justify-between gap-2 border-b border-b-border bg-[color-mix(in_oklab,var(--canvas)_72%,transparent)] px-4 backdrop-blur-2xl sm:gap-4 md:px-6">
          <div className="flex min-w-0 items-center gap-3">
            <SidebarTrigger className={`${toolbarButton} shrink-0 border border-input`} />
            <div className="min-w-0">
              <nav aria-label="Breadcrumb" className="hidden sm:block">
                <ol className="flex items-center gap-1.5 text-[11px] font-medium text-muted-foreground">
                  <li><Link href="/dashboard" className="hover:text-foreground">Workspace</Link></li>
                  {crumbs.map((crumb) => <li key={crumb} className="flex items-center gap-1.5"><span aria-hidden="true">/</span><span className="truncate">{crumb}</span></li>)}
                </ol>
              </nav>
              <h1 className="line-clamp-2 text-sm font-bold leading-tight tracking-tight sm:text-lg">{pageTitle}</h1>
              <span className="sr-only">{dateLabel(new Date())}</span>
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-1.5 sm:gap-2" aria-label="Workspace controls">
            <span role="status" className="sr-only md:not-sr-only md:mr-1 md:inline-flex md:items-center md:gap-1.5 md:text-xs md:font-medium md:text-muted-foreground">
              {online ? <Wifi className="size-4" aria-hidden="true" /> : <WifiOff className="size-4" aria-hidden="true" />}
              {connectionLabel}
            </span>
            <Button variant="outline" size="icon" className={toolbarButton} onClick={() => setPaletteOpen(true)} aria-label="Search workspace" title="Search workspace"><Search /></Button>
            <Button variant="outline" size="icon" className={`${toolbarButton} max-[359px]:hidden`} disabled={loading} onClick={() => void refresh()} aria-label="Refresh portal data" title="Refresh portal data">
              <RefreshCw aria-hidden="true" className={loading ? "motion-safe:animate-spin" : undefined} />
            </Button>
            <ThemeToggle />
            <DropdownMenu>
              <DropdownMenuTrigger aria-label="Account menu" render={<Button variant="outline" size="icon" className={toolbarButton} />}>
                <Avatar className="size-7"><AvatarFallback>{initials}</AvatarFallback></Avatar>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="min-w-56">
                <DropdownMenuGroup>
                  <DropdownMenuLabel className="flex flex-col gap-0.5 px-2.5 py-2">
                    <strong className="truncate text-sm text-foreground">{facultyIdentity.display_name}</strong>
                    <span className="text-xs font-normal text-muted-foreground">{connectionLabel}</span>
                  </DropdownMenuLabel>
                </DropdownMenuGroup>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => router.push("/settings")}><Settings />Profile & security</DropdownMenuItem>
                {canSeeGovernance ? <DropdownMenuItem onClick={() => router.push("/admin")}><ShieldCheck />Device governance</DropdownMenuItem> : null}
                <DropdownMenuItem disabled={loading} onClick={() => void refresh()}><RefreshCw />Refresh workspace</DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </header>

        {!online ? (
          <div role="status" className="sticky top-[4.5rem] z-10 flex items-center justify-center gap-2 border-b border-warning/30 bg-[color-mix(in_oklab,var(--amber-soft)_100%,var(--canvas))] px-4 py-2 text-center text-xs font-semibold text-foreground backdrop-blur">
            <WifiOff className="size-3.5 shrink-0 text-warning" aria-hidden="true" />Offline. Showing saved data where available.
          </div>
        ) : null}
        <main id="main-content" tabIndex={-1} className="portal-workspace mx-auto flex w-full min-w-0 max-w-[1280px] flex-col gap-5 p-4 pb-[calc(var(--bottom-nav-h)+1.5rem+env(safe-area-inset-bottom))] outline-none md:p-6 md:pb-6 xl:p-8 min-[1900px]:max-w-[1440px]">
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
      <CommandPalette open={paletteOpen} onOpenChange={setPaletteOpen} admin={canSeeGovernance} />
      <AttestationDialog />
    </SidebarProvider>
  );
}
