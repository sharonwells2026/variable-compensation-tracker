insert into public.comp_periods(name,period_type,start_date,end_date,status)
select to_char(d,'FMMonth YYYY'),'monthly',d::date,(d + interval '1 month - 1 day')::date,'open'::public.comp_period_status
from generate_series(date '2025-01-01', date '2025-11-01', interval '1 month') d
on conflict (period_type,start_date,end_date) do nothing;
