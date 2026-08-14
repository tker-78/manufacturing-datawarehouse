with conversion as (
    select * from {{ ref('stg_conversion') }}
),

shift as (
    select * from {{ ref('stg_shift') }}
),

attribution as (
    select * from {{ ref('int_shift_attribution_timestamp') }}
),

final as (
    select
        attribution.coil_id,
        shift.shift_id
    from attribution
    left join shift
        on
            shift.shift_start_timestamp_utc
            <= attribution.shift_attribution_timestamp_utc
            and attribution.shift_attribution_timestamp_utc
            < shift.shift_end_timestamp_utc
)

select * from final

