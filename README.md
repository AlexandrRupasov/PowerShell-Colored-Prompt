# PowerShell Colored Prompt

A self-contained console prompt for Windows PowerShell 5.1 and PowerShell 7:

```text
[user@HOST] PS5 C:\Path>
[user@HOST] PS7 C:\Path>
```

These are synthetic examples. Local identities and locations are read dynamically.
No network services, packages or other projects are needed.

## Install and upgrade

Keep `Prompt.ps1`, `Set-ColoredPrompt.ps1` and both CMD files together.
Double-click `Set-ColoredPrompt.cmd`. It runs Windows PowerShell with `-NoProfile`
and a process-only execution policy bypass; it does not change a saved policy.
Alternatively, run `./Set-ColoredPrompt.ps1` from PowerShell under your existing
execution policy. No administrator rights are needed.

The default targets are the current user's `Microsoft.PowerShell_profile.ps1`
console profiles in `WindowsPowerShell` and `PowerShell` beneath the Windows-resolved
Documents folder (including Windows folder redirection). Editor-host profiles are
outside this scope. The installed block has no dependency on this project directory.
The CMD launcher resolves the installer relative to itself, including paths with spaces.

Open a new console normally after installation. Each shell reads its own profile
and determines its label from its session's major version. `-NoProfile` deliberately
skips profiles. Existing execution policies still govern normal profile loading.
To reload after editing the installed header, use `. $PROFILE.CurrentUserCurrentHost`.

Rerun the installer to upgrade. Recognized format-1 blocks retain their settings
header, including comments. Both exact supplied legacy blocks (fixed `PS` and runtime
major-version labels) upgrade to the new defaults. Repeating an unchanged installation
does not rewrite the profile or create a new backup. Changes outside the settings
header, duplicate markers, invalid settings and unknown formats are refused.
Resolve such changes manually before retrying; the installer never guesses which code
to overwrite. All targets are validated before profile edits begin.

Before each changed existing profile is written, a uniquely named
`.before-colored-prompt-<random>.bak` copy is retained beside that profile.
Existing bytes outside the block and BOMs are preserved. UTF-8 (with or without BOM),
UTF-16 and UTF-32 BOMs are recognized; invalid BOM-less UTF-8 falls back to the Windows
culture ANSI code page. New profiles use UTF-8 with BOM for both shells. Existing
newline styles are retained; appending creates a newline before and after the block.
Backups and profiles contain local data: keep them outside any public source tree.
Backups permit manual recovery after an I/O failure; writes across two profiles are
not a filesystem transaction.

## Settings

Edit the clearly marked **PROMPT SETTINGS** header near the top of `Prompt.ps1`
before a fresh installation, or edit that header inside each installed profile.
Installer defaults only initialize fresh and legacy installs. Existing recognized
headers take precedence during upgrades. Reload the profile after editing it.
Use literal strings and `$true`/`$false`; the installer does not execute settings
expressions. Validation runs at install/load time, before replacing an active prompt.

| Setting | Default | Meaning |
| --- | --- | --- |
| NameColor | Green | Username |
| HostColor | Red | Hostname |
| ShellColor | White | Shell label |
| PathColor | Green | Location |
| PunctuationColor | White | Brackets, separators, spaces and end symbol |
| PS5Label | PS5 | Major version 5 |
| PS7Label | PS7 | Major version 7 |
| OtherLabelPrefix | PS | Prefix plus current major version for other versions |
| ShowName, ShowHost | `$true` each | Independently show identity fields |
| ShowShell, ShowPath | `$true` each | Independently show shell and location |
| EnableColor | `$true` | Set `$false` for plain string output, with no explicit styling |
| PrivacyMode | `$false` | Replace enabled identity/path fields with `user`, `HOST`, `<path>` |
| PathStyle | Full | Full, HomeRelative or Leaf |
| OpenBracket, CloseBracket | `[`, `]` | Wrap visible identity fields |
| IdentitySeparator | `@` | Only between two visible identity fields |
| EndSymbol | `>` | Followed by exactly one trailing space |

Colors: Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow,
Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White.
Strings cannot contain control characters or leading/trailing whitespace.
Hiding identity fields also hides their brackets and separator; hiding all optional
fields yields `> ` with the defaults. HomeRelative shortens the actual home directory
and its descendants, matching a directory boundary. Leaf preserves drive, provider
and UNC share roots. Non-filesystem providers never use home substitution.
Privacy overrides path shortening and does not read identity or location for rendering;
field visibility still applies. This protects the prompt text, not command output,
window titles or other applications.

## Uninstall and reset

Double-click `Remove-ColoredPrompt.cmd`, or run
`./Set-ColoredPrompt.ps1 -Action Uninstall`. Only a recognized managed block is
removed; later unrelated edits and backups remain. Appended boundary newlines remain.
Old whole-profile backups are never restored automatically. Reopen the console to
stop using an already loaded prompt. To reset settings deliberately, uninstall and
then reinstall from an unedited `Prompt.ps1`.

## Validation

Run the focused fixture suite in each installed target shell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Acceptance.ps1
pwsh.exe -NoProfile -File .\tests\Acceptance.ps1
```

Tests edit randomly named temporary profile fixtures, never the live profiles.
Examples and fixed test inputs use synthetic identities and paths. Tests cover
rendering, captured color calls, all field combinations, privacy/plain output,
path boundaries, upgrades, rejected edits, backups and byte preservation.
The future-major fallback check supplies a mocked version; runtime label checks use
the executing shell's actual version. Captured rendering calls are color evidence,
not a visual claim about a terminal's theme. Fixture dot-sourcing verifies installed
code loading; it does not establish automatic loading from real user profiles.

For explicit temporary or custom targets, use the PowerShell-only array parameter
`-ProfilePaths @($fixture1, $fixture2)`. CMD can forward a single target with
`-ProfilePaths "<temporary profile path>"`. Never direct a test at a live profile.
Set `COLORED_PROMPT_NO_PAUSE=1` in a test process to suppress the CMD launcher's pause.
Store runtime evidence and test output outside this source directory.

No license has been selected for this project.
