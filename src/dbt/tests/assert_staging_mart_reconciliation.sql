-- Integridade cruzada: todo atendimento COMPLETED do Staging deve estar no Mart (e vice-versa), com o mesmo valor faturado.
with staging as (

    select appointment_id, billed_amount
    from {{ ref('stg_appointments') }}
    where status = 'COMPLETED'

),

mart as (

    select appointment_id, billed_amount
    from {{ ref('fct_billed_appointments') }}

)

select
    coalesce(s.appointment_id, m.appointment_id) as appointment_id,
    s.billed_amount                              as staging_billed_amount,
    m.billed_amount                              as mart_billed_amount
from staging s
full outer join mart m
    on s.appointment_id = m.appointment_id
where s.appointment_id is null
   or m.appointment_id is null
   or abs(s.billed_amount - m.billed_amount) > 0.01
