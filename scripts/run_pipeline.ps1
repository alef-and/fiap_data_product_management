# Executa a esteira completa do Data Product usando o ambiente virtual do projeto.
# Uso (a partir da raiz): powershell -ExecutionPolicy Bypass -File scripts\run_pipeline.ps1

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
$dbtDirs  = @('--project-dir', 'src/dbt', '--profiles-dir', 'src/dbt')
$sodaArgs = @('scan', '-d', 'analytics', '-c', 'src/quality_gate/configuration.yml', 'src/quality_gate/checks.yml')

function Invoke-Step {
    param([string]$Title, [string]$Exe, [string[]]$Arguments)
    Write-Host "`n==================== $Title ====================" -ForegroundColor Cyan
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FALHA] $Title (exit code $LASTEXITCODE). Esteira interrompida." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Invoke-Step 'Passo 1: Base sintetica DuckDB'      $python @('src/synthetic_data/setup_duckdb.py')
Invoke-Step 'Passo 2: Quality Gate (Soda Core)'   $soda   $sodaArgs
Invoke-Step 'Passo 3: dbt deps'                   $dbt    (@('deps') + $dbtDirs)
Invoke-Step 'Passo 4: dbt debug'                  $dbt    (@('debug') + $dbtDirs)
Invoke-Step 'Passo 5: dbt build (modelos+testes)' $dbt    (@('build') + $dbtDirs)
Invoke-Step 'Passo 6: Inspecao do Mart'           $python @('src/inspection/query_mart.py')
Invoke-Step 'Passo 7: Resultados de qualidade'    $python @('src/inspection/query_test_results.py')

Write-Host "`n[OK] Esteira executada com sucesso!" -ForegroundColor Green
