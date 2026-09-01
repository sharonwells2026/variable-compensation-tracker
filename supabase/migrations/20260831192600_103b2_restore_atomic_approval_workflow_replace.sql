create or replace function public.replace_employee_approval_workflow(selected_current_workflow_version_id uuid,selected_workflow_name text,selected_effective_start_date date,selected_effective_end_date date,selected_steps jsonb,selected_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare current_row public.employee_approval_workflow_versions%rowtype; end_result jsonb; create_result jsonb;
begin
 if not private.has_permission('users.manage') then raise exception 'Workflow administration is not permitted.' using errcode='42501'; end if;
 select * into current_row from public.employee_approval_workflow_versions where id=selected_current_workflow_version_id for update;
 if current_row.id is null then raise exception 'Current workflow version was not found.'; end if;
 if current_row.status<>'active' then raise exception 'Only an active workflow can be replaced.'; end if;
 if selected_effective_start_date is null or selected_effective_start_date<=current_row.effective_start_date then raise exception 'Replacement workflow must start after the current workflow start date.'; end if;
 end_result:=public.end_employee_approval_workflow(current_row.id,selected_effective_start_date-1);
 create_result:=public.create_employee_approval_workflow(current_row.employee_id,selected_workflow_name,selected_effective_start_date,selected_effective_end_date,selected_steps,selected_notes);
 return jsonb_build_object('ended_workflow_version_id',current_row.id,'ended_effective_end_date',selected_effective_start_date-1,'replacement',create_result);
end;$function$;
revoke all on function public.replace_employee_approval_workflow(uuid,text,date,date,jsonb,text) from public,anon;
grant execute on function public.replace_employee_approval_workflow(uuid,text,date,date,jsonb,text) to authenticated;
