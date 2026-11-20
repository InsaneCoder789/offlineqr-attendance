import { copyFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const target = path.dirname(fileURLToPath(import.meta.url));
const source = path.resolve(target, "../../faculty-portal");
const components = [
  "ScrollEditorial.tsx", "ImageStory.tsx", "PricingSection.tsx", "ClassroomScene.tsx",
  "PublicPage.tsx", "public-page.module.css", "story-model.ts", "story.module.css", "image-story.module.css",
];
await mkdir(path.join(target, "src/components/marketing"), { recursive: true });
for (const name of components) {
  await copyFile(path.join(source, "src/components/marketing", name), path.join(target, "src/components/marketing", name));
}
await mkdir(path.join(target, "public/branding"), { recursive: true });
for (const name of ["offlineqr-mark.svg", "classroom-hd.webp", "classroom-mobile.webp", "devices-hd.webp"]) {
  await copyFile(path.join(source, "public/branding", name), path.join(target, "public/branding", name));
}
await mkdir(path.join(target, "src/lib/commercial"), { recursive: true });
await mkdir(path.join(target, "src/app/api/proposals"), { recursive: true });
await mkdir(path.join(target, "server-assets/commercial"), { recursive: true });
for (const name of ["proposal-model.ts", "proposal-pdf.ts", "proposal-http.ts"]) {
  await copyFile(path.join(source, "src/lib/commercial", name), path.join(target, "src/lib/commercial", name));
}
await copyFile(path.join(source, "src/app/api/proposals/route.ts"), path.join(target, "src/app/api/proposals/route.ts"));
for (const name of ["Manrope-Regular.ttf", "Manrope-SemiBold.ttf", "Manrope-Bold.ttf", "logo.png"]) {
  await copyFile(path.join(source, "server-assets/commercial", name), path.join(target, "server-assets/commercial", name));
}
console.log("Prepared editorial and proposal PDF endpoint only; no workspace routes, customer records or secrets copied.");

for (const name of ["public-pages.ts", "public-site.ts"]) {
  await copyFile(path.join(source, "src/lib", name), path.join(target, "src/lib", name));
}
for (const name of ["not-found.tsx", "robots.ts", "sitemap.ts", "privacy/page.tsx", "terms/page.tsx", "contact/page.tsx", "accessibility/page.tsx"]) {
  await mkdir(path.dirname(path.join(target, "src/app", name)), { recursive: true });
  await copyFile(path.join(source, "src/app", name), path.join(target, "src/app", name));
}
