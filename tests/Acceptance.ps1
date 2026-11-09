# Run in each real target shell with -NoProfile. All profile edits use temp fixtures.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$installer = Join-Path $root 'Set-ColoredPrompt.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('prompt-fixtures-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixture)
$script:checks = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
    $script:checks++
}
function BytesEqual([byte[]]$A,[byte[]]$B) { return [Convert]::ToBase64String($A) -ceq [Convert]::ToBase64String($B) }
function Render($Settings, [int]$Major = $PSVersionTable.PSVersion.Major) {
    $parts = Get-ColoredPromptParts $Settings $Major 'user' 'HOST' 'C:\Path' 'C:\Users\user' $true
    return (($parts | ForEach-Object { $_[0] }) -join '') + ' '
}
function MustReject([scriptblock]$Operation, [string]$Message) {
    $rejected = $false
    try { & $Operation | Out-Null } catch { $rejected = $true }
    Assert $rejected $Message
}
. (Join-Path $root 'Prompt.ps1')
$defaults = $PromptSettings
Assert ((Render $defaults) -ceq ('[user@HOST] PS' + $PSVersionTable.PSVersion.Major + ' C:\Path> ')) 'native runtime label'
# Captured renderer calls verify colors without relying on terminal theme.
$script:calls = @()
function Write-Host { param($Object, [switch]$NoNewline, $ForegroundColor) $script:calls += ,@($Object,[string]$ForegroundColor) }
$global:ColoredPromptSettings = [ordered]@{}; foreach ($k in $defaults.Keys) { $global:ColoredPromptSettings[$k] = $defaults[$k] }
$global:ColoredPromptSettings.PrivacyMode = $true
Assert ((prompt) -ceq ' ') 'colored prompt returns one trailing space'
Assert (($script:calls | ForEach-Object { $_[0] }) -join '' -ceq ('[user@HOST] PS' + $PSVersionTable.PSVersion.Major + ' <path>>')) 'privacy native rendering'
Assert (($script:calls | ForEach-Object { $_[1] }) -join ',' -ceq 'White,Green,White,Red,White,White,White,White,Green,White') 'default captured color sequence'
$global:ColoredPromptSettings.EnableColor = $false; $script:calls = @()
Assert ((prompt) -ceq ('[user@HOST] PS' + $PSVersionTable.PSVersion.Major + ' <path>> ')) 'plain prompt'
Assert ($script:calls.Count -eq 0) 'plain emits no styling calls'
Remove-Item Function:\Write-Host
for ($mask = 0; $mask -lt 16; $mask++) {
    $s = [ordered]@{}; foreach ($k in $defaults.Keys) { $s[$k] = $defaults[$k] }
    $s.ShowName = [bool]($mask -band 1); $s.ShowHost = [bool]($mask -band 2)
    $s.ShowShell = [bool]($mask -band 4); $s.ShowPath = [bool]($mask -band 8)
    $identity = if ($s.ShowName -and $s.ShowHost) { '[user@HOST]' } elseif ($s.ShowName) { '[user]' } elseif ($s.ShowHost) { '[HOST]' } else { '' }
    $groups = @(); if ($identity) { $groups += $identity }; if ($s.ShowShell) { $groups += 'PS' + $PSVersionTable.PSVersion.Major }; if ($s.ShowPath) { $groups += 'C:\Path' }
    Assert ((Render $s) -ceq (($groups -join ' ') + '> ')) "visibility $mask"
}
Assert ((Render $defaults 9) -ceq '[user@HOST] PS9 C:\Path> ') 'MOCKED future major fallback'
$s = [ordered]@{}; foreach ($k in $defaults.Keys) { $s[$k] = $defaults[$k] }
$s.PS5Label = 'Classic'; $s.PS7Label = 'Modern'; $s.OtherLabelPrefix = 'Shell'
$s.OpenBracket = '('; $s.CloseBracket = ')'; $s.IdentitySeparator = ':'; $s.EndSymbol = '#'
$expectedLabel = if ($PSVersionTable.PSVersion.Major -eq 5) { 'Classic' } else { 'Modern' }
Assert ((Render $s) -ceq ('(user:HOST) ' + $expectedLabel + ' C:\Path# ')) 'custom labels and punctuation native major'
Assert ((Render $s 9) -ceq '(user:HOST) Shell9 C:\Path# ') 'MOCKED custom fallback prefix'
Assert ((Get-ColoredPromptPath 'C:\Users\user\Work' 'C:\Users\user' HomeRelative $true) -ceq '~\Work') 'home-relative'
Assert ((Get-ColoredPromptPath 'C:\Users\user2\Work' 'C:\Users\user' HomeRelative $true) -ceq 'C:\Users\user2\Work') 'home boundary'
Assert ((Get-ColoredPromptPath 'C:\Users\user' 'C:\Users\user' HomeRelative $true) -ceq '~') 'home itself'
Assert ((Get-ColoredPromptPath 'C:\Path' '' Leaf $true) -ceq 'Path') 'leaf'
foreach ($path in @('C:\','\\HOST\share\','HKLM:\')) { Assert ((Get-ColoredPromptPath $path '' Leaf $true) -ceq $path) 'root preservation' }
Assert ((Get-ColoredPromptPath 'HKLM:\Software' 'HKLM:' HomeRelative $false) -ceq 'HKLM:\Software') 'provider home exclusion'
Assert ((Get-ColoredPromptPath 'HKLM:\Software' '' Leaf $false) -ceq 'Software') 'provider leaf'
$source = [IO.File]::ReadAllText((Join-Path $root 'Prompt.ps1')).Replace("`r`n","`n")
foreach ($case in @(
    @{ Name='utf8'; Encoding=[Text.UTF8Encoding]::new($false) },
    @{ Name='utf8bom'; Encoding=[Text.UTF8Encoding]::new($true) },
    @{ Name='ansi'; Encoding=[Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage) },
    @{ Name='utf16le'; Encoding=[Text.UnicodeEncoding]::new($false,$true) },
    @{ Name='utf16be'; Encoding=[Text.UnicodeEncoding]::new($true,$true) },
    @{ Name='utf32le'; Encoding=[Text.UTF32Encoding]::new($false,$true) },
    @{ Name='utf32be'; Encoding=[Text.UTF32Encoding]::new($true,$true) }
)) {
    foreach ($nl in @("`n","`r`n")) {
        $path = Join-Path $fixture ($case.Name + '-' + $nl.Length + '.ps1')
        $enc = $case.Encoding
        $prefix = '# synthetic ' + [char]0x00e9 + $nl + '$unrelated = 42' + $nl
        $before = [byte[]]($enc.GetPreamble() + $enc.GetBytes($prefix))
        [IO.File]::WriteAllBytes($path,$before)
        & $installer -ProfilePaths $path | Out-Null
        $installed = [IO.File]::ReadAllBytes($path)
        Assert (BytesEqual $before ([byte[]]$installed[0..($before.Length-1)])) 'original bytes preserved'
        $backups = @(Get-ChildItem -LiteralPath $fixture -Filter ((Split-Path $path -Leaf) + '*.bak'))
        Assert ($backups.Count -eq 1 -and (BytesEqual $before ([IO.File]::ReadAllBytes($backups[0].FullName)))) 'pre-edit backup bytes'
        & $installer -ProfilePaths $path | Out-Null
        Assert (BytesEqual $installed ([IO.File]::ReadAllBytes($path))) 'repeat install idempotent'
        Assert (@(Get-ChildItem -LiteralPath $fixture -Filter ((Split-Path $path -Leaf) + '*.bak')).Count -eq 1) 'repeat creates no backup'
        # Edit an installed header, then upgrade without losing it.
        $text = $enc.GetString($installed,$enc.GetPreamble().Length,$installed.Length-$enc.GetPreamble().Length)
        $text = $text.Replace("NameColor         = 'Green'", "NameColor         = 'Cyan'").Replace("PS5Label          = 'PS5'", "PS5Label          = 'Legacy'")
        [IO.File]::WriteAllBytes($path,[byte[]]($enc.GetPreamble()+$enc.GetBytes($text)))
        $custom = [IO.File]::ReadAllBytes($path)
        & $installer -ProfilePaths $path | Out-Null
        Assert (BytesEqual $custom ([IO.File]::ReadAllBytes($path))) 'custom settings survive upgrade'
        . $path
        Assert ($global:ColoredPromptSettings.NameColor -ceq 'Cyan') 'edited header loads'
        [IO.File]::AppendAllText($path,('# later unrelated edit' + $nl),$enc)
        & $installer -Action Uninstall -ProfilePaths $path | Out-Null
        $expected = [byte[]]($before + $enc.GetBytes($nl + $nl + '# later unrelated edit' + $nl))
        Assert (BytesEqual $expected ([IO.File]::ReadAllBytes($path))) 'scoped uninstall preserves later bytes'
        $removed = [IO.File]::ReadAllBytes($path)
        & $installer -Action Uninstall -ProfilePaths $path | Out-Null
        Assert (BytesEqual $removed ([IO.File]::ReadAllBytes($path))) 'uninstall idempotent'
    }
}
$target = Join-Path $fixture 'fresh profile.ps1'
& $installer -ProfilePaths $target | Out-Null
. $target
Assert ($global:ColoredPromptSettings.NameColor -ceq 'Green') 'fresh installed profile loads'
foreach ($change in @(
    @("NameColor         = 'Green'", "NameColor         = 'Invisible'"),
    @("PathStyle         = 'Full'", "PathStyle         = 'Broken'"),
    @("NameColor         = 'Green'", 'NameColor         = (Get-Date)'),
    @("NameColor         = 'Green'", "NameColor         = 'Green' > 'unexpected.txt'"),
    @("}`n# ================= END PROMPT SETTINGS", "} | Out-Null`n# ================= END PROMPT SETTINGS"),
    @('function global:prompt {','function global:prompt { # manual code edit')
)) {
    [IO.File]::WriteAllText($target,$source.Replace($change[0],$change[1]))
    $before = [IO.File]::ReadAllBytes($target)
    MustReject { & $installer -ProfilePaths $target } 'invalid/unsupported settings rejected'
    Assert (BytesEqual $before ([IO.File]::ReadAllBytes($target))) 'rejection leaves bytes unchanged'
}
# Obtain legacy variants from the installer already loaded into this scope.
# Running it via dot sourcing against a fixture exposes its recognition helper.
. $installer -Action Uninstall -ProfilePaths (Join-Path $fixture 'absent.ps1') | Out-Null
foreach ($legacy in (Get-LegacyPrompt)) {
    foreach ($nl in @("`n","`r`n")) {
        [IO.File]::WriteAllText($target,('# before' + $nl + $legacy.Replace("`n",$nl) + $nl + '# after'))
        & $installer -ProfilePaths $target | Out-Null
        . $target
        Assert ($global:ColoredPromptSettings.NameColor -ceq 'Green') 'legacy upgrade defaults'
    }
}
# Multi-target preflight prevents an invalid second profile changing the first.
$first = Join-Path $fixture 'first.ps1'; [IO.File]::WriteAllText($first,'# keep')
[IO.File]::WriteAllText($target,'# BEGIN USER-HOST COLORED PROMPT')
MustReject { & $installer -ProfilePaths @($first,$target) } 'ambiguous marker rejection'
Assert ([IO.File]::ReadAllText($first) -ceq '# keep') 'all targets preflighted'
# Launch the real CMD entry points from an unrelated directory with spaces.
$launch = Join-Path $fixture 'launcher directory with spaces'
$null = [IO.Directory]::CreateDirectory($launch)
foreach ($name in 'Prompt.ps1','Set-ColoredPrompt.ps1','Set-ColoredPrompt.cmd','Remove-ColoredPrompt.cmd') {
    [IO.File]::Copy((Join-Path $root $name),(Join-Path $launch $name))
}
$launchProfile = Join-Path $fixture 'CMD profile with spaces.ps1'
$policyBefore = Get-ExecutionPolicy -List | Out-String
$oldPause = $env:COLORED_PROMPT_NO_PAUSE
try {
    $env:COLORED_PROMPT_NO_PAUSE = '1'
    Push-Location $fixture
    try {
        & cmd.exe /d /c ('call "' + (Join-Path $launch 'Set-ColoredPrompt.cmd') + '" -ProfilePaths "' + $launchProfile + '"') | Out-Null
        Assert ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $launchProfile)) 'install CMD relative path with spaces'
        Assert ([IO.File]::ReadAllText($launchProfile).Contains('# Configurable prompt format 1')) 'CMD installed managed block'
        & cmd.exe /d /c ('call "' + (Join-Path $launch 'Remove-ColoredPrompt.cmd') + '" -ProfilePaths "' + $launchProfile + '"') | Out-Null
        Assert ($LASTEXITCODE -eq 0 -and -not [IO.File]::ReadAllText($launchProfile).Contains('# BEGIN USER-HOST')) 'uninstall CMD with spaces'
    } finally { Pop-Location }
} finally { $env:COLORED_PROMPT_NO_PAUSE = $oldPause }
Assert ((Get-ExecutionPolicy -List | Out-String) -ceq $policyBefore) 'saved execution policies unchanged'
$empty = Join-Path $fixture 'empty.ps1'; [IO.File]::WriteAllBytes($empty,[byte[]]@())
& $installer -ProfilePaths $empty | Out-Null
Assert ([IO.File]::ReadAllText($empty).Contains('# Configurable prompt format 1')) 'empty existing profile installation'
# Invalid source configuration must also leave an unrelated target untouched.
[IO.File]::WriteAllText((Join-Path $launch 'Prompt.ps1'), $source.Replace("PathStyle         = 'Full'", "PathStyle         = 'Broken'"))
$before = [IO.File]::ReadAllBytes($empty)
MustReject { & (Join-Path $launch 'Set-ColoredPrompt.ps1') -ProfilePaths $empty } 'invalid source setting'
Assert (BytesEqual $before ([IO.File]::ReadAllBytes($empty))) 'invalid source leaves target untouched'
$native = (Get-Process -Id $PID).Path
& $native -NoProfile -Command 'if (Test-Path Variable:\ColoredPromptSettings) { exit 1 } else { exit 0 }'
Assert ($LASTEXITCODE -eq 0) 'native NoProfile omits installed fixture prompt'
Write-Output ("PASS: {0} checks; native runtime {1}; fixture root {2}" -f $script:checks,$PSVersionTable.PSVersion,$fixture)
