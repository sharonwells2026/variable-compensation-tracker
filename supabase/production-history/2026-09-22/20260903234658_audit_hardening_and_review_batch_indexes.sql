create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

revoke all on function public.set_updated_at() from public, anon, authenticated;

create index if not exists compensation_review_batch_items_employee_idx
  on public.compensation_review_batch_items(employee_id);
create index if not exists compensation_review_batches_prepared_by_idx
  on public.compensation_review_batches(prepared_by);
