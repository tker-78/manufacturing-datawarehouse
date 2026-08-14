with source as (
    select * from {{ source('history', 'r_trkact') }}
),

renamed as (
    select
        c_coilid as coil_id,
        gt_fceextracttm::timestamp as fce_extract_timestamp_utc,
        -- gt_dczdotm::timestamp as dc_z_off_timestamp_utc,
        nullif(gt_dczdotm::timestamp, '1970-01-01 00:00.00')
            as dc_z_off_timestamp_utc
    from source
)

select * from renamed
