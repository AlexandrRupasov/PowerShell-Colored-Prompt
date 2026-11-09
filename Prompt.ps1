# BEGIN USER-HOST COLORED PROMPT
# Configurable prompt format 1
# ================= PROMPT SETTINGS =================
# Edit this header in the installed profile, then reload the profile.
# Colors: Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta,
# DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White.
$PromptSettings = [ordered]@{
    NameColor         = 'Green'
    HostColor         = 'Red'
    ShellColor        = 'White'
    PathColor         = 'Green'
    PunctuationColor  = 'White'
    PS5Label          = 'PS5'
    PS7Label          = 'PS7'
    OtherLabelPrefix  = 'PS'
    ShowName          = $true
    ShowHost          = $true
    ShowShell         = $true
    ShowPath          = $true
    EnableColor       = $true
    PrivacyMode       = $false
    PathStyle         = 'Full' # Full | HomeRelative | Leaf
    OpenBracket       = '['
    CloseBracket      = ']'
    IdentitySeparator = '@'
    EndSymbol         = '>'
}
# ================= END PROMPT SETTINGS =============
function Test-ColoredPromptSettings {
    param([System.Collections.IDictionary]$Settings)
    $colors = 'NameColor','HostColor','ShellColor','PathColor','PunctuationColor'
    $flags = 'ShowName','ShowHost','ShowShell','ShowPath','EnableColor','PrivacyMode'
    $strings = 'PS5Label','PS7Label','OtherLabelPrefix','OpenBracket','CloseBracket','IdentitySeparator','EndSymbol'
    $keys = @($colors) + @($flags) + @($strings) + @('PathStyle')
    foreach ($key in $Settings.Keys) {
        if ($key -notin $keys) { throw "Unknown prompt setting '$key'. Remove it from PROMPT SETTINGS." }
    }
    foreach ($key in $keys) {
        if (-not $Settings.Contains($key)) { throw "Missing prompt setting '$key'. Restore it in PROMPT SETTINGS." }
        $value = $Settings[$key]
        if ($key -in $colors -and ($value -isnot [string] -or $value -notin [Enum]::GetNames([ConsoleColor]))) {
            throw "Invalid $key. Use a standard ConsoleColor name such as Green."
        }
        if ($key -in $flags -and $value -isnot [bool]) { throw "Invalid $key. Use a literal `$true or `$false." }
        if ($key -in $strings -and ($value -isnot [string] -or $value -match '[\x00-\x1f\x7f]' -or $value -match '^\s|\s$')) {
            throw "Invalid $key. Use text without control characters or leading/trailing whitespace."
        }
    }
    if ($Settings.PathStyle -notin 'Full','HomeRelative','Leaf') { throw 'Invalid PathStyle. Use Full, HomeRelative or Leaf.' }
    foreach ($key in 'PS5Label','PS7Label','OtherLabelPrefix') {
        if (-not $Settings[$key]) { throw "Invalid $key. Use nonempty text, or hide the shell with ShowShell." }
    }
}
Test-ColoredPromptSettings $PromptSettings
# Publish validated settings only after validation succeeds.
$global:ColoredPromptSettings = $PromptSettings
function global:Get-ColoredPromptPath {
    param([string]$Path, [string]$HomePath, [string]$Style, [bool]$IsFileSystem)
    if ($Style -eq 'Full') { return $Path }
    if ($Style -eq 'HomeRelative' -and $IsFileSystem -and $HomePath) {
        $base = $HomePath.TrimEnd('\','/')
        if ($Path.Equals($base, [StringComparison]::OrdinalIgnoreCase)) { return '~' }
        if ($Path.Length -gt $base.Length -and $Path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -and $Path[$base.Length] -in '\','/') {
            return '~' + $Path.Substring($base.Length)
        }
    }
    if ($Style -eq 'Leaf') {
        $trimmed = $Path.TrimEnd('\','/')
        # Keep drive roots, provider roots and UNC share roots recognizable.
        if ($trimmed -match '^[^\\/]+:$' -or $trimmed -match '^\\\\[^\\]+\\[^\\]+$' -or -not $trimmed) { return $Path }
        return ($trimmed -split '[\\/]')[-1]
    }
    return $Path
}
function global:Get-ColoredPromptParts {
    param([System.Collections.IDictionary]$Settings, [int]$Major,
        [string]$UserName, [string]$HostName, [string]$Path, [string]$HomePath, [bool]$IsFileSystem = $true)
    $s = $Settings
    if ($s.PrivacyMode) { $UserName = 'user'; $HostName = 'HOST'; $Path = '<path>' }
    elseif ($s.ShowPath) { $Path = Get-ColoredPromptPath $Path $HomePath $s.PathStyle $IsFileSystem }
    $parts = New-Object 'System.Collections.Generic.List[object]'
    if ($s.ShowName -or $s.ShowHost) {
        $parts.Add(@($s.OpenBracket, $s.PunctuationColor))
        if ($s.ShowName) { $parts.Add(@($UserName, $s.NameColor)) }
        if ($s.ShowName -and $s.ShowHost) { $parts.Add(@($s.IdentitySeparator, $s.PunctuationColor)) }
        if ($s.ShowHost) { $parts.Add(@($HostName, $s.HostColor)) }
        $parts.Add(@($s.CloseBracket, $s.PunctuationColor))
    }
    if ($s.ShowShell) {
        if ($parts.Count) { $parts.Add(@(' ', $s.PunctuationColor)) }
        $label = if ($Major -eq 5) { $s.PS5Label } elseif ($Major -eq 7) { $s.PS7Label } else { $s.OtherLabelPrefix + $Major }
        $parts.Add(@($label, $s.ShellColor))
    }
    if ($s.ShowPath) {
        if ($parts.Count) { $parts.Add(@(' ', $s.PunctuationColor)) }
        $parts.Add(@($Path, $s.PathColor))
    }
    $parts.Add(@($s.EndSymbol, $s.PunctuationColor))
    return ,$parts
}
function global:prompt {
    $s = $global:ColoredPromptSettings
    # Privacy avoids even reading identity/location values for rendering.
    $name = ''; $machine = ''; $location = ''; $homePath = ''; $fileSystem = $false
    if (-not $s.PrivacyMode) {
        if ($s.ShowName) { $name = [Environment]::UserName }
        if ($s.ShowHost) { $machine = [Environment]::MachineName }
        if ($s.ShowPath) {
            $current = $ExecutionContext.SessionState.Path.CurrentLocation
            $location = [string]$current; $homePath = $HOME
            $fileSystem = $current.Provider.Name -eq 'FileSystem'
        }
    }
    $parts = Get-ColoredPromptParts $s $PSVersionTable.PSVersion.Major $name $machine $location $homePath $fileSystem
    if (-not $s.EnableColor) { return (($parts | ForEach-Object { $_[0] }) -join '') + ' ' }
    foreach ($part in $parts) { Write-Host -Object $part[0] -NoNewline -ForegroundColor $part[1] }
    return ' '
}
# END USER-HOST COLORED PROMPT
