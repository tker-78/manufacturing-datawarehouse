with source as (
    select * from {{ ref('snap_shift') }}
),
modified as (
    select
    {{ dbt_utils.generate_surrogate_key(['shift_id', 'dbt_valid_from'])}} as shift_key,
    source.*
    from source
)
select * from modified