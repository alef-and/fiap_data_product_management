# Demonstra o DAG Circuit Breaker: dados corrompidos na origem sao bloqueados antes de chegar ao consumidor.
# Uso (a partir da raiz): powershell -ExecutionPolicy Bypass -File scripts\run_circuit_breaker.ps1

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'
# Todos os caminhos (dbt, Soda, DuckDB) sao relativos a raiz do repositorio
$root = Split-Path -Parent $PSScriptRoot
Set-Location -Path $root
$venv = Join-Path $root '.venv\Scripts'

$python = Join-Path $venv 'python.exe'
$dbt    = Join-Path $venv 'dbt.exe'
$soda   = Join-Path $venv 'soda.exe'
$dbtBuild = @('build', '--project-dir', 'src/dbt', '--profiles-dir', 'src/dbt')
$sodaArgs = @('scan', '-d', 'analytics', '-c', 'src/quality_gate/configuration.yml', 'src/quality_gate/checks.yml')
$snapshotQuery = "import duckdb; c=duckdb.connect('data/analytics.duckdb', read_only=True); r=c.execute('select count(*), round(sum(net_amount), 2) from main.fct_billed_appointments').fetchone(); print(f'{r[0]} linhas | net_amount total = {r[1]}')"

function Write-Title([string]$Title) {
    Write-Host "`n==================== $Title ====================" -ForegroundColor Cyan
}

function Stop-Demo([string]$Message) {
    Write-Host "[FALHA NA DEMO] $Message" -ForegroundColor Red
    exit 1
}

function Invoke-ExpectSuccess {
    param([string]$Title, [string]$Exe, [string[]]$Arguments)
    Write-Title $Title
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { Stop-Demo "$Title deveria passar (exit code $LASTEXITCODE)." }
}

function Invoke-ExpectFailure {
    param([string]$Title, [string]$Exe, [string[]]$Arguments)
    Write-Title $Title
    & $Exe @Arguments
    if ($LASTEXITCODE -eq 0) { Stop-Demo "$Title deveria ter bloqueado a esteira." }
    Write-Host "[BLOQUEADO] $Title interrompeu a esteira (exit code $LASTEXITCODE), como esperado." -ForegroundColor Yellow
}

# 1. Estado saudavel
Invoke-ExpectSuccess 'Passo 1: Base sintetica limpa'        $python @('src/synthetic_data/setup_duckdb.py')
Invoke-ExpectSuccess 'Passo 2: dbt deps'                     $dbt    @('deps', '--project-dir', 'src/dbt', '--profiles-dir', 'src/dbt')
Invoke-ExpectSuccess 'Passo 3: dbt build (estado saudavel)'  $dbt    $dbtBuild
$before = & $python -c $snapshotQuery
Write-Host "Mart antes do incidente: $before" -ForegroundColor Green

# 2. Incidente na origem
Invoke-ExpectSuccess 'Passo 4: Injecao de dados corrompidos' $python @('src/synthetic_data/inject_anomaly.py')

# 3. Gate 1: Soda Core na ingestao
Invoke-ExpectFailure 'Passo 5: Gate 1 - Soda Core (ingestao)' $soda $sodaArgs

# 4. Gate 2: testes do dbt (simulando que o Gate 1 foi ignorado)
Invoke-ExpectFailure 'Passo 6: Gate 2 - dbt build (Circuit Breaker)' $dbt $dbtBuild

# 5. Consumidor protegido
Write-Title 'Passo 7: Verificacao do Mart de consumo'
$after = & $python -c $snapshotQuery
Write-Host "Mart antes : $before"
Write-Host "Mart depois: $after"
if ($before -ne $after) { Stop-Demo 'O Mart foi alterado pelos dados corrompidos.' }
Write-Host '[PROTEGIDO] O Mart manteve os ultimos dados validos.' -ForegroundColor Green

# 6. Restauracao
Invoke-ExpectSuccess 'Passo 8: Restauracao dos dados'      $python @('src/synthetic_data/restore_data.py')
Invoke-ExpectSuccess 'Passo 9: Gate 1 - Soda Core (verde)'  $soda   $sodaArgs
Invoke-ExpectSuccess 'Passo 10: Gate 2 - dbt build (verde)' $dbt    $dbtBuild

Write-Host "`n[OK] Circuit Breaker demonstrado com sucesso: dados corrompidos bloqueados e consumidor protegido." -ForegroundColor Green
