[CmdletBinding()]
param(
    [ValidateSet('Install','Uninstall')][string]$Action = 'Install',
    # Explicit targets are useful for temporary fixtures and custom console profiles.
    [string[]]$ProfilePaths
)
$ErrorActionPreference = 'Stop'
$begin = '# BEGIN USER-HOST COLORED PROMPT'
$end = '# END USER-HOST COLORED PROMPT'
function Read-PromptSource([string]$Source) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Prompt syntax is invalid. Fix PROMPT SETTINGS before installing.' }
    $assignments = @($ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$PromptSettings'}, $true))
    if ($assignments.Count -ne 1) { throw 'Expected exactly one literal PromptSettings header.' }
    $assignment = $assignments[0]
    $right = $assignment.Right
    if ($right -isnot [Management.Automation.Language.CommandExpressionAst] -or $right.Redirections.Count -or
        $right.Expression -isnot [Management.Automation.Language.ConvertExpressionAst] -or
        $right.Expression.Type.TypeName.FullName -ine 'ordered' -or
        $right.Expression.Child -isnot [Management.Automation.Language.HashtableAst]) {
        throw 'The settings header must contain only a literal ordered hashtable, without pipelines or redirections.'
    }
    $tables = @($right.FindAll({param($n) $n -is [Management.Automation.Language.HashtableAst]}, $true))
    if ($tables.Count -ne 1 -or $right.Extent.Text -notmatch '^\[ordered\]@\{') { throw 'Use a literal [ordered]@{} settings header.' }
    # Only accept literal keys, strings and booleans. No expressions are executed.
    $settings = [ordered]@{}
    foreach ($pair in $tables[0].KeyValuePairs) {
        $keyAst = $pair.Item1
        if ($keyAst -isnot [Management.Automation.Language.StringConstantExpressionAst]) { throw 'Settings keys must be literal names.' }
        $key = $keyAst.Value
        if ($settings.Contains($key)) { throw "Duplicate prompt setting '$key'." }
        $pipeline = $pair.Item2
        if ($pipeline -isnot [Management.Automation.Language.PipelineAst] -or $pipeline.PipelineElements.Count -ne 1 -or $pipeline.PipelineElements[0] -isnot [Management.Automation.Language.CommandExpressionAst] -or $pipeline.PipelineElements[0].Redirections.Count) { throw "Setting '$key' must be a literal string or boolean." }
        $valueAst = $pipeline.PipelineElements[0].Expression
        if ($valueAst -is [Management.Automation.Language.StringConstantExpressionAst]) { $value = $valueAst.Value }
        elseif ($valueAst -is [Management.Automation.Language.VariableExpressionAst] -and $valueAst.VariablePath.UserPath -in 'true','false') { $value = $valueAst.VariablePath.UserPath -eq 'true' }
        else { throw "Setting '$key' must be a literal string or boolean; expressions are not allowed." }
        $settings.Add($key, $value)
    }
    $start = $right.Extent.StartOffset; $stop = $right.Extent.EndOffset
    # Check the assignment wrapper too; extra statements cannot hide in the header.
    $literal = $Source.Substring($start, $stop - $start)
    $scaffold = $Source.Substring(0,$start) + '<SETTINGS>' + $Source.Substring($stop)
    return @{ Settings = $settings; Scaffold = $scaffold; Literal = $literal; Ast = $ast }
}
function Read-ProfileBytes([byte[]]$Bytes) {
    $skip = 0; $encoding = $null
    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 255 -and $Bytes[1] -eq 254 -and $Bytes[2] -eq 0 -and $Bytes[3] -eq 0) { $encoding = [Text.UTF32Encoding]::new($false,$true,$true); $skip = 4 }
    elseif ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0 -and $Bytes[1] -eq 0 -and $Bytes[2] -eq 254 -and $Bytes[3] -eq 255) { $encoding = [Text.UTF32Encoding]::new($true,$true,$true); $skip = 4 }
    elseif ($Bytes.Length -ge 3 -and $Bytes[0] -eq 239 -and $Bytes[1] -eq 187 -and $Bytes[2] -eq 191) { $encoding = [Text.UTF8Encoding]::new($true,$true); $skip = 3 }
    elseif ($Bytes.Length -ge 2 -and $Bytes[0] -eq 255 -and $Bytes[1] -eq 254) { $encoding = [Text.UnicodeEncoding]::new($false,$true,$true); $skip = 2 }
    elseif ($Bytes.Length -ge 2 -and $Bytes[0] -eq 254 -and $Bytes[1] -eq 255) { $encoding = [Text.UnicodeEncoding]::new($true,$true,$true); $skip = 2 }
    else {
        $encoding = [Text.UTF8Encoding]::new($false,$true)
        try { $null = $encoding.GetString($Bytes) }
        catch { $encoding = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage, [Text.EncoderExceptionFallback]::new(), [Text.DecoderExceptionFallback]::new()) }
    }
    return @{ Text = $encoding.GetString($Bytes,$skip,$Bytes.Length-$skip); Encoding = $encoding; Skip = $skip }
}
function Get-LegacyPrompt {
    # Exact supplied baseline, with either fixed PS or runtime major label.
    $block = @'
# BEGIN USER-HOST COLORED PROMPT
function global:prompt {
    Write-Host '[' -NoNewline -ForegroundColor White
    Write-Host $env:USERNAME -NoNewline -ForegroundColor Red
    Write-Host '@' -NoNewline -ForegroundColor White
    Write-Host ([Environment]::MachineName) -NoNewline -ForegroundColor Green
    Write-Host ('] PS{0} ' -f $PSVersionTable.PSVersion.Major) -NoNewline -ForegroundColor White
    Write-Host ([string]$executionContext.SessionState.Path.CurrentLocation) -NoNewline -ForegroundColor Green
    Write-Host '>' -NoNewline -ForegroundColor White
    return ' '
}
# END USER-HOST COLORED PROMPT
'@
    $block = $block.Replace("`r`n", "`n")
    return @($block, $block.Replace("    Write-Host ('] PS{0} ' -f `$PSVersionTable.PSVersion.Major) -NoNewline -ForegroundColor White", "    Write-Host '] PS ' -NoNewline -ForegroundColor White"))
}
$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Prompt.ps1')).Replace("`r`n","`n").TrimEnd("`n")
$parsed = Read-PromptSource $template
# Load only the bundled validation function, never the settings source.
$validator = $parsed.Ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-ColoredPromptSettings'}, $true)
if (-not $validator) { throw 'Bundled settings validator is missing.' }
. ([scriptblock]::Create($validator.Extent.Text))
Test-ColoredPromptSettings $parsed.Settings
if (-not $ProfilePaths) {
    $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    if ([string]::IsNullOrWhiteSpace($documents)) { throw 'Windows Documents folder could not be resolved.' }
    $ProfilePaths = @((Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'), (Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'))
}
$plans = @()
foreach ($path in ($ProfilePaths | Select-Object -Unique)) {
    $previous = $null
    $path = [IO.Path]::GetFullPath($path)
    if (Test-Path -LiteralPath $path -PathType Container) { throw 'A profile target is a directory.' }
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    [byte[]]$bytes = @()
    if ($exists) { $bytes = [IO.File]::ReadAllBytes($path) }
    # New profiles use a UTF-8 BOM so Windows PowerShell also reads Unicode labels.
    if (-not $exists) { $bytes = [byte[]]@(239,187,191) }
    $decoded = Read-ProfileBytes $bytes
    $text = $decoded.Text
    $starts = [regex]::Matches($text, [regex]::Escape($begin)); $ends = [regex]::Matches($text, [regex]::Escape($end))
    if ($starts.Count -gt 1 -or $ends.Count -gt 1 -or $starts.Count -ne $ends.Count) { throw 'Ambiguous prompt markers. No profiles were changed.' }
    $offset = $text.Length; $length = 0; $settings = $parsed.Settings
    if ($starts.Count) {
        $offset = $starts[0].Index; $length = $ends[0].Index + $end.Length - $offset
        if ($length -le 0) { throw 'Reversed prompt markers. No profiles were changed.' }
        $old = $text.Substring($offset,$length).Replace("`r`n","`n")
        if ($old -notin (Get-LegacyPrompt)) {
            $previous = Read-PromptSource $old
            if ($previous.Scaffold -cne $parsed.Scaffold) { throw 'Unrecognized edited prompt block. No profiles were changed.' }
            Test-ColoredPromptSettings $previous.Settings
            $settings = $previous.Settings
        }
    } elseif ($Action -eq 'Uninstall') { continue }
    $newline = if ($text.Contains("`r`n")) { "`r`n" } elseif ($text.Contains("`n")) { "`n" } else { "`r`n" }
    $replacement = ''
    if ($Action -eq 'Install') {
        # Preserve an existing recognized header verbatim (including comments).
        $literal = if ($starts.Count -and $null -ne $previous) { $previous.Literal } else { $parsed.Literal }
        $replacement = $parsed.Scaffold.Replace('<SETTINGS>', $literal).Replace("`n", $newline)
        if (-not $starts.Count) { $replacement = $newline + $replacement + $newline }
    }
    $candidate = $text.Substring(0,$offset) + $replacement + $text.Substring($offset+$length)
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($candidate,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'Candidate profile syntax is invalid. No profiles were changed.' }
    $enc = $decoded.Encoding
    $byteOffset = $decoded.Skip + $enc.GetByteCount($text.Substring(0,$offset))
    $byteLength = $enc.GetByteCount($text.Substring($offset,$length))
    $insert = $enc.GetBytes($replacement)
    $updated = [byte[]]::new($bytes.Length-$byteLength+$insert.Length)
    [Array]::Copy($bytes,0,$updated,0,$byteOffset)
    [Array]::Copy($insert,0,$updated,$byteOffset,$insert.Length)
    [Array]::Copy($bytes,$byteOffset+$byteLength,$updated,$byteOffset+$insert.Length,$bytes.Length-$byteOffset-$byteLength)
    if ([Convert]::ToBase64String($bytes) -eq [Convert]::ToBase64String($updated)) { continue }
    $plans += @{ Path = $path; Before = $bytes; After = $updated; Exists = $exists }
    $previous = $null
}
# Preflight all targets before writing any. Backups stay beside private profiles.
foreach ($plan in $plans) {
    if ($plan.Exists) {
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($plan.Path)) -ne [Convert]::ToBase64String($plan.Before)) { throw 'Profile changed during preflight. Rerun the installer.' }
        $backup = $plan.Path + '.before-colored-prompt-' + [guid]::NewGuid().ToString('N') + '.bak'
        [IO.File]::Copy($plan.Path,$backup,$false)
    }
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($plan.Path))
    [IO.File]::WriteAllBytes($plan.Path,$plan.After)
}
Write-Output ("{0}: {1} profile(s) changed. Open a normal console session to load the result." -f $Action,$plans.Count)
