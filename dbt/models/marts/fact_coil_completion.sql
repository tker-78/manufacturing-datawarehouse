with conversion as (
    select * from {{ ref('stg_conversion') }}
    where is_rejected is not true
),

attribution as (
    select * from {{ ref('int_coil_shift_attribution') }}
),

tracking as (
    select * from {{ ref('stg_tracking') }}
),

joined as (
    select
        conversion.*,
        attribution.shift_id,
        tracking.fce_extract_timestamp_utc,
        tracking.dc_z_off_timestamp_utc
    from conversion
    left join attribution
        on conversion.coil_id = attribution.coil_id
    left join tracking
        on conversion.coil_id = tracking.coil_id
),

modified as (
    select
        coil_id as coil_id,
        shift_id as shift_id,
        eject_timestamp_utc as coil_completion_timestamp,
        coil_weight_actual as coil_weight,
        -- coil_length todo
        fm_del_width_average as coil_width,
        fm_del_thickness_average as coil_thickness,
        -- coil_quality_rating todo
        extract(
            epoch from (dc_z_off_timestamp_utc - fce_extract_timestamp_utc)
        ) as coil_completion_duration
    from joined
)

select * from modified
