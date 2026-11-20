"use client";

import type { FacultyClass } from "@/api";
import { useRouter } from "next/navigation";
import { CalendarX2, Clock3, DoorOpen, Play, Radio } from "lucide-react";
import { formatTime, stateClass, stateLabel } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { courseAccentStyle, EmptyPanel, LoadingPanel, StatusBadge } from "./PortalUI";

export function ClassList({ items }: { items: FacultyClass[] }) {
  const router = useRouter();
  const { session, start, loading } = usePortalData();

  if (items.length === 0 && loading) return <LoadingPanel rows={3} label="Loading classes" />;
  if (items.length === 0) {
    return <EmptyPanel icon={CalendarX2} title="No classes scheduled today" description="Your synchronized teaching timetable will appear here." className="m-5" />;
  }

  return (
    <ul className="grid gap-3 p-3 sm:p-4">
      {items.map((item, index) => {
        const tone = stateClass(item, session);
        const isOtherSessionActive = Boolean(session && !session.closed_at && session.course_offering_id !== item.course_offering_id);
        const isThisSessionActive = Boolean(session && !session.closed_at && session.course_offering_id === item.course_offering_id);
        return (
          <li
            className={`course-accent enter relative grid min-w-0 gap-3 overflow-hidden rounded-2xl border py-4 pl-5 pr-4 transition-colors md:grid-cols-[9rem_minmax(0,1fr)_auto_auto] md:items-center md:gap-4 ${isThisSessionActive ? "border-primary/40 bg-primary/10 glow-green-soft" : "border-border bg-foreground/[0.025] hover:bg-foreground/[0.05]"}`}
            style={courseAccentStyle(item.course_code)}
            key={`${item.course_offering_id}:${item.start_time}:${item.end_time}:${index}`}
          >
            <span className="bar-accent-course absolute inset-y-3 left-0 w-1 rounded-r-full" aria-hidden="true" />
            <time className="flex items-center gap-2 text-sm font-bold tabular-nums"><Clock3 className="size-4 text-accent-course" aria-hidden="true" />{formatTime(item.start_time)} - {formatTime(item.end_time)}</time>
            <div className="min-w-0">
              <strong className="block truncate text-sm font-semibold">{item.course_name}</strong>
              <p className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                <span>{item.course_code} · {item.section_code}</span>
                <span className="flex items-center gap-1"><DoorOpen className="size-3.5" aria-hidden="true" />Room {item.room}</span>
              </p>
            </div>
            <StatusBadge tone={tone === "success" ? "success" : tone === "warning" ? "warning" : "neutral"} icon={isThisSessionActive ? Radio : undefined}>{stateLabel(item, session)}</StatusBadge>
            <Button
              className="max-md:w-full"
              size="default"
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
          </li>
        );
      })}
    </ul>
  );
}
