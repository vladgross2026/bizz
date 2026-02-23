# Скрипт для скачивания Supabase локально (обход Tracking Prevention)
# Запустите: .\download-supabase.ps1
$dir = Join-Path $PSScriptRoot "js\vendor"
$url = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"
$out = Join-Path $dir "supabase.min.js"

if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Write-Host "Downloading Supabase..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    Write-Host "Done! Saved to js/vendor/supabase.min.js" -ForegroundColor Green
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Download manually from: $url" -ForegroundColor Yellow
    Write-Host "Save as: js\vendor\supabase.min.js" -ForegroundColor Yellow
}
