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
    left join shift on coil.shift_key = shift.shift_key
),
final as (
    select
    shift_id,
    group_name,
    shift_start_timestamp_local,
    shift_end_timestamp_local,
    count(*) as coil_completion_count,
    sum(coil_weight) as coil_weight_sum,
    sum(coil_length) as coil_length_sum,
    sum(coil_completion_duration) as coil_completion_duration_sum
    from joined
    group by 1,2,3,4
)
select * from final
