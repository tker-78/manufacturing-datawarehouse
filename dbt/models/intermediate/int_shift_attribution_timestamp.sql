with conversion as (
    select * from {{ ref('stg_conversion') }}
),

tracking as (
    select * from {{ ref('stg_tracking') }}
),

joined as (
    select
        conversion.coil_id,
        conversion.eject_timestamp_utc,
        tracking.fce_extract_timestamp_utc,
        tracking.dc_z_off_timestamp_utc
    from conversion
    left join tracking on conversion.coil_id = tracking.coil_id
),

final as (
    select
        joined.*,
        coalesce(
            eject_timestamp_utc,
            fce_extract_timestamp_utc + interval '35 minutes'
        ) as shift_attribution_timestamp_utc
    from joined
)

select * from final
