"use client";

import { useEffect } from "react";

export function OfflineRuntime() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;
    void navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch(() => {
      // Keep the workspace usable when offline storage is unavailable.
    });
  }, []);

  return null;
}
