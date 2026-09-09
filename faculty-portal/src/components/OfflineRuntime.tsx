"use client";

import { useEffect } from "react";

export function OfflineRuntime() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;
    void navigator.serviceWorker.register("/sw.js", { scope: "/" });
  }, []);

  return null;
}
