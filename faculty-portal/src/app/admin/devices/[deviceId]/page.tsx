import { AdminDeviceDetail } from "../../../../components/admin/AdminDeviceDetail";

export default async function AdminDevicePage({ params }: { params: Promise<{ deviceId: string }> }) {
  const { deviceId } = await params;
  return <AdminDeviceDetail deviceId={deviceId} />;
}
