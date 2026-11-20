import { cn } from "cn"

function Skeleton({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="skeleton"
      className={cn("shimmer rounded-xl motion-reduce:animate-none", className)}
      {...props}
    />
  )
}

export { Skeleton }
