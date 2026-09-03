with source as (
    select * from {{ ref('snap_shift') }}
),
modified as (
    select
    {{ dbt_utils.generate_surrogate_key(['shift_id', 'dbt_valid_from'])}} as shift_key,
    source.*,
    '2025-01-01'::timestamp as valid_from_for_join,
    case
        when dbt_valid_to is null then '9999-12-31'::timestamp
        when dbt_valid_to is not null then dbt_valid_to
    end as valid_to_for_join
    from source
)
select * from modified
