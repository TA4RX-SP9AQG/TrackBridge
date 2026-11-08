# Downloads the APRS symbol sprite sheets from hessu/aprs-symbols (pinned commit,
# SHA-256 verified). See tools/fetch_symbols.sh for why they are not in the repo.
# Usage (PowerShell): ./tools/fetch_symbols.ps1
$ErrorActionPreference = 'Stop'
$commit = 'f2286a9cd43eb6ba4501250b4c39fff111e3796c'
$base = "https://raw.githubusercontent.com/hessu/aprs-symbols/$commit"
$dest = if ($env:SYMBOLS_DEST) { $env:SYMBOLS_DEST } else { Join-Path $PSScriptRoot '..\assets\symbols\hessu' }
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$files = @(
  @{ Name = 'aprs-symbols-128-0.png'; Path = 'png/aprs-symbols-128-0.png'; Sha = '6458fb4364893f94a032a5a6f4f98850f9b5a78c29943a1971ac58416a64da66' },
  @{ Name = 'aprs-symbols-128-1.png'; Path = 'png/aprs-symbols-128-1.png'; Sha = 'bf0518c70d819fabd8f138841edabbc7be584feb0ef5cb2bf9206f0bc36f7d46' },
  @{ Name = 'aprs-symbols-128-2.png'; Path = 'png/aprs-symbols-128-2.png'; Sha = 'a841ccc807c73667cfc8c988880627ac87b1ef7cdd903715d5a5af8f01f44f4b' },
  @{ Name = 'COPYRIGHT_UPSTREAM.md';  Path = 'COPYRIGHT.md';              Sha = '203aa7bcc9d7d2e2c4f788e85a08ff8715e9eef2d798f11d105700f6cb0eceed' }
)

$tmp = New-Item -ItemType Directory -Force -Path (Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid()))
try {
  foreach ($f in $files) {
    $out = Join-Path $tmp $f.Name
    Invoke-WebRequest -Uri "$base/$($f.Path)" -OutFile $out -UseBasicParsing
    $got = (Get-FileHash -Algorithm SHA256 $out).Hash.ToLower()
    if ($got -ne $f.Sha) { throw "Checksum mismatch for $($f.Name): expected $($f.Sha), got $got" }
    Move-Item -Force $out (Join-Path $dest $f.Name)
    Write-Host "ok  $($f.Name)"
  }
} finally { Remove-Item -Recurse -Force $tmp }
Write-Host "Symbols installed in $dest"
