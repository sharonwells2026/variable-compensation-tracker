"use client";
import {useEffect,useState} from "react";
import {Activity,AlertTriangle,BarChart3,Bot,CheckCircle2,ChevronRight,CircleDollarSign,CircleHelp,Clock3,Copy,Download,Eye,FileCheck2,Filter,History,LayoutDashboard,Menu,MessageSquare,Pencil,RefreshCw,Search,Send,Settings,ShieldCheck,TrendingUp,UserPlus,Users,WalletCards,X} from "lucide-react";
import {createClient} from "@supabase/supabase-js";

type Mode="management"|"employee"; type Workspace="self"|"team"|"administration"; type Screen="dashboard"|"approvals"|"employees"|"plans"|"payments"|"reconciliation"|"hubspot"|"rules"|"settings"|"logs"|"help";
type HubSpotSummary={deals:number;companies:number;associations:number;unlinkedDeals:number;unreviewedChanges:number;lastSync:string|null;recentChanges:Array<{detected_at:string;deal_name:string;field_name:string;old_value:string|null;new_value:string|null;review_status:string}>};
type AccessSummary={authenticated:boolean;user_id?:string;email?:string;full_name?:string;employee_id?:string|null;is_active?:boolean;roles:string[];permissions:string[]};
const emptyHubSpot:HubSpotSummary={deals:0,companies:0,associations:0,unlinkedDeals:0,unreviewedChanges:0,lastSync:null,recentChanges:[]};
// These are public browser connection values, not privileged database secrets.
// The fallbacks keep Sites archive builds connected when build-time env injection is unavailable.
const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;
const manager=[ ["dashboard","Dashboard",LayoutDashboard],["approvals","Approvals",ShieldCheck],["employees","Employees",Users],["plans","Compensation Plans",FileCheck2],["payments","Payments",WalletCards],["reconciliation","Reconciliation",History] ] as const;
const admin=[["hubspot","HubSpot Integration",RefreshCw],["rules","Rules & Calculations",BarChart3],["settings","Settings",Settings],["logs","Activity Log",Activity],["help","Help",CircleHelp]] as const;
const employee=[["dashboard","My Dashboard",LayoutDashboard],["plans","My Plan",FileCheck2],["employees","My Earnings",BarChart3],["approvals","Submit for Approval",Send],["payments","Payments & Statements",WalletCards],["help","Help",CircleHelp]] as const;
const titles:Record<Screen,string>={dashboard:"Dashboard",approvals:"Approvals",employees:"Employees",plans:"Compensation Plans",payments:"Payments",reconciliation:"Reconciliation",hubspot:"HubSpot Integration",rules:"Rules & Calculations",settings:"Settings",logs:"Activity Log",help:"Help"};

type PlanComponent={name:string;rate:string;description:string;calculation:string;scope:string;earned:string;eligible:string;effective:string;accent:"blue"|"green"|"orange"|"violet"};
const wesComponents:PlanComponent[]=[
  {name:"Retention commission",rate:"2%",description:"Rewards retained customer revenue assigned to Wes.",calculation:"HubSpot Deal Amount × 2%",scope:"Renewal deals in GovAffairs or MEams where Wes is the deal owner. Owner/CEM mismatches require review.",earned:"Closed Won Finance, Invoiced, or Paid",eligible:"Closed Won Paid with an Invoice Paid Date",effective:"Dec 12, 2025",accent:"green"},
  {name:"Expansion commission",rate:"10%",description:"Rewards additional revenue sold to an existing customer.",calculation:"HubSpot Deal Amount × 10%",scope:"Expansion deals selected by this plan component in GovAffairs or MEams.",earned:"Closed Won Finance, Invoiced, or Paid",eligible:"Closed Won Paid with an Invoice Paid Date",effective:"Dec 12, 2025",accent:"blue"},
  {name:"GovAffairs new sales",rate:"8–12%",description:"Pays a term-based rate on new Government Affairs business.",calculation:"Average ARR × 8% for 1 year, 10% for 2–3 years, or 12% for 4+ years",scope:"New Business deals in the GovAffairs pipeline selected by this plan.",earned:"Closed Won Finance, Invoiced, or Paid",eligible:"Closed Won Paid with an Invoice Paid Date",effective:"Dec 12, 2025",accent:"violet"},
  {name:"Year-end book bonus",rate:"$5,000",description:"Rewards ending the year above the assigned book-of-business target.",calculation:"$5,000 when ending book of business exceeds $700,000",scope:"Wes’s frozen starting book plus qualifying annual changes.",earned:"Calculated at year end",eligible:"After year-end validation and approval",effective:"2026 plan year",accent:"orange"}
];
const sharonComponents:PlanComponent[]=[
  {name:"GovAffairs new sales override",rate:"3%",description:"Sharon receives an override on GovAffairs new sales she did not personally own as the AE.",calculation:"Average ARR × 3%",scope:"All qualifying GovAffairs New Business deals where Sharon is not the deal owner.",earned:"Closed Won Finance, Invoiced, or Paid",eligible:"Closed Won Paid with an Invoice Paid Date",effective:"Apr 1, 2023",accent:"blue"},
  {name:"MEams new sales override",rate:"3% → 6%",description:"The MEams override increased when the dedicated go-to-market motion launched.",calculation:"Average ARR × 3% through Jul 31, 2024; Average ARR × 6% beginning Aug 1, 2024",scope:"All qualifying MEams New Business deals where Sharon is not the deal owner.",earned:"Closed Won Finance, Invoiced, or Paid",eligible:"Closed Won Paid with an Invoice Paid Date",effective:"Apr 1, 2023; rate change Aug 1, 2024",accent:"violet"},
  {name:"Expansion ARR override",rate:"2%",description:"Sharon receives an override whenever Engagifii expands an existing customer relationship.",calculation:"HubSpot Deal Amount × 2%",scope:"All qualifying Expansion deals, in any pipeline and for any deal owner.",earned:"Closed Won Finance, Invoiced, or Paid",eligible:"Closed Won Paid with an Invoice Paid Date",effective:"Apr 1, 2023",accent:"green"},
  {name:"One-time fees override",rate:"3%",description:"Pays an override on qualifying implementation and other one-time-fee deals.",calculation:"HubSpot Deal Amount × 3%",scope:"All deals typed One-time Fees, in any pipeline and for any owner.",earned:"Closed Won Finance, Invoiced, or Paid",eligible:"Closed Won Paid with an Invoice Paid Date",effective:"Oct 1, 2023",accent:"orange"},
  {name:"Renewal ARR override",rate:"2%",description:"Tracks Sharon’s company-wide renewal override, including amounts historically held from submission.",calculation:"HubSpot Deal Amount × 2%",scope:"All Renewal deals, in any pipeline and for any owner.",earned:"Closed Won Finance, Invoiced, or Paid",eligible:"Closed Won Paid with an Invoice Paid Date; payment hold can be managed separately",effective:"Aug 1, 2024",accent:"green"},
  {name:"Completed QDC bonus",rate:"$30 each",description:"Every completed qualifying discovery call earns a fixed bonus.",calculation:"Number of HubSpot meetings with Meeting Type = QDC and Outcome = Completed × $30",scope:"Every completed QDC meeting counts, including multiple completed QDCs on one deal.",earned:"Immediately when the meeting is completed",eligible:"Immediately when the meeting is completed",effective:"Apr 1, 2023",accent:"blue"},
  {name:"Annual revenue milestones",rate:"$1K–$5K",description:"Cumulative bonuses reward company-wide New Business and Expansion ARR growth.",calculation:"$1K at $100K and $150K; $2K at $200K and $250K; $3K at $300K and $350K; $4K at $400K and $450K; $5K at $500K",scope:"All earned New Business and Expansion ARR across every pipeline and owner. Milestones reset each January 1.",earned:"Immediately when each annual threshold is reached",eligible:"Immediately; customer payment is not required",effective:"Apr 1, 2023; calendar-year measurement thereafter",accent:"violet"}
];

export default function Home(){
  const[mode,setMode]=useState<Mode>("management"),[workspace,setWorkspace]=useState<Workspace>("administration"),[screen,setScreen]=useState<Screen>("dashboard"),[period,setPeriod]=useState("YTD"),[notice,setNotice]=useState(""),[hubspot,setHubspot]=useState<HubSpotSummary>(emptyHubSpot),[syncing,setSyncing]=useState(false),[hubspotError,setHubspotError]=useState(""),[access,setAccess]=useState<AccessSummary|null>(null),[mobileMenu,setMobileMenu]=useState(false);
  const go=(x:Screen)=>{setScreen(x);setMobileMenu(false)};
  const toast=(x:string)=>{setNotice(x);setTimeout(()=>setNotice(""),2600)};
  const can=(permission:string)=>Boolean(access?.permissions?.includes(permission));
  const isSystemAdmin=Boolean(access?.roles?.includes("system_administrator"));
  const hasManagementAccess=isSystemAdmin||Boolean(access?.roles?.some(role=>["management_approver","finance_payroll","plan_administrator","auditor_read_only"].includes(role)));
  const hasEmployeeAccess=Boolean(access?.employee_id)||isSystemAdmin;
  const chooseWorkspace=(next:Workspace)=>{setWorkspace(next);setMode(next==="self"?"employee":"management");go("dashboard")};
  const loadHubSpot=async()=>{if(!supabase||!isSystemAdmin)return;const{data,error}=await supabase.rpc("get_compensation_dashboard_data");if(error){setHubspotError(error.message);return}setHubspotError("");if(data)setHubspot(data as HubSpotSummary)};
  const loadAccess=async()=>{if(!supabase)return null;const{data,error}=await supabase.rpc("get_current_user_access");if(error){setHubspotError(error.message);return null}const next=data as AccessSummary;setAccess(next);return next};
  useEffect(()=>{if(!supabase)return;const hydrate=async()=>{const{data:{session}}=await supabase.auth.getSession();if(!session){setAccess(null);setHubspotError("Sign in required");return}const next=await loadAccess();if(next&&!next.roles?.includes("system_administrator")&&next.employee_id)setMode("employee")};hydrate();const{data}=supabase.auth.onAuthStateChange((_event,session)=>{if(session)setTimeout(hydrate,50);else{setAccess(null);setHubspot(emptyHubSpot);setHubspotError("Sign in required")}});return()=>data.subscription.unsubscribe()},[]);
  useEffect(()=>{if(isSystemAdmin)loadHubSpot()},[isSystemAdmin]);
  const refreshHubSpot=async()=>{if(!supabase)return toast("Database connection is unavailable");if(!can("hubspot.refresh"))return toast("You do not have permission to refresh HubSpot");setSyncing(true);const{error}=await supabase.rpc("refresh_compensation_management_data",{force_refresh:true});if(error)toast(error.message);else{await loadHubSpot();toast("HubSpot and compensation data refreshed")};setSyncing(false)};
  const managerPermission:Partial<Record<Screen,string[]>>={approvals:["earnings.approve"],employees:["earnings.view"],plans:["plans.view"],payments:["payments.view"],reconciliation:["flags.resolve","audit.view_assigned","audit.view_all"]};
  const adminPermission:Partial<Record<Screen,string[]>>={hubspot:["hubspot.refresh"],rules:["plans.edit"],settings:["settings.manage","users.manage","notifications.configure_own"],logs:["audit.view_assigned","audit.view_all"]};
  // Until the permission migration is activated, preserve the complete
  // management navigation instead of hiding valid pages while access loads.
  const allowed=(id:Screen,map:Partial<Record<Screen,string[]>>)=>!access||id==="dashboard"||id==="help"||isSystemAdmin||Boolean(map[id]?.some(can));
  const nav=(mode==="management"?manager:employee).filter(([id])=>mode==="employee"||allowed(id,managerPermission));
  const adminNav=admin.filter(([id])=>allowed(id,adminPermission));
  const initials=(access?.full_name||access?.email||"User").split(/[ .@]/).filter(Boolean).slice(0,2).map(x=>x[0]?.toUpperCase()).join("");
  const allMobileNav=mode==="management"?[...nav,...adminNav]:nav;
  if (!access) {
  return (
    <main className="auth-page">
      <section className="auth-page-card">
        <img src="/engagifii-logo.png" alt="Engagifii" />
        <h1>Compensation Tracker</h1>
        <p>Sign in with your Engagifii account to continue.</p>
        <SupabaseStatus />
      </section>
    </main>
  );
}
  return <main className="shell"><aside><button className="brand" onClick={()=>go("dashboard")}><img src="/engagifii-logo.png" alt="Engagifii"/><span><small>WORKSPACE</small><b>COMPENSATION</b></span></button><nav><p>{mode==="management"?"MANAGE":"MY COMPENSATION"}</p>{nav.map(([id,label,Icon])=><button key={id} className={screen===id?"active":""} onClick={()=>go(id)}><Icon/>{label}</button>)}{mode==="management"&&adminNav.length>0&&<><p>ADMIN</p>{adminNav.map(([id,label,Icon])=><button key={id} className={screen===id?"active":""} onClick={()=>go(id)}><Icon/>{label}</button>)}</>}</nav></aside>{mobileMenu&&<div className="mobile-menu-backdrop" onClick={()=>setMobileMenu(false)}><section className="mobile-menu" onClick={e=>e.stopPropagation()}><div className="mobile-menu-head"><img src="/engagifii-logo.png" alt="Engagifii"/><button onClick={()=>setMobileMenu(false)} aria-label="Close navigation"><X/></button></div><small>{mode==="management"?"MANAGEMENT WORKSPACE":"MY COMPENSATION"}</small>{hasManagementAccess&&hasEmployeeAccess&&<div className="mobile-mode workspace-mobile"><button className={workspace==="self"?"active":""} onClick={()=>chooseWorkspace("self")}>My</button><button className={workspace==="team"?"active":""} onClick={()=>chooseWorkspace("team")}>Team</button><button className={workspace==="administration"?"active":""} onClick={()=>chooseWorkspace("administration")}>Admin</button></div>}<nav>{allMobileNav.map(([id,label,Icon])=><button key={id} className={screen===id?"active":""} onClick={()=>go(id)}><Icon/>{label}</button>)}</nav></section></div>}<section className="work"><header><button className="mobile-menu-button" onClick={()=>setMobileMenu(true)} aria-label="Open navigation"><Menu/></button><div className="header-title"><b>{mode==="employee"&&screen==="dashboard"?"My Dashboard":titles[screen]}</b><small>{workspace==="self"?`${access?.full_name||"Employee"} · My workspace`:workspace==="team"?"Assigned team workspace":"Administration workspace"}</small></div><div className="header-actions"><SupabaseStatus/><div className="switch workspace-switch">{hasEmployeeAccess&&<button className={workspace==="self"?"selected":""} onClick={()=>chooseWorkspace("self")}>My dashboard</button>}{hasManagementAccess&&<button className={workspace==="team"?"selected":""} onClick={()=>chooseWorkspace("team")}>Team dashboard</button>}{isSystemAdmin&&<button className={workspace==="administration"?"selected":""} onClick={()=>chooseWorkspace("administration")}>Administration</button>}</div><span className="avatar">{initials||"—"}</span></div></header><div className="announcement"><span className="announcement-desktop">✦ Access is controlled by inherited roles, individual permission overrides, and assigned employee scope.</span><span className="announcement-mobile">✦ Secure, access-controlled workspace</span><button onClick={()=>go("settings")}>View access</button></div><div className="page">{render(screen,mode,period,setPeriod,go,toast,hubspot,refreshHubSpot,syncing,hubspotError,access)}</div></section>{notice&&<div className="notice">{notice}</div>}</main>
}

function SupabaseStatus() {
  const [state, setState] = useState<
    "checking" | "connected" | "restricted" | "error"
  >("checking");
  const [open, setOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);

  useEffect(() => {
    if (!supabase) {
      setState("error");
      return;
    }

    supabase.auth.getSession().then(({ data, error }) => {
      setState(error ? "error" : data.session ? "connected" : "restricted");
    });

    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setState(session ? "connected" : "restricted");
      if (session) setOpen(false);
    });

    return () => data.subscription.unsubscribe();
  }, []);

  const validateEmail = () => {
    if (!email.trim().toLowerCase().endsWith("@engagifii.com")) {
      setMessage("Use your Engagifii email address.");
      return false;
    }
    return true;
  };

  const signInWithGoogle = async () => {
    if (!supabase) {
      setMessage("The database connection is unavailable.");
      return;
    }

    setMessage("");
    setSending(true);

    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: window.location.origin,
        queryParams: {
          hd: "engagifii.com",
          prompt: "select_account",
        },
      },
    });

    if (error) {
      setMessage(error.message);
      setSending(false);
    }
  };

  const signInWithPassword = async () => {
    setMessage("");

    if (!validateEmail()) return;

    if (!password) {
      setMessage("Enter your password.");
      return;
    }

    if (!supabase) {
      setMessage("The database connection is unavailable.");
      return;
    }

    setSending(true);

    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });

    setMessage(error ? error.message : "");
    setSending(false);
  };

  const forgotPassword = async () => {
    setMessage("");

    if (!validateEmail()) return;

    if (!supabase) {
      setMessage("The database connection is unavailable.");
      return;
    }

    setSending(true);

    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: window.location.origin,
    });

    setMessage(
      error
        ? error.message
        : "Check your Engagifii inbox for a password reset link.",
    );

    setSending(false);
  };

  const signOut = async () => {
    if (supabase) await supabase.auth.signOut();
    setState("restricted");
  };

  const label =
    state === "checking"
      ? "Checking…"
      : state === "connected"
        ? "Signed in securely"
        : state === "restricted"
          ? "Sign in"
          : "Connection error";

  return (
    <>
      <button
        className={`db-status ${state}`}
        onClick={() => (state === "connected" ? signOut() : setOpen(true))}
        title={state === "connected" ? "Sign out" : "Sign in to compensation"}
      >
        {label}
      </button>

      {open && (
        <div className="auth-backdrop" onMouseDown={() => setOpen(false)}>
          <section
            className="auth-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="auth-title"
            onMouseDown={(e) => e.stopPropagation()}
          >
            <button
              className="auth-close"
              aria-label="Close"
              onClick={() => setOpen(false)}
            >
              ×
            </button>

            <ShieldCheck />
            <h2 id="auth-title">Sign in to compensation</h2>
            <p>Use your Engagifii account to access the compensation tracker.</p>

            <button
              className="primary auth-submit"
              onClick={signInWithGoogle}
              disabled={sending}
            >
              Continue with Google
            </button>

            <div className="auth-divider">
              <span>or</span>
            </div>

            <label>
              Engagifii email address
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
              />
            </label>

            <label>
              Password
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="current-password"
                onKeyDown={(e) => {
                  if (e.key === "Enter") signInWithPassword();
                }}
              />
            </label>

            <button
              className="primary auth-submit"
              onClick={signInWithPassword}
              disabled={sending}
            >
              {sending ? "Working…" : "Sign in"}
            </button>

            <button
              type="button"
              className="auth-forgot"
              onClick={forgotPassword}
              disabled={sending}
            >
              Forgot password?
            </button>

            {message && <div className="auth-message">{message}</div>}

            <small>
              Only authorized Engagifii users can access compensation data.
            </small>
          </section>
        </div>
      )}
    </>
  );
}

function render(s:Screen,m:Mode,p:string,setP:(x:string)=>void,go:(x:Screen)=>void,toast:(x:string)=>void,hubspot:HubSpotSummary,refreshHubSpot:()=>void,syncing:boolean,hubspotError:string,access:AccessSummary|null){if(s==="dashboard")return m==="management"?<Manager period={p} setPeriod={setP} go={go} toast={toast} hubspot={hubspot}/>:<Employee period={p} setPeriod={setP} go={go} access={access}/>;if(s==="approvals")return <Approvals employee={m==="employee"} go={go} toast={toast}/>;if(s==="employees")return m==="employee"?<Earnings go={go} toast={toast}/>:<Employees go={go}/>;if(s==="plans")return <Plans employee={m==="employee"} toast={toast}/>;if(s==="payments")return <Payments employee={m==="employee"} go={go} toast={toast}/>;if(s==="reconciliation")return <Reconcile toast={toast}/>;if(s==="hubspot")return <HubSpot toast={toast} data={hubspot} refresh={refreshHubSpot} syncing={syncing} error={hubspotError}/>;if(s==="rules")return <Rules/>;if(s==="settings")return <SettingsPage toast={toast} access={access}/>;if(s==="logs")return <Logs/>;return <Help/>}
function Head({title,copy,children}:{title:string;copy:string;children?:React.ReactNode}){return <div className="title"><div><h1>{title}</h1><p>{copy}</p></div>{children}</div>}
function Period({value,set}:{value:string;set:(x:string)=>void}){return <div className="seg">{["This month","Last month","YTD"].map(x=><button key={x} className={value===x?"selected":""} onClick={()=>set(x)}>{x}</button>)}</div>}
function Stat({label,value="—",note,blue=false}:{label:string;value?:string;note:string;blue?:boolean}){return <article className={`stat ${blue?"blue":""}`}><small>{label}</small><b>{value}</b><span>{note}</span></article>}
function Panel({title,copy,children,action}:{title:string;copy?:string;children:React.ReactNode;action?:React.ReactNode}){return <section className="card panel"><div className="panel-head"><div><h2>{title}</h2>{copy&&<p>{copy}</p>}</div>{action}</div>{children}</section>}
function Empty({icon,title,text,action,onClick}:{icon:React.ReactNode;title:string;text:string;action:string;onClick:()=>void}){return <div className="empty"><span>{icon}</span><div><b>{title}</b><small>{text}</small></div><button onClick={onClick}>{action}</button></div>}
function Warn({title,text}:{title:string;text:string}){return <div className="warning"><AlertTriangle/><div><b>{title}</b><small>{text}</small></div></div>}
function downloadFile(kind:"csv"|"xls"){const rows=[["Report","Variable Compensation Tracker"],["Generated",new Date().toLocaleString()],["Starting book","386674.25"],["Known expansion","22318.00"],["Known preliminary book","408992.25"],["Note","Live earnings and payments pending sync"]];const body=rows.map(r=>r.map(v=>`"${String(v).replaceAll('"','""')}"`).join(",")).join("\n");const a=document.createElement("a");a.href=URL.createObjectURL(new Blob([body],{type:kind==="csv"?"text/csv":"application/vnd.ms-excel"}));a.download=`engagifii-compensation-report.${kind}`;a.click();URL.revokeObjectURL(a.href)}
function Exports({toast}:{toast:(x:string)=>void}){return <div className="exports"><button onClick={()=>{downloadFile("csv");toast("CSV downloaded")}}><Download/>CSV</button><button onClick={()=>{downloadFile("xls");toast("Excel file downloaded")}}><Download/>XLS</button><button onClick={()=>{window.print();toast("Choose Save as PDF in the print dialog")}}><Download/>PDF</button></div>}
function Filters({toast,employee=false}:{toast:(x:string)=>void;employee?:boolean}){return <div className="filters"><label><Search/><input placeholder="Search deals, accounts, or line items"/></label><select><option>Year to date</option><option>This month</option><option>Last month</option><option>Custom range</option></select>{!employee&&<select><option>All employees</option><option>Wes Morris</option><option>Sharon Wells</option></select>}<select><option>All statuses</option><option>Earned</option><option>Eligible</option><option>Pending approval</option><option>Approved</option><option>Paid</option></select><button onClick={()=>toast("Filters applied")}><Filter/>Apply</button></div>}
function DataTable({type}:{type:"approvals"|"payments"|"book"}){const heads=type==="approvals"?["Select","Employee","Line item / source","Earned","Eligible","Approval status","Comments"]:type==="payments"?["Pay period","Employee","Deal / line item","Approved","Eligible","Paid","Payment status"]:["Account","Starting ARR","Current ARR","Revenue type","Renewal date","Deal owner","Company owner","CEM","Status"];return <div className={`rich-table ${type}`}>{heads.map(h=><b key={h}>{h}</b>)}<div className="table-empty"><span>No synchronized records match these filters.</span><small>The table is ready; HubSpot and historical data will populate it.</small></div></div>}
function Charts(){return <div className="charts"><article><div className="chart-title"><span><b>Revenue by type</b><small>Known 2026 data</small></span><em>$22.3K expansion</em></div><div className="bars">{[42,68,35,55,28,77,60,82].map((h,i)=><i key={i} style={{height:`${h}%`}}/>)}</div><div className="axis"><span>Jan</span><span>Mar</span><span>May</span><span>Jul</span></div></article><article><div className="chart-title"><span><b>Book of business</b><small>Starting vs known current</small></span><em>+5.8%</em></div><div className="progress-chart"><div><span>Starting</span><i><u style={{width:"55%"}}/></i><b>$386,674</b></div><div><span>Known current</span><i><u style={{width:"58%"}}/></i><b>$408,992</b></div><div><span>Target</span><i><u style={{width:"100%"}}/></i><b>$700,000</b></div></div></article></div>}
function Attainment(){return <div className="attainment"><article><div><b>Book target</b><small>Known current book / $700,000</small></div><strong>58.4%</strong><i><u style={{width:"58.4%"}}/></i><span>$291,008 remaining</span></article><article><div><b>Expansion earnings</b><small>Known $22,318 ARR · 10% plan rate</small></div><strong>$2,231.80</strong><i><u style={{width:"34%"}}/></i><span>Preview only · payment eligibility not verified</span></article></div>}

function ExecutiveSnapshot({hubspot}:{hubspot:HubSpotSummary}){const dealCount=hubspot.deals||562,companyCount=hubspot.companies||317;return <section className="executive-snapshot"><div className="snapshot-main"><div className="snapshot-kicker"><TrendingUp/>2026 COMPENSATION PULSE <em>Preliminary</em></div><div className="snapshot-total"><div><small>TOTAL EARNED</small><strong>$2,822.30</strong><span>Wes retention · 23 qualifying deals</span></div><div className="eligibility-ring" aria-label="15 of 23 earnings eligible"><div><b>65%</b><small>eligible</small></div></div></div><div className="snapshot-progress"><i><u style={{width:"65.2%"}}/></i><span><b>15</b> eligible for payment</span><span><b>8</b> waiting on paid condition</span></div></div><div className="snapshot-grid"><article className="money"><CircleDollarSign/><span><small>ELIGIBLE NOW</small><b>$1,799.40</b><em>15 earnings</em></span></article><article className="waiting"><Clock3/><span><small>EARNED · NOT ELIGIBLE</small><b>$1,022.90</b><em>8 earnings</em></span></article><article><BarChart3/><span><small>RENEWAL ARR</small><b>$141,115</b><em>qualifying source amount</em></span></article><article><ShieldCheck/><span><small>DATA COVERAGE</small><b>{dealCount.toLocaleString()} deals</b><em>{companyCount.toLocaleString()} companies</em></span></article></div></section>}

function AnalyticsGrid(){return <div className="analytics-grid"><article className="analytics-card"><div className="analytics-title"><span><b>Earning status</b><small>Wes retention · 23 deals</small></span><em>65% payable</em></div><div className="status-visual"><div className="status-donut"><span><b>23</b><small>earned</small></span></div><div className="status-legend"><p><i className="eligible"/><span>Eligible</span><b>15</b><em>$1,799</em></p><p><i className="pending"/><span>Waiting</span><b>8</b><em>$1,023</em></p></div></div></article><article className="analytics-card"><div className="analytics-title"><span><b>HubSpot portfolio</b><small>All synchronized deal years</small></span><em>562 deals</em></div><div className="pipeline-bars"><div><span>GovAffairs <b>325</b></span><i><u style={{width:"58%"}}/></i></div><div><span>MEams <b>237</b></span><i><u className="purple" style={{width:"42%"}}/></i></div></div><div className="pipeline-foot"><span>58% GovAffairs</span><span>42% MEams</span></div></article><article className="analytics-card book-visual"><div className="analytics-title"><span><b>Book attainment</b><small>Known current / year-end target</small></span><em>+5.8%</em></div><div className="book-ring"><div><b>58.4%</b><small>of target</small></div></div><div className="book-values"><span><small>Current</small><b>$408,992</b></span><span><small>Target</small><b>$700,000</b></span></div></article></div>}

function EmployeeAtAGlance(){return <><section className="employee-hero"><div><small>YOUR 2026 EARNINGS</small><strong>$2,822.30</strong><span>23 retention earnings</span><div className="employee-money-row"><p><b>$1,799.40</b><small>eligible now</small></p><p><b>$1,022.90</b><small>waiting on payment</small></p></div></div><div className="employee-pay-ring"><span><b>65%</b><small>payable</small></span></div></section><div className="employee-goals"><article className="goal-card"><div className="goal-head"><span><small>YEARLY BOOK TARGET</small><b>$408,992 <em>of $700,000</em></b></span><strong>58.4%</strong></div><div className="goal-track"><i style={{left:"55.2%"}}/><u style={{width:"58.4%"}}/><span style={{left:"58.4%"}}>You are here</span></div><div className="goal-scale"><span>$386,674 start</span><span>$291,008 to goal</span><span>$700K</span></div><div className="next-reward"><TrendingUp/><span><small>NEXT YEAR-END REWARD</small><b>$5,000 bonus at $700,000</b></span></div></article><article className="goal-card component-performance"><div className="goal-head"><span><small>EARNINGS BY COMPONENT</small><b>Retention leads YTD</b></span><strong>$2.8K</strong></div><div className="component-bar"><span>Retention commission <b>$2,822</b></span><i><u style={{width:"100%"}}/></i></div><div className="component-bar muted"><span>Expansion commission <b>Not calculated</b></span><i><u style={{width:"0%"}}/></i></div><div className="component-bar muted"><span>New sales commission <b>Not calculated</b></span><i><u style={{width:"0%"}}/></i></div></article><article className="goal-card tier-card"><div className="goal-head"><span><small>NEW SALES RATE TIERS</small><b>Your rate depends on contract term</b></span></div><div className="tier-steps"><div><small>1 year</small><b>8%</b></div><div><small>2–3 years</small><b>10%</b></div><div><small>4+ years</small><b>12%</b><em>TOP TIER</em></div></div><p>Each qualifying deal shows its achieved tier and the next available rate.</p></article></div></>}

function ComponentCard({item,compact=false}:{item:PlanComponent;compact?:boolean}){return <article className={`plan-component-card ${item.accent} ${compact?"compact":""}`}><div className="component-top"><span>{item.name}</span><strong>{item.rate}</strong></div><p>{item.description}</p><div className="formula"><small>HOW IT IS CALCULATED</small><b>{item.calculation}</b></div>{!compact&&<div className="component-rules"><div><small>WHAT COUNTS</small><span>{item.scope}</span></div><div><small>WHEN IT IS EARNED</small><span>{item.earned}</span></div><div><small>WHEN IT IS PAYABLE</small><span>{item.eligible}</span></div><div><small>EFFECTIVE</small><span>{item.effective}</span></div></div>}</article>}
function PlanComponentSections({items,compact=false}:{items:PlanComponent[];compact?:boolean}){return <div className={`plan-component-grid ${compact?"compact-grid":""}`}>{items.map(item=><ComponentCard key={item.name} item={item} compact={compact}/>)}</div>}
function DashboardPlanOverview({go}:{go:(x:Screen)=>void}){const[person,setPerson]=useState<"Wes"|"Sharon">("Wes");const items=person==="Wes"?wesComponents:sharonComponents;return <Panel title="Plan components" copy="Each component explains what counts, how it is calculated, and when it becomes payable." action={<div className="mini-switch"><button className={person==="Wes"?"active":""} onClick={()=>setPerson("Wes")}>Wes</button><button className={person==="Sharon"?"active":""} onClick={()=>setPerson("Sharon")}>Sharon</button></div>}><PlanComponentSections items={items} compact/><button className="text-link" onClick={()=>go("plans")}>Open full plan details <ChevronRight/></button></Panel>}

function Manager({period,setPeriod,go,toast,hubspot}:{period:string;setPeriod:(x:string)=>void;go:(x:Screen)=>void;toast:(x:string)=>void;hubspot:HubSpotSummary}){const connected=hubspot.deals>0;return <><Head title="Compensation intelligence" copy="Earnings, payment readiness, plan performance, and data quality at a glance."><div className="head-actions"><Period value={period} set={setPeriod}/><Exports toast={toast}/></div></Head><ExecutiveSnapshot hubspot={hubspot}/><Filters toast={toast}/><section className="card priority"><div><span><ShieldCheck/></span><div><small>YOUR APPROVAL QUEUE</small><h2>No employee submissions yet</h2><p>23 calculated earnings are ready for employee verification; 15 currently meet the payment condition.</p></div></div><button className="primary" onClick={()=>go("approvals")}>Open approvals <ChevronRight/></button></section><AnalyticsGrid/><div className="two"><Panel title="Employee earnings" copy={`Earned versus eligible · ${period}`} action={<button onClick={()=>go("employees")}>View employees</button>}><div className="employee-row"><span className="initials">WM</span><div><b>Wes Morris</b><small>Customer Experience Manager</small></div><div><small>Earned</small><b>$2,822.30</b></div><div><small>Eligible</small><b>$1,799.40</b></div><em>23 earnings</em></div><div className="employee-row"><span className="initials">SW</span><div><b>Sharon Wells</b><small>Revenue operations overlay</small></div><div><small>Earned</small><b>—</b></div><div><small>Eligible</small><b>—</b></div><em>Plan designed</em></div></Panel><Panel title="Flags & warnings" copy="Items that may affect accuracy" action={<button onClick={()=>go("reconciliation")}>Review all</button>}>{connected?<Warn title={`${hubspot.unreviewedChanges} HubSpot change${hubspot.unreviewedChanges===1?"":"s"} need review`} text={`${hubspot.deals.toLocaleString()} deals and ${hubspot.companies.toLocaleString()} companies are synchronized.`}/>:<Warn title="Live refresh requires sign-in" text="Showing the latest validated compensation snapshot."/>}<Warn title="Historical payments not imported" text="Prior paid and unpaid earnings could be duplicated."/><Warn title="Renewal payment hold needs status" text="Sharon’s historical renewal override is tracked separately until management releases the hold."/></Panel></div><DashboardPlanOverview go={go}/><Book/><Panel title="Book of business accounts" copy="Starting ARR, current ARR, revenue movement, ownership, renewal timing, and status"><DataTable type="book"/></Panel><section className="card ai"><Bot/><div><h2>Ask your compensation data</h2><p>Once calculations are active, ask “Which renewals don’t match last year?” or “Why isn’t this earning eligible?”</p></div><button onClick={()=>go("hubspot")}>Review source data</button></section></>}
function Employee({
  period,
  setPeriod,
  go,
  access
}:{
  period:string;
  setPeriod:(x:string)=>void;
  go:(x:Screen)=>void;
  access:AccessSummary|null;
}){
  const isSharon=access?.email?.toLowerCase()==="sharonwells@engagifii.com";
  const employeeName=access?.full_name||access?.email||"Employee";
  const planItems=isSharon?sharonComponents:wesComponents;

  return <>
    <Head
      title="My compensation"
      copy={`${employeeName} · 2026 plan year`}
    >
      <Period value={period} set={setPeriod}/>
    </Head>

    {isSharon ? (
      <>
        <div className="stats">
          <Stat label="Earned" note="Calculation pending"/>
          <Stat label="Eligible" note="Calculation pending"/>
          <Stat label="Approved" note="No submissions"/>
          <Stat label="Paid" note="History not imported"/>
        </div>

        <Panel
          title="My compensation plan"
          copy="Your assigned compensation components and effective rules."
        >
          <PlanComponentSections items={planItems} compact/>
          <button className="text-link" onClick={()=>go("plans")}>
            See full component rules <ChevronRight/>
          </button>
        </Panel>

        <Panel
          title="My earnings"
          copy="Your calculated earnings will appear here once live calculations are activated."
        >
          <Empty
            icon={<BarChart3/>}
            title="No earnings calculated yet"
            text="Your employee profile is connected. Earnings still need to be calculated from the configured compensation rules."
            action="View my plan"
            onClick={()=>go("plans")}
          />
        </Panel>
      </>
    ) : (
      <>
        <EmployeeAtAGlance/>
        <section className="card employee-action">
          <div>
            <ShieldCheck/>
            <span>
              <small>READY FOR YOUR REVIEW</small>
              <b>23 earnings calculated</b>
              <p>Verify the source deals before submitting them for management approval.</p>
            </span>
          </div>
          <button className="primary" onClick={()=>go("approvals")}>
            Review earnings <ChevronRight/>
          </button>
        </section>

        <Panel
          title="How my plan works"
          copy="Each plan component is calculated independently."
        >
          <PlanComponentSections items={planItems} compact/>
        </Panel>
      </>
    )}
  </>
}
function Book(){return <Panel title="Company performance" copy="Book of business, revenue type, ownership, and renewal status"><div className="book"><div><small>2026 starting book</small><b>$386,674.25</b><span>64 companies</span></div><div><small>Known expansion</small><b>$22,318.00</b><span>Maryland Hospital + Pepco</span></div><div><small>Year-end threshold</small><b>$700,000.00</b><span>Wes’s $5,000 bonus</span></div><div><small>Renewal validation</small><b>Pending sync</b><span>Flag mismatches</span></div></div></Panel>}
function Employees({go}:{go:(x:Screen)=>void}){return <><Head title="Employees" copy="People, roles, assigned plan versions, and calculation readiness."><button className="primary" onClick={()=>go("plans")}>Add employee</button></Head><Panel title="Configured employees" copy="Multiple roles, effective-dated plan versions, and component-level rules are supported"><div className="table-head"><span>Employee</span><span>Roles</span><span>Plan</span><span>Status</span></div><div className="table-row"><div><span className="initials">WM</span><p><b>Wes Morris</b><small>wesmorris@engagifii.com</small></p></div><span>Customer Experience Manager</span><span>4 components · 2026</span><em>Configured</em></div><div className="table-row"><div><span className="initials">SW</span><p><b>Sharon Wells</b><small>Revenue operations overlay</small></p></div><span>Company-wide revenue override</span><span>7 effective-dated components</span><em>Plan designed</em></div><Empty icon={<Users/>} title="Two employee plans configured" text="Every component retains its own source, owner, stage, earning, eligibility, and approval rules." action="Review plans" onClick={()=>go("plans")}/></Panel><Book/></>}
function MissingDealClaim({toast}:{toast:(x:string)=>void}){const[dealId,setDealId]=useState(""),[explanation,setExplanation]=useState(""),[sending,setSending]=useState(false),[message,setMessage]=useState("");const submit=async()=>{if(!supabase)return toast("Database connection is unavailable");if(!/^\d+$/.test(dealId.trim()))return setMessage("Enter the numeric HubSpot deal ID.");if(explanation.trim().length<10)return setMessage("Please add a short explanation of why the deal should count.");setSending(true);setMessage("");const{data,error}=await supabase.rpc("submit_missing_earning_claim",{submitted_hubspot_deal_id:dealId.trim(),submitted_explanation:explanation.trim(),submitted_plan_component_id:null});if(error)setMessage(error.message);else{setDealId("");setExplanation("");setMessage(`Claim submitted for deal ${data?.hubspot_deal_id||dealId}. Your assigned approver will review it.`);toast("Missing earning claim submitted")};setSending(false)};return <Panel title="Missing a deal?" copy="Submit a HubSpot deal you believe should count. This creates a review request—it does not add an earning automatically."><div className="claim-form"><label><span>HubSpot deal ID</span><input inputMode="numeric" value={dealId} onChange={e=>setDealId(e.target.value)} placeholder="Example: 31248163753"/></label><label><span>Why should this deal be earned?</span><textarea value={explanation} onChange={e=>setExplanation(e.target.value)} placeholder="Explain the deal type, your role, and why it matches your plan." rows={4}/></label><button className="primary" onClick={submit} disabled={sending}><MessageSquare/>{sending?"Submitting…":"Submit for review"}</button>{message&&<div className="claim-message">{message}</div>}<small>Your management approver can approve, deny, or return the request for more information. Every decision is retained in the audit history.</small></div></Panel>}
function Earnings({go,toast}:{go:(x:Screen)=>void;toast:(x:string)=>void}){return <><Head title="My earnings" copy="Deal-level earnings, eligibility, approval, and payment status by plan component."/><div className="stats"><Stat label="Earned" note="Not calculated"/><Stat label="Eligible" note="Not calculated"/><Stat label="Approved" note="No submissions"/><Stat label="Paid" note="History not imported"/></div><DashboardPlanOverview go={go}/><Panel title="Earning details by component" copy="Each section will show its HubSpot source, formula, effective rule, status, and explanation"><Empty icon={<BarChart3/>} title="No earnings calculated" text="The component structure is ready; calculation activation and historical reconciliation come next." action="View my plan" onClick={()=>go("plans")}/></Panel><MissingDealClaim toast={toast}/></>}
function Plans({employee,toast}:{employee:boolean;toast:(x:string)=>void}){const[selected,setSelected]=useState<"Wes"|"Sharon">("Wes");const items=selected==="Wes"?wesComponents:sharonComponents;return <><Head title={employee?"My compensation plan":"Compensation plans"} copy={employee?"Every component explains what counts, the formula, and when it becomes payable.":"Configure and version each component independently without changing historical calculations."}>{!employee&&<div className="plan-actions"><button onClick={()=>toast("Plan component editor opened")}><Pencil/> Edit components</button><button onClick={()=>toast("Plan assignments opened")}><Users/> Applied to</button></div>}</Head>{!employee&&<div className="plan-person-tabs"><button className={selected==="Wes"?"active":""} onClick={()=>setSelected("Wes")}><span>WM</span><b>Wes Morris</b><small>4 components</small></button><button className={selected==="Sharon"?"active":""} onClick={()=>setSelected("Sharon")}><span>SW</span><b>Sharon Wells</b><small>7 components</small></button></div>}<section className="plan-intro"><div><small>{selected.toUpperCase()}’S PLAN</small><h2>{selected==="Wes"?"Customer Experience Manager Incentive Plan":"Revenue Operations Override & Bonus Plan"}</h2><p>{selected==="Wes"?"Effective from December 12, 2025. Deal-based earnings use component-selected pipelines, types, stages, amounts, and credit rules.":"Historical rules effective from April 1, 2023 with rate changes preserved by date. Base salary is excluded from variable compensation."}</p></div><em>{selected==="Wes"?"Draft · 2026":"Effective-dated · historical"}</em></section><PlanComponentSections items={items}/>{selected==="Sharon"&&<div className="plan-note"><AlertTriangle/><span><b>Renewal payment hold needs confirmation</b><small>Renewal earnings beginning August 1, 2024 can be calculated and shown as eligible while payment remains held until management releases the hold.</small></span></div>}</>}
function Approvals({employee,go,toast}:{employee:boolean;go:(x:Screen)=>void;toast:(x:string)=>void}){const[comment,setComment]=useState("");return <><Head title={employee?"Submit for approval":"Approvals"} copy={employee?"Verify line items by plan component, add comments, and submit selected earnings.":"Approve by employee and plan component, return with comments, and track every approval step."}><Exports toast={toast}/></Head><Filters toast={toast} employee={employee}/><DashboardPlanOverview go={go}/><div className="tabs"><button className="active">{employee?"Ready to submit":"My queue"} <b>0</b></button><button>{employee?"Submitted":"Waiting on others"} <b>0</b></button><button>Approved</button><button>Returned</button><button>All activity</button></div><Panel title="Approval line items by component" copy="Every row will include the component description, source facts, formula, effective rule, and comments"><div className="bulk"><label><input type="checkbox"/> Select all visible</label><button disabled>{employee?"Submit selected":"Approve selected"}</button><button disabled>{employee?"Remove":"Return selected"}</button></div><DataTable type="approvals"/><div className="comment-box"><MessageSquare/><textarea value={comment} onChange={e=>setComment(e.target.value)} placeholder="Add a comment to the selected line item or submission…"/><button onClick={()=>{if(comment.trim()){toast("Comment saved to the activity history");setComment("")}else toast("Enter a comment first")}}>Add comment</button></div></Panel><Panel title="Workflow" copy="Approval and payment eligibility remain independent"><div className="flow"><b>Employee verifies</b><ChevronRight/><b>Manager approves</b><ChevronRight/><b>Executive if required</b><ChevronRight/><b>Payroll pays eligible items</b></div></Panel></>}
function Payments({employee,go,toast}:{employee:boolean;go:(x:Screen)=>void;toast:(x:string)=>void}){return <><Head title={employee?"Payments & statements":"Payments"} copy={employee?"See what was paid, when, and which plan component produced it.":"Analyze and reconcile payments by period, employee, deal, component, and status."}><Exports toast={toast}/></Head><Filters toast={toast} employee={employee}/><div className="stats"><Stat label="Approved & eligible" note="No live calculations"/><Stat label="Approved, not eligible" note="Held for payment condition"/><Stat label="Scheduled" value="0" note="No open pay run"/><Stat label="Paid" note="History not imported"/></div><DashboardPlanOverview go={go}/><Panel title="Payment detail by component" copy="Pay period, component, source, approval, eligibility, scheduled date, paid date, and payroll reference"><DataTable type="payments"/><Empty icon={<WalletCards/>} title="No payments loaded" text="Historical payments must be imported before live payroll to prevent duplicate payments." action={employee?"View my earnings":"Open reconciliation"} onClick={()=>go(employee?"employees":"reconciliation")}/></Panel></>}
function Reconcile({toast}:{toast:(x:string)=>void}){return <><Head title="Historical reconciliation" copy="Match prior earnings to paid, still owed, or intended pay periods."><Exports toast={toast}/></Head><Filters toast={toast}/><Panel title="Import checklist" copy="Required before the first live pay run">{["Import 2025 and 2026 employee earning spreadsheets","Record paid status, dates, and pay periods","Flag approved earnings still waiting for customer payment","Reconcile QDCs, tiers, partial payments, advances, and clawbacks"].map(x=><Check key={x} text={x}/>)}</Panel></>}
function HubSpot({data,refresh,syncing,error}:{toast:(x:string)=>void;data:HubSpotSummary;refresh:()=>void;syncing:boolean;error:string}){const connected=data.deals>0;return <><Head title="HubSpot integration" copy="Source of truth for deals, companies, ownership, revenue, stages, and payment dates."/><section className={`card connection ${connected?"connected":""}`}><span>H</span><div><small>CONNECTION STATUS</small><h2>{connected?"Connected and synchronized":"Connected · sign in to view data"}</h2><p>{connected?`${data.deals.toLocaleString()} deals · ${data.companies.toLocaleString()} companies · ${data.associations.toLocaleString()} deal/company links`:"The service connection is complete; live counts are limited to authorized users."}</p></div><button className="primary" onClick={refresh} disabled={syncing}>{syncing?"Refreshing…":"Refresh HubSpot"}</button></section><div className="sync-stats"><Stat label="Deals synchronized" value={connected?data.deals.toLocaleString():"—"} note="GovAffairs and MEams · all available years"/><Stat label="Companies synchronized" value={connected?data.companies.toLocaleString():"—"} note="Associated company records"/><Stat label="Unlinked deals" value={connected?data.unlinkedDeals.toLocaleString():"—"} note="Require review before compensation"/><Stat label="Changes to review" value={connected?data.unreviewedChanges.toLocaleString():"—"} note={data.lastSync?`Last refresh ${new Date(data.lastSync).toLocaleString()}`:"Sign in to view refresh history"}/></div><div className="two"><Panel title="Data synchronized" copy="Read-only source data during validation">{["Deals: pipeline, type, stage, owner, ARR, term and payment fields","Companies: customer since, owner, CEM and account status","Payment: Closed Won [Paid] plus Invoice Paid Date","Deal/company associations and change history"].map(x=><Check key={x} done={connected} text={x}/>)}</Panel><Panel title="Automatic warnings"><Warn title="Stage/date mismatch" text="Paid stage and invoice paid date must agree."/><Warn title="Renewal mismatch" text="Compare prior-year revenue to the next renewal."/><Warn title="Missing contract grouping" text="Link annual deals for multi-year contracts in this app."/><Warn title="Ownership ambiguity" text="Flag unclear credit rather than guessing."/></Panel></div>{error&&error!=="Sign in required"&&<div className="sync-error"><AlertTriangle/><div><b>Dashboard data could not load</b><span>{error}</span></div></div>}{data.recentChanges.length>0&&<Panel title="Recent HubSpot changes" copy="Changes are retained for audit and reviewed before they alter compensation"><div className="change-list">{data.recentChanges.map((x,i)=><div className="change-row" key={`${x.detected_at}-${i}`}><span>{new Date(x.detected_at).toLocaleString()}</span><b>{x.deal_name}</b><span>{x.field_name}</span><small>{x.old_value||"—"} → {x.new_value||"—"}</small><em>{x.review_status}</em></div>)}</div></Panel>}</>}
function Rules(){return <><Head title="Rules & calculations" copy="Auditable plan logic turns HubSpot and meeting facts into component-level earnings."/><Panel title="Calculation sequence" copy="Every result retains source inputs, the effective rule version, and before/after history"><div className="rule-grid">{[["1","Match a component","Pipeline, deal type, stage, meeting type, and effective date"],["2","Assign credit","Any owner, selected owners, employee is owner, or employee is not owner"],["3","Calculate the amount","Average ARR, Deal Amount, meeting count, tier, or cumulative milestone"],["4","Move through status","Earned, eligible, approval, payment, removal, or clawback"]].map(([n,a,b])=><div key={n}><span>{n}</span><b>{a}</b><small>{b}</small></div>)}</div></Panel><div className="two"><Panel title="Owner and scope controls" copy="Configured separately for every plan component">{["Any owner or selected owner(s)","Employee is the deal owner","Employee is not the deal owner","Any pipeline or selected pipeline(s)","Selected deal types and stages"].map(x=><Check key={x} text={x} done/>)}</Panel><Panel title="Refresh safeguards" copy="A refresh never erases compensation history">{["Recalculate when a source field changes","Remove from current earned when a deal stops qualifying","Log the prior and new state","Require review before reversing approved or paid earnings","Create a clawback when recovery is required"].map(x=><Check key={x} text={x} done/>)}</Panel></div></>}
type NotificationPreference={notification_type:string;display_name:string;description:string;in_app_enabled:boolean;email_delivery:"off"|"immediate"|"daily"|"weekly";is_user_override:boolean};
function NotificationSettings({toast}:{toast:(x:string)=>void}){const[preferences,setPreferences]=useState<NotificationPreference[]>([]),[loading,setLoading]=useState(true);useEffect(()=>{if(!supabase){setLoading(false);return}supabase.rpc("get_my_notification_preferences").then(({data})=>{setPreferences((data||[]) as NotificationPreference[]);setLoading(false)})},[]);const update=async(item:NotificationPreference,patch:Partial<NotificationPreference>)=>{const next={...item,...patch};setPreferences(rows=>rows.map(row=>row.notification_type===item.notification_type?next:row));if(!supabase)return;const{error}=await supabase.rpc("set_my_notification_preference",{selected_notification_type:item.notification_type,enable_in_app:next.in_app_enabled,selected_email_delivery:next.email_delivery});if(error)toast(error.message);else toast("Notification preference saved")};if(loading)return <p className="settings-note">Loading notification preferences…</p>;return <div className="notification-settings">{preferences.map(item=><div className="notification-setting" key={item.notification_type}><label><input type="checkbox" checked={item.in_app_enabled} onChange={e=>update(item,{in_app_enabled:e.target.checked})}/><span><b>{item.display_name}</b><small>{item.description}</small></span></label><select value={item.email_delivery} onChange={e=>update(item,{email_delivery:e.target.value as NotificationPreference["email_delivery"]})}><option value="off">No email</option><option value="immediate">Email immediately</option><option value="daily">Daily summary</option><option value="weekly">Weekly summary</option></select></div>)}</div>}
function SettingsPage({toast,access}:{toast:(x:string)=>void;access:AccessSummary|null}){const roles=access?.roles||[];const isAdmin=roles.includes("system_administrator");return <><Head title="Settings" copy="Role defaults provide the starting point. Authorized administrators can grant or deny individual permissions per user."/>{isAdmin&&<UserAdministration toast={toast}/>}<section className="settings-summary"><div><small>YOUR ROLES</small><b>{roles.length?roles.map(role=>role.replaceAll("_"," ")).join(" · "):"Sign in required"}</b></div><div><small>EFFECTIVE PERMISSIONS</small><b>{access?.permissions?.length||0}</b></div><div><small>ACCOUNT STATUS</small><b>{access?.is_active===false?"Deactivated":"Active"}</b></div></section><div className="two"><Panel title="Access model" copy="Inherited role defaults plus explicit user-level grants or denials"><Setting a="Account activation" b="Administrator invitation only"/><Setting a="Manager visibility" b="Assigned per employee and action"/><Setting a="Multiple roles" b="Supported"/><Setting a="Deactivation" b="Immediate; history preserved"/></Panel><Panel title="Organization controls" copy="Only system administrators can change these settings"><Setting a="Localization" b="Time zone and currency"/><Setting a="Plan calendar" b="Plan and calendar years"/><Setting a="Payroll" b="Periods and payment dates"/><Setting a="Workflow" b="Deadlines and escalation"/><Setting a="Integration" b="HubSpot refresh schedule"/><Setting a="Governance" b="Domains, retention, and audit rules"/></Panel></div><Panel title="Roles and responsibilities" copy="Each role supplies defaults; individual permissions may be changed without editing the role"><div className="role-grid">{[["System administrator","Full data, security, settings, and audit access"],["Management approver","Assigned employees; approvals, exceptions, flags, and adjustments"],["Finance or payroll","Payable earnings, scheduling, exports, holds, and payment corrections"],["Plan administrator","Drafts and edits plans; activation still requires approval and acknowledgment"],["Employee","Own plan, earnings, submissions, disputes, statements, and preferences"],["Auditor or read-only","Only assigned employees or plans; no changes"]].map(([name,copy])=><article key={name}><ShieldCheck/><div><b>{name}</b><small>{copy}</small></div></article>)}</div></Panel><Panel title="My notifications" copy="Role defaults are inherited. Your selections below override them for your account."><NotificationSettings toast={toast}/></Panel><Panel title="Settings ownership" copy="Personal preferences are editable by the user; security and company rules require administration"><div className="setting-ownership"><div><b>User-editable</b><span>Notification delivery, display time zone, date format, dashboard period, and digest timing</span></div><div><b>Administrator-only</b><span>Roles, permission overrides, employee scope, approval chains, active status, company calendars, payroll, domains, and retention</span></div></div></Panel></>}

type DraftPreview={draft_user?:{id?:string;email?:string;full_name?:string;status?:string};roles?:Array<{role_key?:string;name?:string}|string>;permissions?:Array<{permission_key?:string;allowed?:boolean}|string>;workspaces?:Array<{workspace_key?:string;label?:string}|string>};
const roleChoices=[["employee","Employee"],["management_approver","Management approver"],["finance_payroll","Finance or payroll"],["plan_administrator","Plan administrator"],["auditor_read_only","Auditor or read-only"],["system_administrator","System administrator"]] as const;
function UserAdministration({toast}:{toast:(x:string)=>void}){const[email,setEmail]=useState(""),[name,setName]=useState(""),[selectedRoles,setSelectedRoles]=useState<string[]>(["employee"]),[draftId,setDraftId]=useState(""),[preview,setPreview]=useState<DraftPreview|null>(null),[busy,setBusy]=useState(false),[showPreview,setShowPreview]=useState(false);const toggleRole=(key:string)=>setSelectedRoles(current=>current.includes(key)?current.filter(x=>x!==key):[...current,key]);const createDraft=async()=>{if(!email||!name)return toast("Enter the user’s name and email");if(!email.toLowerCase().endsWith("@engagifii.com"))return toast("Use an Engagifii email address");if(!supabase)return toast("Database connection unavailable");setBusy(true);const{data,error}=await supabase.rpc("create_app_user_draft",{selected_email:email,selected_full_name:name,selected_employee_id:null,selected_role_keys:selectedRoles,selected_notes:"Created in user administration"});if(error)toast(error.message);else{const raw:any=data;const id=typeof raw==="string"?raw:raw?.draft_user_id||raw?.id;setDraftId(id||"");toast("User draft created — no invitation sent")};setBusy(false)};const loadPreview=async()=>{if(!draftId||!supabase)return;setBusy(true);const{data,error}=await supabase.rpc("get_app_user_draft_preview",{selected_draft_user_id:draftId});if(error)toast(error.message);else{setPreview(data as DraftPreview);setShowPreview(true)}setBusy(false)};const copySharon=async()=>{if(!draftId||!supabase)return toast("Create the draft first");setBusy(true);const{error}=await supabase.rpc("copy_user_access_to_draft",{source_user_id:"7fd6fdae-efbd-4d3f-b52b-62d30216ff55",selected_draft_user_id:draftId});if(error)toast(error.message);else toast("Sharon’s access copied to the draft");setBusy(false)};const prepare=async()=>{if(!draftId||!supabase)return toast("Create the draft first");setBusy(true);const{error}=await supabase.rpc("prepare_app_user_draft_invitation",{selected_draft_user_id:draftId});if(error)toast(error.message);else toast("Invitation prepared but not sent");setBusy(false)};return <section className="card user-admin"><div className="user-admin-head"><div><small>USER ADMINISTRATION</small><h2>Create and configure access before inviting</h2><p>Build the account, review exactly what the person will see, and send the invitation only when you are ready.</p></div><span><ShieldCheck/>Invitation-only access</span></div><div className="user-builder"><div className="user-form"><label>Full name<input value={name} onChange={e=>setName(e.target.value)} placeholder="Employee name"/></label><label>Engagifii email<input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="name@engagifii.com"/></label><fieldset><legend>Roles <em>Choose one or more</em></legend><div className="role-options">{roleChoices.map(([key,label])=><label key={key} className={selectedRoles.includes(key)?"checked":""}><input type="checkbox" checked={selectedRoles.includes(key)} onChange={()=>toggleRole(key)}/><span>{selectedRoles.includes(key)?<CheckCircle2/>:null}{label}</span></label>)}</div></fieldset><div className="user-actions"><button className="primary" disabled={busy} onClick={createDraft}><UserPlus/>{draftId?"Update draft":"Create user draft"}</button>{draftId&&<><button className="secondary" disabled={busy} onClick={loadPreview}><Eye/>Preview as user</button><button className="secondary" disabled={busy} onClick={copySharon}><Copy/>Copy Sharon’s access</button><button className="invite-prepare" disabled={busy} onClick={prepare}><Send/>Prepare invitation</button></>}</div>{draftId&&<p className="draft-safe"><ShieldCheck/>Draft saved. The person cannot sign in and no email has been sent.</p>}</div><aside className="access-explainer"><b>Access is built in layers</b><ol><li><span>1</span><div><strong>Role defaults</strong><small>Start with the normal permissions for each role.</small></div></li><li><span>2</span><div><strong>Specific access</strong><small>Grant employee, plan, or action access separately.</small></div></li><li><span>3</span><div><strong>User overrides</strong><small>An explicit grant or denial wins over the role default.</small></div></li></ol><div><small>WORKSPACES</small><p>People with their own plan and management duties can switch among My dashboard, Team dashboard, and Administration.</p></div></aside></div>{showPreview&&<div className="preview-backdrop" onMouseDown={()=>setShowPreview(false)}><section className="user-preview" onMouseDown={e=>e.stopPropagation()}><div className="preview-head"><div><small>READ-ONLY PREVIEW</small><h2>{preview?.draft_user?.full_name||name}</h2><p>{preview?.draft_user?.email||email}</p></div><button onClick={()=>setShowPreview(false)} aria-label="Close preview"><X/></button></div><div className="preview-banner"><Eye/><span><b>You are viewing their access, not acting as them.</b><small>Nothing in this preview can approve, edit, submit, or pay.</small></span></div><div className="preview-workspaces">{(preview?.workspaces||["My dashboard",...(selectedRoles.some(x=>x!=="employee")?["Team dashboard"]:[]),...(selectedRoles.includes("system_administrator")?["Administration"]:[])]).map((item:any)=><span key={typeof item==="string"?item:item.workspace_key}>{typeof item==="string"?item:item.label||item.workspace_key}</span>)}</div><h3>Assigned roles</h3><div className="preview-roles">{(preview?.roles||selectedRoles).map((item:any)=><span key={typeof item==="string"?item:item.role_key}>{(typeof item==="string"?item:item.name||item.role_key).replaceAll("_"," ")}</span>)}</div><button className="primary" onClick={()=>setShowPreview(false)}>Close preview</button></section></div>}</section>}
function Logs(){return <><Head title="Activity log" copy="A searchable, exportable audit trail of plan, calculation, approval, removal, override, clawback, and payment activity."/><Panel title="Lifecycle events" copy="Refreshes preserve the previous state before changing an earning"><div className="table-head logs"><span>Date & time</span><span>Source</span><span>Action</span><span>Record</span><span>Before / after</span></div>{["Sharon’s effective-dated plan designed","MHA credit mismatch approved for Wes","All GovAffairs and MEams stages synchronized","Earning lifecycle logging enabled"].map((x,i)=><div className="log-row" key={x}><span>Aug 28, 2026</span><span>{i===1?"Management":"System setup"}</span><b>{x}</b><span>{i===1?"Deal review":"Configuration"}</span><button>View detail</button></div>)}</Panel><Panel title="Events captured automatically" copy="These event types will appear when the calculation engine is activated"><div className="event-chips">{["Earning created","Became eligible","Removed from earned","Reinstated","Amount changed","Credit mismatch","Reversal required","Clawback required"].map(x=><span key={x}>{x}</span>)}</div></Panel></>}
function Help(){return <><Head title="Help & implementation checklist" copy="What remains before employee access is enabled."/><Panel title="Readiness">{[[true,"Supabase project and compensation schema created"],[true,"Wes’s signed plan configured"],[true,"Preliminary 2026 book reconstructed"],[false,"Connect HubSpot and validate internal property names"],[false,"Confirm account-level baseline"],[false,"Import historical earnings and payroll"],[false,"Configure every other employee’s signed plan"],[false,"Set up authentication and permissions"],[false,"Validate calculations before launch"]].map(([d,t])=><Check key={String(t)} done={Boolean(d)} text={String(t)}/>)}</Panel></>}
function Check({text,done=false}:{text:string;done?:boolean}){return <div className={`check ${done?"done":""}`}><span>{done?"✓":""}</span><p>{text}</p></div>}
function Setting({a,b}:{a:string;b:string}){return <div className="setting"><span>{a}</span><b>{b}</b></div>}
