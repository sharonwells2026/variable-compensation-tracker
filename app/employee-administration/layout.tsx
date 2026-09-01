import "./employee-administration.css";

export default function EmployeeAdministrationLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <div className="employee-admin-route-shell">{children}</div>;
}
