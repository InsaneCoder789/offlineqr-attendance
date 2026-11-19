"use client";

import { useEffect, useRef } from "react";

/**
 * Keeps one live-update socket open for an active session, falling back to
 * polling and reconnecting while the socket is down. `onChange` may change
 * identity freely; the connection is only rebuilt when the target changes.
 */
export function useSessionEvents(sessionId: string | null, enabled: boolean, urlFor: (id: string) => string, onChange: (id: string) => void): void {
  const onChangeRef = useRef(onChange);
  const urlForRef = useRef(urlFor);
  useEffect(() => { onChangeRef.current = onChange; urlForRef.current = urlFor; });

  useEffect(() => {
    if (!sessionId || !enabled) return;
    let socket: WebSocket | null = null;
    let fallbackTimer: number | null = null;
    let reconnectTimer: number | null = null;
    let disposed = false;
    const notify = () => onChangeRef.current(sessionId);

    const connect = () => {
      if (disposed) return;
      socket = new WebSocket(urlForRef.current(sessionId));
      socket.onopen = () => {
        if (fallbackTimer !== null) { window.clearInterval(fallbackTimer); fallbackTimer = null; }
      };
      socket.onmessage = notify;
      socket.onerror = () => socket?.close();
      socket.onclose = () => {
        if (disposed) return;
        if (fallbackTimer === null) fallbackTimer = window.setInterval(notify, 5000);
        reconnectTimer = window.setTimeout(connect, 4000);
      };
    };
    connect();
    return () => {
      disposed = true;
      socket?.close();
      if (fallbackTimer !== null) window.clearInterval(fallbackTimer);
      if (reconnectTimer !== null) window.clearTimeout(reconnectTimer);
    };
  }, [sessionId, enabled]);
}
