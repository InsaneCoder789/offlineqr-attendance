import type { MetadataRoute } from "next";
import { siteOrigin } from "../lib/public-site";

export default function robots(): MetadataRoute.Robots {
  return { rules: { userAgent: "*", allow: "/", disallow: "/api/" }, sitemap: new URL("/sitemap.xml", siteOrigin).href };
}
