<#
.SYNOPSIS
  Build et deploie l'app web Occasion sur GitHub Pages via la branche gh-pages.

.DESCRIPTION
  Contourne GitHub Actions (utile tant que la facturation Actions est bloquee).
  1. Compile le web en release avec le bon base-href.
  2. Copie build/web dans un dossier temporaire + .nojekyll.
  3. Pousse (force) le resultat sur la branche gh-pages.

  GitHub Pages doit etre configure en mode branche :
    gh api -X PUT repos/davekbg08-cloud/occasion/pages -f build_type=legacy -f "source[branch]=gh-pages" -f "source[path]=/"

  Site : https://davekbg08-cloud.github.io/occasion/

.EXAMPLE
  pwsh tool/deploy_web.ps1
#>

[CmdletBinding()]
param(
  [string]$Remote   = 'https://github.com/davekbg08-cloud/occasion.git',
  [string]$Branch   = 'gh-pages',
  [string]$BaseHref = '/occasion/',
  [string]$Email    = 'davekbg08@gmail.com',
  [string]$Name     = 'davekbg08-cloud',
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

# Racine du projet = dossier parent de ce script.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $SkipBuild) {
  Write-Host "==> flutter build web --release --base-href $BaseHref" -ForegroundColor Cyan
  flutter build web --release --base-href $BaseHref
  if ($LASTEXITCODE -ne 0) { throw "flutter build web a echoue (code $LASTEXITCODE)." }
}

$webDir = Join-Path $root 'build\web'
if (-not (Test-Path $webDir)) { throw "Dossier introuvable : $webDir. Lance sans -SkipBuild." }

$tmp = Join-Path $env:TEMP 'occasion-ghpages'
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Path $tmp | Out-Null

Write-Host "==> Copie de build/web -> $tmp" -ForegroundColor Cyan
Copy-Item -Recurse -Force (Join-Path $webDir '*') $tmp
# .nojekyll : empeche GitHub Pages d'ignorer les fichiers commencant par _.
New-Item -ItemType File -Path (Join-Path $tmp '.nojekyll') | Out-Null

Push-Location $tmp
try {
  git init -q
  git checkout -q -b $Branch
  git add -A
  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
  git -c user.email=$Email -c user.name=$Name commit -q -m "Deploy Occasion web ($stamp)"
  git remote add origin $Remote
  Write-Host "==> Push force sur origin/$Branch" -ForegroundColor Cyan
  git push -f origin $Branch
  if ($LASTEXITCODE -ne 0) { throw "git push a echoue (code $LASTEXITCODE)." }
}
finally {
  Pop-Location
}

# Declenche un nouveau build Pages (necessite gh authentifie). Non bloquant.
Write-Host "==> Declenchement du build GitHub Pages" -ForegroundColor Cyan
gh api -X POST repos/davekbg08-cloud/occasion/pages/builds 2>$null | Out-Null

Write-Host ""
Write-Host "OK. Site : https://davekbg08-cloud.github.io/occasion/ (propagation ~1 min)" -ForegroundColor Green
