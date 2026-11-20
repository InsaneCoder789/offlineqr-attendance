"use client";

import { Analytics } from "@vercel/analytics/next";

export function SiteAnalytics() {
  return <Analytics debug={false} beforeSend={event => {
    if (event.type !== "pageview") return null;
    const url = new URL(event.url);
    // No query strings, fragments, arbitrary visitor paths or customer form values.
    return { ...event, url: `${url.origin}${url.pathname === "/" ? "/" : "/404"}` };
  }} />;
}
