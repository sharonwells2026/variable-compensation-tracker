"use client";

import EmployeeAdministration from "../components/employee-administration";
import AdminShell from "../components/admin-shell";

export default function EmployeeAdministrationPage() {
  return (
    <AdminShell
      section="people"
      title="People & Access"
      description="Employee records, application access, compensation participation, and readiness."
    >
      <EmployeeAdministration />
    </AdminShell>
  );
}
