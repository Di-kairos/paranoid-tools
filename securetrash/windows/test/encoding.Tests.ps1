# Pester 5: every .ps1 with non-ASCII must start with a UTF-8 BOM.
#
# Windows PowerShell 5.1 — the stock Windows shell — reads a BOM-less .ps1 in the system
# ANSI codepage (CP1251 on Russian Windows). Cyrillic in the source turns into
# mojibake, quotes and brackets inside strings break, and the script dies with a ParserError
# before the first command. PowerShell 7 reads UTF-8 by default and so never sees the problem —
# CI stayed green until a live user ran `securetrash check` on their machine and got
# "Unexpected token 'РїРѕРґ'" instead of a working tool.
#
# Both hosts read the BOM, so a single check covers every file in the repository.

Describe 'ps1 encoding' {
    It 'every .ps1 with non-ASCII bytes starts with a UTF-8 BOM' {
        # Join-Path with three arguments is PS7-only; in Windows PowerShell 5.1 it has
        # exactly two positional parameters, and a third kills the test with a ParameterBindingException.
        $root = Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')
        $bad = @()
        # foreach, not ForEach-Object: the latter runs in a child scope,
        # and `$bad +=` inside it would be lost along with the test result.
        foreach ($file in (Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File)) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
            if ($hasBom) { continue }
            foreach ($b in $bytes) {
                if ($b -gt 0x7F) { $bad += $file.FullName; break }
            }
        }
        ($bad -join "`n") | Should -BeExactly ''
    }
}
