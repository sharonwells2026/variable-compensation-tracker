import { Suspense } from "react";
import "./workflow-overrides.css";

export default function ApprovalWorkflowsLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <Suspense fallback={<div className="workflow-admin-page min-h-screen bg-[#f6f8fc]" />}>
      <div className="workflow-admin-page">{children}</div>
    </Suspense>
  );
}
