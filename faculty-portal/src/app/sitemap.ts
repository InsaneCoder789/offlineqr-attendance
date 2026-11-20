import type { MetadataRoute } from "next";
import { publicPages } from "../lib/public-pages";
import { siteOrigin } from "../lib/public-site";

export default function sitemap(): MetadataRoute.Sitemap {
  return ["/", ...publicPages.map(({ path }) => path)].map((path) => ({ url: new URL(path, siteOrigin).href }));
}
