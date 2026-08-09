with source as (
    select * from {{ source('history', 'r_cnvact') }}
),
conversion as (
    select
        c_piecename::text as picename,
        to_timestamp(c_historykeytm, 'YYYYMMDDHH24MISS') as timestamp_local,
        gt_historykeytm::timestamp as timestamp_utc,
        c_coilid::text as coil_id,
        c_palletno::text as pallet_no,
        i_dcno::int as dc_no,
        f_fmdelthktarg::numeric(12,4) as fm_del_thickness_target,
        f_fmdelwidtarg::numeric(12,4) as fm_del_width_target,
        f_fmdelthkave::numeric(12,4) as fm_del_thickness_average,
        f_fmdelthkave::numeric(12,4) as fm_del_width_average,
        f_coildiainner::numeric(12,4) as coil_diameter_inner,
        f_coildiaouter::numeric(12,4) as coil_diameter_outer,
        case b_weightopeflag
            when 1 then true
            when 0 then false
        end as weight_operation_flag,
        gt_weighttm::timestamp as weight_measured_timestamp,
        f_coilcalwt::numeric(12,4) as coil_weight_calculated,
        f_coilactwt::numeric(12,4) as coil_weight_actual,
        i_routingcode::int as routing_code,
        c_coilshape::text as coil_shape,
        c_coilshapereason::text as coil_shape_reason,
        c_stripsurface::text as strip_surface,
        c_stripsurfacereason::text as strip_surface_reason,
        gt_ejecttm::timestamp as eject_timestamp_utc,
        case b_isrejected
            when 1 then true
            when 0 then false
        end as is_rejected,
        c_rejectarea::text as reject_area,
        c_rejectreasoncode::text as reject_reason_code,
        c_rejectreason::text as reject_reason,
        gt_rejecttm::timestamp as reject_timestamp_utc,
        case b_inspectcomp
            when 1 then true
            when 0 then false
        end as is_inspected,
        case b_holdmove
            when 1 then true
            when 0 then false
        end as is_hold_move,
        case b_insprequest
            when 1 then true
            when 0 then false
        end as is_inspect_requested,
        i_strapnumber::int as strap_number
    from source
)
select * from conversion