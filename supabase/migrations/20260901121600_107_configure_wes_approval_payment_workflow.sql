do $$
declare wes_id uuid; sharon_employee uuid; sharon_user uuid; scott_id uuid; namit_id uuid; workflow_id uuid; existing_id uuid;
begin
 select id into wes_id from public.employees where lower(email)='wesmorris@engagifii.com';
 select e.id,p.id into sharon_employee,sharon_user from public.employees e join public.profiles p on p.employee_id=e.id and p.is_active=true where lower(e.email)='sharonwells@engagifii.com';
 select id into scott_id from public.employees where lower(email)='scottkey@engagifii.com';
 select id into namit_id from public.employees where lower(email)='namitbhatia@engagifii.com';
 if wes_id is null or sharon_user is null or scott_id is null or namit_id is null then raise exception 'Required Wes workflow participants are missing.'; end if;
 select id into existing_id from public.employee_approval_workflow_versions where employee_id=wes_id and status in ('draft','active') order by effective_start_date desc limit 1;
 if existing_id is not null then return; end if;
 insert into public.employee_approval_workflow_versions(employee_id,workflow_name,effective_start_date,effective_end_date,status,notes,created_by)
 values(wes_id,'Wes Morris Approval & Payment Workflow — 2026','2025-12-12','2026-12-31','draft','Wes submits; Sharon validates data and amount; after Sharon approval Scott receives required finance acknowledgement/payment-info task and Namit receives optional executive review. All stage recipients are notified.',sharon_user)
 returning id into workflow_id;
 insert into public.employee_approval_chains(employee_id,workflow_version_id,approval_order,step_name,approver_employee_id,approver_user_id,approval_level,is_required,effective_start_date,effective_end_date,conditions,created_by)
 values(wes_id,workflow_id,1,'Data & Amount Approval',sharon_employee,sharon_user,'manager',true,'2025-12-12','2026-12-31','{}'::jsonb,sharon_user);
 insert into public.employee_post_approval_steps(workflow_version_id,employee_id,stage_order,step_name,step_type,assignee_employee_id,assignee_user_id,is_required_for_payment,requires_payment_details,effective_start_date,effective_end_date,created_by)
 values
 (workflow_id,wes_id,2,'Finance Receipt & Payment Information','finance_acknowledgement',scott_id,null,true,true,'2025-12-12','2026-12-31',sharon_user),
 (workflow_id,wes_id,2,'Optional Executive Review','optional_executive_review',namit_id,null,false,false,'2025-12-12','2026-12-31',sharon_user);
end$$;
