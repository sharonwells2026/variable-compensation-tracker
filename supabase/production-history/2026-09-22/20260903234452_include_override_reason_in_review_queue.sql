create or replace function public.get_compensation_review_batches()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare payload jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_app_role('system_administrator') or private.has_permission('earnings.approve') or private.has_permission('payments.view')) then
    raise exception 'Compensation review access required.' using errcode='42501';
  end if;
  select jsonb_build_object(
    'batches',coalesce((select jsonb_agg(jsonb_build_object(
      'id',b.id,'batch_name',b.batch_name,'period_start',b.period_start,'period_end',b.period_end,'status',b.status,
      'prepared_by',b.prepared_by,'submitted_by',b.submitted_by,'submitted_at',b.submitted_at,
      'approved_by',b.approved_by,'approved_at',b.approved_at,'returned_by',b.returned_by,'returned_at',b.returned_at,
      'return_reason',b.return_reason,'finance_accepted_by',b.finance_accepted_by,'finance_accepted_at',b.finance_accepted_at,
      'snapshot',b.snapshot,'created_at',b.created_at,
      'item_count',(select count(*) from public.compensation_review_batch_items i where i.review_batch_id=b.id and i.included=true),
      'employee_count',(select count(distinct i.employee_id) from public.compensation_review_batch_items i where i.review_batch_id=b.id and i.included=true),
      'proposed_total',(select coalesce(sum(i.proposed_amount),0) from public.compensation_review_batch_items i where i.review_batch_id=b.id and i.included=true)
    ) order by b.created_at desc) from public.compensation_review_batches b),'[]'::jsonb),
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'review_batch_id',i.review_batch_id,'comp_earning_id',i.comp_earning_id,'employee_id',i.employee_id,
      'employee_name',e.full_name,'proposed_amount',i.proposed_amount,'included',i.included,'review_note',i.review_note,
      'override_reason',i.override_reason,'item_snapshot',i.item_snapshot
    ) order by e.full_name,i.created_at)
    from public.compensation_review_batch_items i join public.employees e on e.id=i.employee_id),'[]'::jsonb)
  ) into payload;
  return payload;
end;
$function$;
revoke all on function public.get_compensation_review_batches() from public,anon;
grant execute on function public.get_compensation_review_batches() to authenticated;