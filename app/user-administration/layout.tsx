import "./user-administration.css";

export default function UserAdministrationLayout({children}:{children:React.ReactNode}){
  return <div className="user-admin-route-shell">{children}</div>;
}
