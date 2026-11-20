"use client";

import { ThemeProvider as NextThemes } from "next-themes";
import { usePathname } from "next/navigation";

/** Dark by default for the workspace; the public marketing page stays light. */
export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  return (
    <NextThemes
      attribute="class"
      defaultTheme="light"
      enableSystem={false}
      storageKey="offlineqr-theme"
      disableTransitionOnChange
      forcedTheme={pathname === "/" ? "light" : undefined}
    >
      {children}
    </NextThemes>
  );
}
