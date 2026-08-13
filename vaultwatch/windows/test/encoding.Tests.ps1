# Pester 5: каждый .ps1 с не-ASCII обязан начинаться с UTF-8 BOM.
#
# Windows PowerShell 5.1 — штатный шелл Windows — читает .ps1 без BOM в системной
# ANSI-кодировке (CP1251 на русской Windows). Кириллица в исходнике превращается в
# мозаику, кавычки и скобки в строках рвутся, и скрипт падает с ParserError ещё до
# первой команды. PowerShell 7 по умолчанию читает UTF-8 и потому проблему не видит —
# CI был зелёным, пока живой пользователь не запустил `securetrash check` на своей
# машине и не получил «Unexpected token 'РїРѕРґ'» вместо работы.
#
# BOM читают оба хоста, поэтому проверка одна для всех файлов репозитория.

Describe 'ps1 encoding' {
    It 'every .ps1 with non-ASCII bytes starts with a UTF-8 BOM' {
        # Join-Path с тремя аргументами — PS7-only; в Windows PowerShell 5.1 у него
        # ровно два позиционных параметра, и третий валит тест ParameterBindingException.
        $root = Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')
        $bad = @()
        # foreach, а не ForEach-Object: последний исполняется в дочерней области,
        # и `$bad +=` внутри него потерялся бы вместе с результатом теста.
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
