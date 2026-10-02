-- Regra contábil do faturamento: retorna os atendimentos que violam a conciliação de valores.
with mart as (

    select * from {{ ref('fct_billed_appointments') }}

)

select
    appointment_id,
    billed_amount,
    denied_amount,
    copay_amount,
    net_amount,
    plan_receivable
from mart
where abs(net_amount - (billed_amount - denied_amount)) > 0.01
   or abs(plan_receivable - (net_amount - copay_amount)) > 0.01
   or denied_amount + copay_amount > billed_amount + 0.01
   or plan_receivable < 0
