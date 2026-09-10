type DeviceVisualProps = {
  manufacturer?: string | null;
  platform: string;
  className?: string;
};

export function DeviceVisual({ manufacturer, platform, className = "" }: DeviceVisualProps) {
  const family = `${manufacturer ?? ""} ${platform}`.toLowerCase();
  const label = family.includes("apple") || family.includes("ios") ? "iOS" : family.includes("samsung") ? "Samsung" : "Android";
  return (
    <span className={cn("flex size-11 shrink-0 items-center justify-center rounded-lg border bg-muted text-primary", className)} aria-label={`${manufacturer ?? platform} mobile device`} title={label}>
      <Smartphone className="size-5" />
    </span>
  );
}
import { Smartphone } from "lucide-react";
import { cn } from "@/lib/utils";
