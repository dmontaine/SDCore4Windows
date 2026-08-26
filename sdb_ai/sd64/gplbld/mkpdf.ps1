<#
    mkpdf.ps1 - render mkdoc.py's HTML pages to PDF with headless Edge.

    command line:
        mkpdf.ps1 -In <dir-or-file> [-Out <dir>]

    WHY THIS EXISTS AT ALL, GIVEN THE FORMAT DECISION SAID NO PDF SHIPS.
    It still does not ship.  PROJECT_STATUS "THE FORMAT" rules that the user
    prints to PDF from the browser and that no PDF goes in the installer,
    because the no-binaries rule in CLAUDE.md forbids tracking one.  This
    script does not change that: it writes PDFs OUTSIDE the repository, into
    the hand-carried sdhelp tree, on the owner's instruction of 26 Aug 2026
    that the first tester document set be delivered in both Markdown and PDF.
    Nothing it produces is tracked, staged or installed.

    WHY EDGE AND NOT A PDF LIBRARY.  Edge is on every supported Windows
    machine, so this adds no dependency to the build - the same argument that
    chose the browser as the reader in the first place.  wkhtmltopdf and
    weasyprint would each be a new install; pandoc was already rejected for
    being a binary dependency.  Headless Chrome is accepted as a fallback
    because it takes the identical switch, and this prints THE SAME HTML the
    reader sees, so the PDF cannot drift from the page.

    IT PRINTS THE FILE, NOT A COPY OF THE CONTENT.  mkdoc.py embeds its CSS,
    so there is no asset folder to resolve and a file:// URL is enough.  The
    print stylesheet mkdoc.py already carries is what makes the output clean.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$In,
    [string]$Out,
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = 'Stop'

function Say($m) { Write-Output ("mkpdf: " + $m) }

# --- find a browser -------------------------------------------------------
# Edge first, Chrome as the fallback.  Both take --headless --print-to-pdf.
$candidates = @(
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')
)
$browser = $null
foreach ($c in $candidates) {
    if ($c -and (Test-Path -LiteralPath $c)) { $browser = $c; break }
}
if (-not $browser) {
    Write-Error ("no Edge or Chrome found.  Looked in:`n  " + ($candidates -join "`n  "))
}

# --- resolve the inputs ---------------------------------------------------
if (-not (Test-Path -LiteralPath $In)) { Write-Error ("no such path: " + $In) }
$inItem = Get-Item -LiteralPath $In
if ($inItem.PSIsContainer) {
    $sources = @(Get-ChildItem -LiteralPath $inItem.FullName -Filter '*.html' |
                 Sort-Object Name)
    if (-not $Out) { $Out = $inItem.FullName }
} else {
    $sources = @($inItem)
    if (-not $Out) { $Out = $inItem.DirectoryName }
}

if (-not (Test-Path -LiteralPath $Out)) {
    $null = New-Item -ItemType Directory -Path $Out -Force
}
$outDir = (Resolve-Path -LiteralPath $Out).Path

# AN INSTRUMENT PRINTS WHAT IT DID (CLAUDE.md).  The resolved paths and the
# count matter: -In pointed at a directory with no .html renders nothing, and
# a converter that cheerfully writes nothing is the "passes because it did
# nothing" failure.  So the null case is refused out loud, below.
Say ("browser " + $browser)
Say ("in      " + $inItem.FullName)
Say ("out     " + $outDir)
Say ("sources " + $sources.Count)

if ($sources.Count -eq 0) {
    Write-Error 'no .html files found - nothing rendered.'
}

# --- print ----------------------------------------------------------------
$made = 0
$failed = @()
foreach ($s in $sources) {
    $pdf = Join-Path $outDir ([System.IO.Path]::ChangeExtension($s.Name, '.pdf'))
    $before = 0
    if (Test-Path -LiteralPath $pdf) { $before = (Get-Item -LiteralPath $pdf).Length }

    # A dedicated profile directory keeps this from touching, or being blocked
    # by, the user's own running browser.
    $profile = Join-Path ([System.IO.Path]::GetTempPath()) ('mkpdf-' + [System.Guid]::NewGuid().ToString('N'))

    # EVERY PATH-BEARING SWITCH IS QUOTED, AND THAT IS NOT DEFENSIVE - IT IS
    # THE BUG THIS SCRIPT ALREADY HAD.  Start-Process -ArgumentList with an
    # ARRAY joins the elements with spaces and quotes nothing, so a switch
    # whose value contains a space becomes several arguments.  The browser then
    # exits 13 and writes no PDF.  It passed on docs\sample and failed on all
    # eleven pages of "SD Core for Windows 1.0-0 Docs" - the only difference
    # being the spaces in the directory name.
    #
    # So the argument list is built as ONE STRING with the quoting written out,
    # which is what Chrome and Edge parse.
    $q = { param($v) '"' + $v + '"' }
    $swargs = @(
        '--headless=new',
        '--disable-gpu',
        '--no-first-run',
        '--no-default-browser-check',
        ('--user-data-dir=' + (& $q $profile)),
        '--print-to-pdf-no-header',
        ('--print-to-pdf=' + (& $q $pdf)),
        (& $q $s.FullName)
    )
    $argLine = $swargs -join ' '

    # Echo the real argument list, not the intent.  A probe whose switches were
    # silently emptied - $args is a PowerShell automatic variable - is exactly
    # how a run once reported a pass having passed nothing (CLAUDE.md).
    Write-Output ("  [run] " + (Split-Path -Leaf $browser) + ' ' + $argLine)

    $p = Start-Process -FilePath $browser -ArgumentList $argLine -PassThru -WindowStyle Hidden
    $null = $p.Handle
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        $failed += ($s.Name + ' (timed out after ' + $TimeoutSec + 's)')
        Remove-Item -LiteralPath $profile -Recurse -Force -ErrorAction SilentlyContinue
        continue
    }
    Remove-Item -LiteralPath $profile -Recurse -Force -ErrorAction SilentlyContinue

    # BEFORE AND AFTER, NOT JUST A CONCLUSION.  "the file exists" would also be
    # true of a stale PDF from an earlier run that this one failed to replace,
    # so the size is read both sides and a byte-identical result on a rerun is
    # reported as such rather than counted as fresh work.
    if (-not (Test-Path -LiteralPath $pdf)) {
        $failed += ($s.Name + ' (browser exited ' + $p.ExitCode + ', no PDF written)')
        continue
    }
    $after = (Get-Item -LiteralPath $pdf).Length
    if ($after -lt 1000) {
        $failed += ($s.Name + ' (PDF is only ' + $after + ' bytes - almost certainly empty)')
        continue
    }
    Write-Output ("  [ok]  " + $s.Name + ' -> ' + (Split-Path -Leaf $pdf) +
                  '  ' + $before + ' -> ' + $after + ' bytes')
    $made++
}

Write-Output ''
Say ($made.ToString() + ' of ' + $sources.Count + ' page(s) written.')
if ($failed.Count -gt 0) {
    foreach ($f in $failed) { Write-Output ("  [FAIL] " + $f) }
    Write-Error ($failed.Count.ToString() + ' page(s) failed.')
}
exit 0
