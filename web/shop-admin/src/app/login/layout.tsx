// Login routes get a minimal layout — no left rail, no top bar. The
// dashboard shell only applies under (dashboard) routes; /login lives
// outside that group so unauthenticated users don't see nav for things
// they can't access yet.

export default function LoginLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/30 p-6">
      <div className="w-full max-w-sm">{children}</div>
    </div>
  );
}
