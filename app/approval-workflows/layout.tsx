import "./workflow-overrides.css";

export default function ApprovalWorkflowsLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return <div className="workflow-admin-page">{children}</div>;
}
