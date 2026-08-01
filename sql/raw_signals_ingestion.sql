with affected_keys as (
select distinct
device_id,
signal_id,
date_trunc('minute', event_timestamp) as event_time_minute
from signals
-- where batch_id = :current_batch_id
),
aggregated as (
  select
    s.device_id,
    s.signal_id,
    date_trunc('minute', s.event_timestamp) as event_time_minute,
    max(s.value) as max_value,
    min(s.value) as min_value,
    max(s.batch_id) as batch_id
  from signals s
  inner join affected_keys k
    on s.device_id = k.device_id
   and s.signal_id = k.signal_id
   and date_trunc('minute', s.event_timestamp) = k.event_time_minute
  group by
    s.device_id,
    s.signal_id,
    date_trunc('minute', s.event_timestamp)
)
insert into stg_signal_1min (
  device_id,
  signal_id,
  event_time_minute,
  max_value,
  min_value,
  batch_id
)
select
  device_id,
  signal_id,
  event_time_minute,
  max_value,
  min_value,
  batch_id
from aggregated
on conflict (device_id, signal_id, event_time_minute)
do update set
  max_value = excluded.max_value,
  min_value = excluded.min_value,
  batch_id = excluded.batch_id;