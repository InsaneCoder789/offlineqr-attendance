export type PortalErrorKind =
  | "password_change_required"
  | "session_expired"
  | "rate_limited"
  | "offline"
  | "service_unavailable"
  | "generic";

export type PortalError = { kind: PortalErrorKind; message: string };

type ErrorLike = { status?: unknown; code?: unknown; message?: unknown; name?: unknown };

/**
 * Maps a thrown value (ApiRequestError, fetch TypeError, Error) to a UI category.
 * The server message is kept verbatim whenever one exists.
 */
export function classifyPortalError(exception: unknown, fallback: string, online = true): PortalError {
  const error = (typeof exception === "object" && exception !== null ? exception : {}) as ErrorLike;
  const status = typeof error.status === "number" ? error.status : null;
  const code = typeof error.code === "string" ? error.code : null;
  const message = typeof error.message === "string" && error.message ? error.message : fallback;

  if (code === "FACULTY_PASSWORD_CHANGE_REQUIRED") {
    return { kind: "password_change_required", message: message || "Change your temporary password to continue." };
  }
  if (code === "FACULTY_SESSION_EXPIRED" || (status === 401 && code !== "INVALID_CREDENTIALS")) {
    return { kind: "session_expired", message: code ? message : "Your session has expired. Sign in again to continue." };
  }
  if (code === "RATE_LIMITED" || status === 429) return { kind: "rate_limited", message };
  if (status !== null && status >= 500) return { kind: "service_unavailable", message };
  if (error.name === "TypeError" || !online) {
    return { kind: "offline", message: "You are offline or the attendance service cannot be reached. Saved data stays available." };
  }
  return { kind: "generic", message };
}
