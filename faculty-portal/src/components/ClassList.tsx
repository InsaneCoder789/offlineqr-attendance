"use client";

import type { FacultyClass } from "@/api";
import { useRouter } from "next/navigation";
import { CalendarX2, Clock3, DoorOpen, Play, Radio } from "lucide-react";
import { formatTime, stateClass, stateLabel } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { EmptyPanel, LoadingPanel, StatusBadge } from "./PortalUI";

export function ClassList({ items }: { items: FacultyClass[] }) {
  const router = useRouter();
  const { session, start, loading } = usePortalData();

  if (items.length === 0 && loading) return <LoadingPanel rows={3} label="Loading classes" />;
  if (items.length === 0) {
    return <EmptyPanel icon={CalendarX2} title="No classes scheduled today" description="Your synchronized teaching timetable will appear here." className="m-5" />;
  }

  return (
    <div className="space-y-1 p-3">
      {items.map((item, index) => {
        const tone = stateClass(item, session);
        const isOtherSessionActive = Boolean(session && !session.closed_at && session.course_offering_id !== item.course_offering_id);
        const isThisSessionActive = Boolean(session && !session.closed_at && session.course_offering_id === item.course_offering_id);
        return (
          <article className={`grid min-w-0 gap-4 rounded-lg px-4 py-4 transition-colors md:grid-cols-[8.5rem_minmax(0,1fr)_auto_auto] md:items-center ${isThisSessionActive ? "bg-primary/10" : "hover:bg-muted/60"}`} key={`${item.course_offering_id}:${item.start_time}:${item.end_time}:${index}`}>
            <time className="flex items-center gap-2 text-sm font-semibold"><Clock3 className="size-4 text-primary" />{formatTime(item.start_time)} - {formatTime(item.end_time)}</time>
            <div className="min-w-0">
              <strong className="block truncate text-sm font-semibold">{item.course_name}</strong>
              <p className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                <span>{item.course_code} · {item.section_code}</span>
                <span className="flex items-center gap-1"><DoorOpen className="size-3.5" />Room {item.room}</span>
              </p>
            </div>
            <StatusBadge tone={tone === "success" ? "success" : tone === "warning" ? "warning" : "neutral"} icon={isThisSessionActive ? Radio : undefined}>{stateLabel(item, session)}</StatusBadge>
            <Button
              className="max-md:w-full"
              size="sm"
              variant={isThisSessionActive ? "outline" : "default"}
              disabled={isOtherSessionActive}
              title={isOtherSessionActive ? "Close the active session first" : undefined}
              onClick={async () => {
                if (isThisSessionActive || await start(item.course_offering_id)) router.push("/attendance");
              }}
            >
              {isThisSessionActive ? <Radio data-icon="inline-start" /> : <Play data-icon="inline-start" />}
              {isThisSessionActive ? "Open live" : "Start"}
            </Button>
          </article>
        );
      })}
    </div>
  );
}
