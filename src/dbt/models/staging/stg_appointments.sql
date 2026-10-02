with source as (

    select * from {{ source('raw_sources', 'appointments') }}

)

select
    cast(appointment_id as varchar)               as appointment_id,
    cast(patient_id as varchar)                   as patient_id,
    cast(provider_id as varchar)                  as provider_id,
    upper(trim(cast(specialty as varchar)))       as specialty,
    cast(procedure_code as varchar)               as procedure_code,
    upper(trim(cast(health_plan as varchar)))     as health_plan,
    upper(trim(cast(care_type as varchar)))       as care_type,
    upper(trim(cast(status as varchar)))          as status,
    cast(billed_amount as double)                 as billed_amount,
    cast(coalesce(denied_amount, 0) as double)    as denied_amount,
    cast(coalesce(copay_amount, 0) as double)     as copay_amount,
    cast(appointment_at as timestamp)             as appointment_at
from source
