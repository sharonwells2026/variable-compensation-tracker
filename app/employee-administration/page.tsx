"use client";

import { ArrowLeft, ShieldCheck } from "lucide-react";
import EmployeeAdministration from "../components/employee-administration";

export default function EmployeeAdministrationPage() {
  const go=(screen:any)=>{
    if(screen==="settings") window.location.href="/user-administration";
    else if(screen==="plans") window.location.href="/";
  };

  return (
    <main className="employee-admin-route min-h-screen bg-[#f6f8fc] text-[#252b35]">
      <header className="border-t-[7px] border-[#a7e3e5] bg-white shadow-sm">
        <div className="mx-auto flex max-w-[1500px] items-center justify-between px-6 py-4">
          <div className="flex items-center gap-4">
            <a href="/" className="grid h-9 w-9 place-items-center rounded-lg border text-[#2095f3]" aria-label="Back to compensation">
              <ArrowLeft size={17}/>
            </a>
            <div>
              <p className="text-[10px] font-extrabold tracking-[.12em] text-[#8d939c]">ADMINISTRATION</p>
              <h1 className="text-xl font-bold">Employee & User Administration</h1>
            </div>
          </div>
          <div className="flex items-center gap-2 rounded-lg bg-[#edf6ff] px-3 py-2 text-xs font-semibold text-[#0879d5]">
            <ShieldCheck size={15}/> Access-controlled
          </div>
        </div>
      </header>
      <div className="mx-auto max-w-[1500px] px-6 py-6">
        <EmployeeAdministration go={go}/>
      </div>
    </main>
  );
}
