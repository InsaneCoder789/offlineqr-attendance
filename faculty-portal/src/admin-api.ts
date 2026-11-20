export type AdminDevice = {
  id: string;
  device_reference: string;
  student_id: string;
  roll_number: string;
  student_name: string;
  section_code: string;
  status: "ACTIVE" | "PENDING" | "REVOKED";
  platform: string;
  manufacturer?: string | null;
  device_model?: string | null;
  os_version?: string | null;
  is_physical_device?: boolean | null;
  integrity_status: string;
  risk_flags: string[];
  display_label?: string | null;
  registered_at?: string | null;
  last_seen_at?: string | null;
  pending_replacement_id?: string | null;
};

export type AdminDeviceDetail = AdminDevice & {
  key_fingerprint: string;
  revoked_at?: string | null;
  app_instance_metadata: Record<string, unknown>;
};

export type AdminDeviceHistory = {
  id: string;
  event_type: string;
  actor_type: string;
  occurred_at: string;
  correlation_id: string;
  metadata: Record<string, unknown>;
};

export type AdminStats = {
  total_devices: number;
  active_devices: number;
  pending_replacements: number;
  review_required: number;
  revoked_devices: number;
};

export type ReplacementRequest = {
  id: string;
  student_id: string;
  roll_number: string;
  student_name: string;
  old_device_registration_id: string;
  new_device_registration_id: string;
  reason: string;
  requested_at: string;
  old_platform: string;
  old_manufacturer?: string | null;
  old_model?: string | null;
  new_platform: string;
  new_manufacturer?: string | null;
  new_model?: string | null;
  new_integrity_status: string;
  new_risk_flags: string[];
  status?: "PENDING" | "APPROVED";
};

export type DeviceActivationQr = {
  replacement_request_id: string;
  qr_payload: string;
  expires_at: string;
};

const apiBase = process.env.NEXT_PUBLIC_API_BASE ?? "http://127.0.0.1:8000";

function csrfHeaders(init?: RequestInit): HeadersInit {
  const csrf = typeof document === "undefined" ? "" : document.cookie.split("; ").find((item) => item.startsWith("offlineqr_faculty_csrf="))?.split("=")[1] ?? "";
  return { "Content-Type": "application/json", ...(init?.method && init.method !== "GET" ? { "X-CSRF-Token": decodeURIComponent(csrf) } : {}) };
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${apiBase}${path}`, {
    ...init,
    headers: { ...csrfHeaders(init), ...(init?.headers ?? {}) },
    credentials: "include",
    cache: "no-store",
  });
  if (!response.ok) {
    const body = await response.json().catch(() => null) as { error?: { message?: string } } | null;
    throw new Error(body?.error?.message ?? `ICT request failed (${response.status})`);
  }
  return response.json() as Promise<T>;
}

export const adminApi = {
  stats: () => request<AdminStats>("/api/v1/admin/device-stats"),
  devices: (query = "", status = "") => request<AdminDevice[]>(`/api/v1/admin/devices?query=${encodeURIComponent(query)}&status=${encodeURIComponent(status)}`),
  device: (id: string) => request<AdminDeviceDetail>(`/api/v1/admin/devices/${id}`),
  history: (id: string) => request<AdminDeviceHistory[]>(`/api/v1/admin/devices/${id}/history`),
  replacements: () => request<ReplacementRequest[]>("/api/v1/admin/device-replacements"),
  approve: (id: string, note: string) => request(`/api/v1/admin/device-replacements/${id}/approve`, { method: "POST", body: JSON.stringify({ note }) }),
  activationQr: (id: string) => request<DeviceActivationQr>(`/api/v1/admin/device-replacements/${id}/activation-qr`, { method: "POST" }),
  reject: (id: string, note: string) => request(`/api/v1/admin/device-replacements/${id}/reject`, { method: "POST", body: JSON.stringify({ note }) }),
  revoke: (id: string, reason: string) => request(`/api/v1/admin/devices/${id}/revoke`, { method: "POST", body: JSON.stringify({ reason }) }),
};
