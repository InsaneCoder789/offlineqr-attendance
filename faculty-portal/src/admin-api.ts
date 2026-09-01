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
};

const apiBase = process.env.NEXT_PUBLIC_API_BASE ?? "http://127.0.0.1:8000";

function headers(key: string, operator: string): HeadersInit {
  return {
    "Content-Type": "application/json",
    "x-ict-approval-key": key,
    "x-ict-operator": operator || "ict-admin",
  };
}

async function request<T>(path: string, key: string, operator: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${apiBase}${path}`, {
    ...init,
    headers: { ...headers(key, operator), ...(init?.headers ?? {}) },
    cache: "no-store",
  });
  if (!response.ok) {
    const body = await response.json().catch(() => null) as { error?: { message?: string } } | null;
    throw new Error(body?.error?.message ?? `ICT request failed (${response.status})`);
  }
  return response.json() as Promise<T>;
}

export const adminApi = {
  stats: (key: string, operator: string) => request<AdminStats>("/api/v1/admin/device-stats", key, operator),
  devices: (key: string, operator: string, query = "", status = "") =>
    request<AdminDevice[]>(`/api/v1/admin/devices?query=${encodeURIComponent(query)}&status=${encodeURIComponent(status)}`, key, operator),
  device: (key: string, operator: string, id: string) => request<AdminDeviceDetail>(`/api/v1/admin/devices/${id}`, key, operator),
  history: (key: string, operator: string, id: string) => request<AdminDeviceHistory[]>(`/api/v1/admin/devices/${id}/history`, key, operator),
  replacements: (key: string, operator: string) => request<ReplacementRequest[]>("/api/v1/admin/device-replacements", key, operator),
  approve: (key: string, operator: string, id: string, note: string) => request(`/api/v1/admin/device-replacements/${id}/approve`, key, operator, { method: "POST", body: JSON.stringify({ note }) }),
  reject: (key: string, operator: string, id: string, note: string) => request(`/api/v1/admin/device-replacements/${id}/reject`, key, operator, { method: "POST", body: JSON.stringify({ note }) }),
  revoke: (key: string, operator: string, id: string, reason: string) => request(`/api/v1/admin/devices/${id}/revoke`, key, operator, { method: "POST", body: JSON.stringify({ reason }) }),
};
