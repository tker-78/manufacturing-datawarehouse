with source as (
    select * from {{ source('operations', 'r_shift') }}
),
shift as (
    select
        c_shiftcode::text as shift_id,
        gt_starttime::timestamp as shift_start_timestamp_utc,
        gt_endtime::timestamp as shift_end_timestamp_utc,
        i_shiftno::int as shift_no,
        c_groupname::text as group_name,
        to_timestamp(c_locstarttime, 'YYYYMMDDHH24MISS') as shift_start_timestamp_local,
        to_timestamp(c_locendtime, 'YYYYMMDDHH24MISS') as shift_end_timestamp_local
    from source
)
select * from shift
