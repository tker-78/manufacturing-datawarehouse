with conversion as (
    select * from {{ ref('stg_conversion') }}
    where is_rejected is true
),
attribution as (
    select * from {{ ref('int_coil_shift_attribution') }}
),
joined as (
    select
        conversion.*,
        attribution.shift_id
    from conversion
    left join attribution
    on conversion.coil_id = attribution.coil_id
)
select * from joined