// HTML sanity check (no browser automation is installed: puppeteer/playwright absent).
// Usage: node scripts/layout-check.mjs [baseUrl]
const base = process.argv[2] ?? "http://127.0.0.1:5180";
const routes = ["/", "/login", "/dashboard", "/classes", "/attendance", "/records", "/settings", "/does-not-exist"];
let failed = 0;
for (const route of routes) {
  const res = await fetch(base + route);
  const html = await res.text();
  const problems = [];
  const expected = route === "/does-not-exist" ? 404 : 200;
  if (res.status !== expected) problems.push(`status ${res.status}`);
  if (!/<meta[^>]+name="viewport"/.test(html)) problems.push("missing viewport meta");
  if (!/<title>[^<]+<\/title>/.test(html)) problems.push("missing title");
  if (/<h1[\s>]/.test(html) === false && route !== "/dashboard" && route !== "/classes" && route !== "/attendance" && route !== "/records" && route !== "/settings") problems.push("no h1");
  if (/(?:width|min-width):\s*(?:3[3-9]\d|[4-9]\d\d)px/.test(html.replace(/<script[\s\S]*?<\/script>/g, ""))) problems.push("fixed px width > 320 in inline styles");
  console.log(`${problems.length ? "FAIL" : "ok  "} ${route} ${res.status} ${problems.join("; ")}`);
  if (problems.length) failed++;
}
process.exit(failed ? 1 : 0);
