with coil as (
    select * from {{ ref('fact_coil_completion') }}
),
shift as (
    select * from {{ ref('dim_shift') }}
),
joined as (
    select
    {{ dbt_utils.star(
        ref('fact_coil_completion'),
        relation_alias='coil',
        except=['shift_key']
    ) }},
    shift.shift_id,
    shift.group_name,
    shift.shift_start_timestamp_local,
    shift.shift_end_timestamp_local
    from coil
    left join shift
        on shift.shift_key = coil.shift_key
),
base_shift as (
    select distinct on (date_trunc('hour', coil_completion_timestamp))
        date_trunc('hour', coil_completion_timestamp) as hour,
        shift_id,
        group_name
    from joined
    order by
        date_trunc('hour', coil_completion_timestamp),
        coil_completion_timestamp
),
final as (
    select
        date_trunc('hour', coil_completion_timestamp) as hour,
        base_shift.shift_id,
        base_shift.group_name,
        count(coil_id) as coil_count,
        sum(coil_weight) as coil_weight,
        sum(coil_length) as coil_length,
        sum(coil_completion_duration) as coil_completion_process_duration
    from joined
    left join base_shift
    on base_shift.hour = date_trunc('hour', coil_completion_timestamp)
    group by 1,2,3
)
select * from final