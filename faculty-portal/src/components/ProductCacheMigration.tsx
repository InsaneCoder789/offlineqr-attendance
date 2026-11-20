"use client";

import { useEffect } from "react";
import { clearFacultyIdentity } from "@/api";

export function ProductCacheMigration() {
  useEffect(() => {
    try {
      if (localStorage.getItem("offlineqr.productCacheVersion") === "2") return;
      clearFacultyIdentity();
      localStorage.setItem("offlineqr.productCacheVersion", "2");
      if ("caches" in window) void caches.delete("offlineqr-faculty-shell-v1").catch(() => {});
    } catch { /* Public pages work even when browser storage is blocked. */ }
  }, []);
  return null;
}
