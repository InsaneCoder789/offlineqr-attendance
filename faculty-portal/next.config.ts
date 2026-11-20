import type { NextConfig } from "next";

const apiBase = process.env.NEXT_PUBLIC_ATTENDANCE_API_BASE ?? "http://127.0.0.1:8000";
const apiOrigin = new URL(apiBase).origin;
const websocketOrigin = apiOrigin.replace(/^http/, "ws");
const developmentConnections = "http://localhost:8000 ws://localhost:8000 http://127.0.0.1:8000 ws://127.0.0.1:8000";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  devIndicators: false,
  outputFileTracingIncludes: { "/api/proposals": ["./server-assets/commercial/*"] },
  distDir: process.env.NEXT_DIST_DIR ?? ".next",
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Referrer-Policy", value: "no-referrer" },
          { key: "Permissions-Policy", value: "camera=(self), geolocation=(), microphone=()" },
          {
            key: "Content-Security-Policy",
            value: [
              "default-src 'self'",
              "img-src 'self' data: blob:",
              "style-src 'self' 'unsafe-inline'",
              `script-src 'self' 'unsafe-inline'${process.env.NODE_ENV === "development" ? " 'unsafe-eval'" : ""}`,
              `connect-src 'self' ${apiOrigin} ${websocketOrigin}${process.env.NODE_ENV === "development" ? ` ${developmentConnections}` : ""}`,
              "worker-src 'self' blob:",
              "frame-ancestors 'none'",
              "base-uri 'self'",
              "form-action 'self'",
              "object-src 'none'",
            ].join("; "),
          },
        ],
      },
    ];
  },
};

export default nextConfig;
