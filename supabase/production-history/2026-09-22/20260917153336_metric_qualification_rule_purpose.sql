alter table public.comp_rule_sets
  drop constraint if exists comp_rule_sets_purpose_check;

alter table public.comp_rule_sets
  add constraint comp_rule_sets_purpose_check
  check (purpose = any (array[
    'qualification'::text,
    'metric_qualification'::text,
    'rate_selection'::text,
    'calculation'::text,
    'eligibility'::text,
    'credit'::text,
    'payout'::text,
    'exception'::text
  ]));