"use client";

import { Analytics } from "@vercel/analytics/next";
import { publicPages } from "../lib/public-pages";

const trackedPaths = new Set<string>(["/", ...publicPages.map(({ path }) => path)]);

export function SiteAnalytics() {
  return <Analytics debug={false} beforeSend={event => {
    if (event.type !== "pageview") return null;
    const url = new URL(event.url);
    // No query strings, fragments, arbitrary visitor paths or customer form values.
    return { ...event, url: `${url.origin}${trackedPaths.has(url.pathname) ? url.pathname : "/404"}` };
  }} />;
}
