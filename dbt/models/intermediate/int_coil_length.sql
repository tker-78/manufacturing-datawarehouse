with coil as (
    select * from {{ ref('stg_conversion') }}
),

picked as (
    select
        coil_id,
        fm_del_thickness_average as thickness,
        fm_del_width_average as width,
        case
            when coil_weight_actual <> 0 then coil_weight_actual
            when coil_weight_actual = 0 then coil_weight_calculated
        end as weight
    from coil
),

calculated as (
    select
        coil_id,
        thickness::numeric, -- unit: mm
        width::numeric, --unit: mm
        weight::numeric, --unit: kg
        -- length: m
        (
            weight * 10 ^ 3 * 10 ^ 3 / (thickness * width * 2.7 * 10 ^ 3)
        )::numeric as length
    from picked
)

select * from calculated
