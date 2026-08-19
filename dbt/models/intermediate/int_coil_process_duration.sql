with tracking as (
    select * from {{ ref('stg_tracking') }}
),
picked as (
    select
        coil_id,
        fce_extract_timestamp_utc,
        dc_z_off_timestamp_utc
    from tracking
),
final as (
    select
        coil_id,
        'coil_completion_duration' as process_duration_name,
        extract (epoch from (
            dc_z_off_timestamp_utc - fce_extract_timestamp_utc
            )
        ) as process_duration_seconds
    from picked
)
select * from final