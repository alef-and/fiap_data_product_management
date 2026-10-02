with appointments as (

    select * from {{ ref('stg_appointments') }}

)

select
    appointment_id,
    patient_id,
    provider_id,
    specialty,
    procedure_code,
    health_plan,
    care_type,
    billed_amount,
    denied_amount,
    copay_amount,
    round(billed_amount - denied_amount, 2)                as net_amount,
    round(billed_amount - denied_amount - copay_amount, 2) as plan_receivable,
    status,
    appointment_at
from appointments
where status = 'COMPLETED'
