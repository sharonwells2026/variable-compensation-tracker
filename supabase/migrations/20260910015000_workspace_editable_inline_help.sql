create table if not exists public.ui_help_content (
  help_key text primary key,
  title text not null,
  help_text text not null,
  area text not null default 'general',
  updated_by uuid null references auth.users(id),
  updated_at timestamptz not null default now()
);
alter table public.ui_help_content enable row level security;

insert into public.ui_help_content(help_key,title,help_text,area) values
 ('plans.plan_code','Plan code','A stable internal identifier for this plan. It is created automatically from the plan name, but you can edit it before saving.','Plan setup'),
 ('plans.earning_name','Earning name','A plain-language name for one way this plan can pay the employee, such as Retention commission or Expansion commission.','Plan setup'),
 ('plans.calculation_type','How is it calculated?','Choose the payout method, such as a percentage, fixed amount, tiered percentage, milestone, or threshold bonus.','Plan setup'),
 ('plans.measurement_source','Calculation basis','Choose the amount or activity the payout is calculated from, such as Deal amount or Average ARR.','Plan setup'),
 ('plans.measurement_period','Calculation frequency','Choose whether this earning is calculated for each qualifying record or over a monthly, quarterly, or annual period.','Plan setup'),
 ('plans.maximum_payout','Maximum payout','Optional cap for this earning. Leave blank when there is no maximum.','Plan setup'),
 ('plans.earned_conditions','Earning conditions','These conditions determine when the employee has earned compensation credit. They can use approved synchronized HubSpot data.','Rules'),
 ('plans.eligible_conditions','Eligibility conditions','These are any additional requirements after compensation is Earned and before it can move toward payment.','Rules'),
 ('rules.related_object','Related HubSpot records','Use fields from related records, such as Company fields on a Deal, when those fields are approved for compensation use.','Rules')
on conflict (help_key) do nothing;

create or replace function public.get_app_help_content()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(jsonb_object_agg(help_key,jsonb_build_object('title',title,'help_text',help_text,'area',area,'updated_at',updated_at)),'{}'::jsonb)
  from public.ui_help_content;
$$;

create or replace function public.save_app_help_content(selected_help_key text, selected_title text, selected_help_text text, selected_area text default 'general')
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('settings.manage') then raise exception 'Workspace administration permission is required.' using errcode='42501'; end if;
  if nullif(trim(coalesce(selected_help_key,'')),'') is null or nullif(trim(coalesce(selected_title,'')),'') is null or nullif(trim(coalesce(selected_help_text,'')),'') is null then
    raise exception 'Help key, title, and help text are required.' using errcode='22023';
  end if;
  insert into public.ui_help_content(help_key,title,help_text,area,updated_by,updated_at)
  values(trim(selected_help_key),trim(selected_title),trim(selected_help_text),coalesce(nullif(trim(selected_area),''),'general'),(select auth.uid()),now())
  on conflict(help_key) do update set title=excluded.title,help_text=excluded.help_text,area=excluded.area,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
  return jsonb_build_object('status','saved','help_key',trim(selected_help_key));
end;
$$;

revoke all on table public.ui_help_content from anon, authenticated;
revoke all on function public.get_app_help_content() from public, anon;
revoke all on function public.save_app_help_content(text,text,text,text) from public, anon;
grant execute on function public.get_app_help_content() to authenticated;
grant execute on function public.save_app_help_content(text,text,text,text) to authenticated;
