type IconName =
  | "dashboard"
  | "classes"
  | "attendance"
  | "records"
  | "settings"
  | "refresh"
  | "monitor"
  | "stop"
  | "play"
  | "check"
  | "alert"
  | "room"
  | "clock"
  | "wifiOff"
  | "wifiOn";

const paths: Record<IconName, string[]> = {
  dashboard: [
    "M3 3h5v5H3z",
    "M12 3h5v5h-5z",
    "M3 12h5v5H3z",
    "M12 12h5v5h-5z",
  ],
  classes: ["M4 4h12a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z", "M7 8h6", "M7 11h4"],
  attendance: ["M9 3H5a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-4", "M13 3l4 4-6 6-4 1 1-4 5-7z"],
  records: ["M6 2h8a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z", "M8 7h4", "M8 10h4", "M8 13h2"],
  settings: ["M10 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6z", "M10 2v2", "M10 16v2", "M2 10h2", "M16 10h2", "M4.22 4.22l1.42 1.42", "M14.36 14.36l1.42 1.42", "M4.22 15.78l1.42-1.42", "M14.36 5.64l1.42-1.42"],
  refresh: ["M3.5 7A7 7 0 1 1 3 10", "M1 4l2.5 3 2.5-3"],
  monitor: ["M2 3h16v11H2z", "M7 18h6", "M10 14v4"],
  stop: ["M5 5h10v10H5z"],
  play: ["M6 4l12 6-12 6V4z"],
  check: ["M4 10l5 5 7-8"],
  alert: ["M10 3L2 17h16L10 3z", "M10 9v4", "M10 15h.01"],
  room: ["M3 3h14v14H3V3z", "M8 17v-4h4v4", "M3 8h14"],
  clock: ["M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16z", "M10 6v4l3 2"],
  wifiOff: ["M3 3l14 14", "M10.5 17.5a.5.5 0 1 1-1 0 .5.5 0 0 1 1 0z", "M7.5 14.5a3.5 3.5 0 0 1 5 0", "M5 11.5a7 7 0 0 1 3.5-2", "M2 8.5A11 11 0 0 1 10 6c1.5 0 2.9.3 4.2.8"],
  wifiOn: ["M10.5 17.5a.5.5 0 1 1-1 0 .5.5 0 0 1 1 0z", "M7.5 14.5a3.5 3.5 0 0 1 5 0", "M5 11.5a7 7 0 0 1 10 0", "M2 8.5a11 11 0 0 1 16 0"],
};

export function Icon({ name }: { name: IconName }) {
  return (
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {paths[name].map((d) => <path key={d} d={d} />)}
    </svg>
  );
}
