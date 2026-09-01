type DeviceVisualProps = {
  manufacturer?: string | null;
  platform: string;
  className?: string;
};

export function DeviceVisual({ manufacturer, platform, className = "" }: DeviceVisualProps) {
  const family = `${manufacturer ?? ""} ${platform}`.toLowerCase();
  const kind = family.includes("apple") || family.includes("ios") ? "apple" : family.includes("samsung") ? "samsung" : "android";
  return <span className={`device-visual ${kind} ${className}`} aria-label={`${manufacturer ?? platform} mobile device`} />;
}
