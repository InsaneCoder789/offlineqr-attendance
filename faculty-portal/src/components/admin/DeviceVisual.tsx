import { Smartphone } from "lucide-react";
import { cn } from "@/lib/utils";

type DeviceVisualProps = {
  manufacturer?: string | null;
  platform: string;
  className?: string;
};

export function DeviceVisual({ manufacturer, platform, className = "" }: DeviceVisualProps) {
  const family = `${manufacturer ?? ""} ${platform}`.toLowerCase();
  const label = family.includes("apple") || family.includes("ios") ? "iOS" : family.includes("samsung") ? "Samsung" : "Android";
  return (
    <span className={cn("flex size-11 shrink-0 items-center justify-center rounded-xl border border-primary/30 bg-primary/10 text-primary shadow-[0_0_24px_-10px_var(--primary)]", className)} aria-label={`${manufacturer ?? platform} mobile device`} title={label}>
      <Smartphone className="size-5" />
    </span>
  );
}
