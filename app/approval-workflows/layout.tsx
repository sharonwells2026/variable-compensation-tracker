import { Suspense } from "react";
import AdminShell from "../components/admin-shell";
import "./workflow-overrides.css";

export default function ApprovalWorkflowsLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <AdminShell
      section="approvals"
      title="Approval Workflows"
      description="Effective-dated approval routing, finance handoffs, and workflow readiness."
    >
      <Suspense fallback={<div className="workflow-admin-page min-h-[420px]" />}>
        <div className="workflow-admin-page">{children}</div>
      </Suspense>
    </AdminShell>
  );
}
