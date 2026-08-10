with conversion as (
    select * from {{ ref('stg_conversion') }}
),
shift as (
    select * from {{ ref('stg_shift') }}
),
attribution as (
    select
        conversion.coil_id,
        shift.shift_id
    from conversion
    left join shift
    on shift.shift_start_timestamp_utc <= conversion.eject_timestamp_utc
    and conversion.eject_timestamp_utc < shift.shift_end_timestamp_utc
)
select * from attribution