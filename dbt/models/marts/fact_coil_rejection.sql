with conversion as (
    select * from {{ ref('stg_conversion') }}
    where is_rejected is true
),

attribution as (
    select * from {{ ref('int_coil_shift_attribution') }}
),

attribution_timestamp as (
    select * from {{ ref('int_shift_attribution_timestamp') }}
),

length as (
    select * from {{ ref('int_coil_length') }}
),

tracking as (
    select * from {{ ref('stg_tracking') }}
),

shift as (
    select * from {{ ref('dim_shift') }}
),

joined as (
    select
        conversion.*,
        attribution.shift_id,
        tracking.fce_extract_timestamp_utc,
        tracking.dc_z_off_timestamp_utc,
        length.length,
        attribution_timestamp.shift_attribution_timestamp_utc
    from conversion
    left join attribution
        on conversion.coil_id = attribution.coil_id
    left join tracking
        on conversion.coil_id = tracking.coil_id
    left join length
        on conversion.coil_id = length.coil_id
    left join attribution_timestamp
        on conversion.coil_id = attribution_timestamp.coil_id
),

modified as (
    select
        joined.coil_id as coil_id,
        -- shift_id as shift_id,
        shift.shift_key as shift_key,
        joined.shift_attribution_timestamp_utc as coil_completion_timestamp,
        joined.coil_weight_actual as coil_weight,
        joined.length::numeric(12, 4) as coil_length,
        joined.fm_del_width_average as coil_width,
        joined.fm_del_thickness_average as coil_thickness,
        -- coil_quality_rating todo
        extract(
            epoch from (
                joined.dc_z_off_timestamp_utc - joined.fce_extract_timestamp_utc
            )
        ) as coil_completion_duration
    from joined
    left join shift
        on
            shift.shift_id = joined.shift_id
            and shift.dbt_valid_to is null
)

select * from modified

