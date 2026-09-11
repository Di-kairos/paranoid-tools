# Pester — the logic of the system-tray agent (paranoid-tray.ps1). Dot-sourced under ST_NO_MAIN=1:
# defines the functions WITHOUT starting the WinForms loop. WinForms is unavailable on Linux/macOS
# CI, so we test the pure logic: the menu spec (the dynamic vault item by state) and the CLI dispatcher.

BeforeAll {
    $env:ST_NO_MAIN = '1'
    . (Join-Path $PSScriptRoot '..\paranoid-tray.ps1')
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}
AfterAll { Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue }

Describe 'Get-PtMenuSpec — структура меню' {
    It 'содержит ключевые действия (status / panic / empty / destroy / launcher / quit)' {
        $labels = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en').Label -join '|'
        $labels | Should -Match 'Status'
        $labels | Should -Match 'PANIC'
        $labels | Should -Match 'Empty'
        $labels | Should -Match 'Destroy'
        $labels | Should -Match 'launcher'
        $labels | Should -Match 'Quit'
    }
    It 'пункт сейфа: closed → Open the vault / securetrash vault open' {
        $vault = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en')[6]
        $vault.Label   | Should -Be (Get-PtL -Key 'vault_open' -Lang 'en')
        $vault.Command | Should -Be 'securetrash vault open'
    }
    It 'пункт сейфа: open → Close the vault / securetrash vault close' {
        $vault = (Get-PtMenuSpec -VaultState 'open' -Lang 'en')[6]
        $vault.Label   | Should -Be (Get-PtL -Key 'vault_close' -Lang 'en')
        $vault.Command | Should -Be 'securetrash vault close'
    }
    It 'пункт сейфа: none → Create a vault / securetrash vault create' {
        $vault = (Get-PtMenuSpec -VaultState 'none' -Lang 'en')[6]
        $vault.Label   | Should -Be (Get-PtL -Key 'vault_create' -Lang 'en')
        $vault.Command | Should -Be 'securetrash vault create'
    }
    It 'пункт сейфа: unknown → спросить securetrash, а не гадать действием' {
        $spec = Get-PtMenuSpec -VaultState 'unknown' -Lang 'en'
        $spec[6].Label   | Should -Be (Get-PtL -Key 'vault_ask' -Lang 'en')
        $spec[6].Command | Should -Be 'securetrash vault status'   # read-only, changes nothing
        # No irreversible actions are offered on top of an unknown state.
        ($spec | Where-Object { $_.Label -match 'Empty' }).Enabled   | Should -BeFalse
        ($spec | Where-Object { $_.Label -match 'Destroy' }).Enabled | Should -BeFalse
        # And the header calls the state by its name, not "closed".
        $spec[0].Label | Should -Match 'unknown'
    }
    It 'empty = securetrash vault reset (crypto-shred)' {
        $empty = (Get-PtMenuSpec -VaultState 'open' -Lang 'en') | Where-Object { $_.Label -match 'Empty' }
        $empty.Command | Should -Be 'securetrash vault reset'
    }
    It 'Empty/Destroy enabled когда сейф есть (open|closed), disabled при none (P2-7)' {
        foreach ($st in 'open', 'closed') {
            $spec = Get-PtMenuSpec -VaultState $st -Lang 'en'
            ($spec | Where-Object { $_.Label -match 'Empty'   }).Enabled | Should -BeTrue
            ($spec | Where-Object { $_.Label -match 'Destroy' }).Enabled | Should -BeTrue
        }
        $none = Get-PtMenuSpec -VaultState 'none' -Lang 'en'
        ($none | Where-Object { $_.Label -match 'Empty'   }).Enabled | Should -BeFalse
        ($none | Where-Object { $_.Label -match 'Destroy' }).Enabled | Should -BeFalse
    }
    It 'содержит пункт автостарта (Start at login / __autostart__)' {
        # Пунктов автостарта теперь два — обычный и с правами; матчим по команде, а не по слову
        # в подписи, иначе фильтр ловит оба и сравнение уходит в массив.
        $auto = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en') | Where-Object { $_.Command -eq '__autostart__' }
        @($auto).Count | Should -Be 1
        $auto.Label | Should -Match 'Start at login'
    }

    It 'содержит отдельный пункт автостарта с правами (__autostart_admin__)' {
        # Отдельный пункт, а не третье состояние первого: он меняет модель безопасности машины,
        # такой переключатель выбирают осознанно, а не доклацывают по той же строке.
        $adm = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en') | Where-Object { $_.Command -eq '__autostart_admin__' }
        @($adm).Count | Should -Be 1
        $adm.Label | Should -Match 'admin rights'
        $adm.Label | Should -Match 'no UAC'
    }
    It 'содержит пункт настроек (Settings / __settings__)' {
        $set = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en') | Where-Object { $_.Label -match 'Settings' }
        $set.Command | Should -Be '__settings__'
    }
    It 'пункт сейфа остаётся на индексе 6 после добавления статус-заголовков/автостарта/настроек' {
        (Get-PtMenuSpec -VaultState 'closed' -Lang 'en')[6].Command | Should -Be 'securetrash vault open'
    }
    It 'первые два пункта — disabled статус-заголовки Vault/BitLocker (честность, P1)' {
        $spec = Get-PtMenuSpec -VaultState 'open' -Lang 'en' -FvOn $false
        $spec[0].Enabled | Should -BeFalse
        $spec[0].Label   | Should -Match ([regex]::Escape((Get-PtL -Key 'vault_label' -Lang 'en')))
        $spec[0].Label   | Should -Match ([regex]::Escape((Get-PtL -Key 'vault_open_risk' -Lang 'en')))
        $spec[1].Enabled | Should -BeFalse
        $spec[1].Label   | Should -Match ([regex]::Escape((Get-PtL -Key 'fv_label' -Lang 'en')))
        $spec[1].Label   | Should -Match ([regex]::Escape((Get-PtL -Key 'fv_off' -Lang 'en')))
    }
    It 'BitLocker-заголовок честно отражает FvOn=true' {
        $spec = Get-PtMenuSpec -VaultState 'closed' -Lang 'en' -FvOn $true
        $spec[1].Label | Should -Match ([regex]::Escape((Get-PtL -Key 'fv_on' -Lang 'en')))
    }
}

Describe 'Get-PtMenuSpec — инструменты в трее (s48)' {
    # До s48 в меню трея были только сейф и паника: блокнот, доли и охрана сейфа жили в консольном
    # лаунчере, и человек, открывший меню «найти блокнот», находил только «Открыть полный лаунчер».
    It 'блокнот: подменю ghostdraft с заметкой и просмотром текста' {
        $n = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en') | Where-Object { $_.Label -eq (Get-PtL -Key 'notepad_menu' -Lang 'en') }
        @($n).Count | Should -Be 1
        $n.Children.Command | Should -Be @('ghostdraft new --clipboard', 'ghostdraft pipe')
    }
    It 'секреты: подменю seedsplit с разбить/собрать' {
        $n = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en') | Where-Object { $_.Label -eq (Get-PtL -Key 'secrets_menu' -Lang 'en') }
        $n.Children.Command | Should -Be @('seedsplit split', 'seedsplit combine')
    }
    It 'охрана сейфа видна и на закрытом сейфе, но disabled и говорит, что нужно' {
        foreach ($st in 'closed', 'none', 'unknown') {
            $vw = (Get-PtMenuSpec -VaultState $st -Lang 'en')[9]
            $vw.Label   | Should -Be (Get-PtL -Key 'vw_needs_open' -Lang 'en')
            $vw.Enabled | Should -BeFalse
        }
    }
    It 'открытый сейф без охраны: подменю TTL, том в команде, кавычка экранирована' {
        $vw = (Get-PtMenuSpec -VaultState 'open' -Lang 'en' -Mount "E:\it's" -Watching $false)[9]
        $vw.Label | Should -Be (Get-PtL -Key 'vw_start' -Lang 'en')
        $vw.Children.Command | Should -Be @(
            "vaultwatch start --ttl 30m 'E:\it''s'", "vaultwatch start --ttl 1h 'E:\it''s'",
            "vaultwatch start --ttl 2h 'E:\it''s'", "vaultwatch start --ttl 4h 'E:\it''s'",
            "vaultwatch start 'E:\it''s'")
    }
    It 'открытый сейф под охраной: один пункт снять охрану' {
        $vw = (Get-PtMenuSpec -VaultState 'open' -Lang 'en' -Mount 'E:\' -Watching $true)[9]
        $vw.Command | Should -Be "vaultwatch stop 'E:\'"
    }
    It 'vaultwatch start/stop идут через UAC, как в лаунчере; status — нет' {
        Test-PtNeedsAdmin "vaultwatch start --ttl 1h 'E:\'" | Should -BeTrue
        Test-PtNeedsAdmin "vaultwatch stop 'E:\'" | Should -BeTrue
        Test-PtNeedsAdmin 'vaultwatch status' | Should -BeFalse
        Test-PtNeedsAdmin 'ghostdraft new --clipboard' | Should -BeFalse
    }
    It 'подписи есть в обоих языках' {
        foreach ($k in 'notepad_menu', 'secrets_menu', 'vw_start', 'ttl_none') {
            (Get-PtL -Key $k -Lang 'ru') | Should -Not -Be $k
            (Get-PtL -Key $k -Lang 'ru') | Should -Not -Be (Get-PtL -Key $k -Lang 'en')
        }
    }
}

Describe 'окно инструмента из трея (s48)' {
    # Раньше: -NoExit, голое `PS C:\...>` в конце и заголовок — путь к pwsh.exe из WindowsApps.
    It 'заголовок называет действие, без метки времени паники' {
        $s = Get-PtToolScript -Command 'panic now --hard --trigger-ms 1757570000000'
        $s | Should -Match ([regex]::Escape("WindowTitle = 'Paranoid Tools - panic now --hard'"))
    }
    It 'в конце окно говорит, как его закрыть, а не бросает в приглашение PowerShell' {
        $s = Get-PtToolScript -Command 'securetrash check'
        $s | Should -Match 'Read-Host'
        $s | Should -Match ([regex]::Escape((Get-PtL -Key 'press_enter_close')))
    }
    It 'кавычка в команде не ломает заголовок' {
        $s = Get-PtToolScript -Command "vaultwatch stop 'E:\it''s'"
        $s | Should -Match ([regex]::Escape("WindowTitle = 'Paranoid Tools - vaultwatch stop ''E:\it''''s'''"))
        $s | Should -Match ([regex]::Escape("; vaultwatch stop 'E:\it''s';"))
    }
    It 'окна, что ждут вставки, говорят, что вставлять и как закончить' {
        # Было: пустое окно с одним курсором (s48).
        (Get-PtToolScript -Command 'seedsplit combine') | Should -Match ([regex]::Escape((Get-PtL -Key 'hint_combine')))
        (Get-PtToolScript -Command 'ghostdraft pipe')   | Should -Match ([regex]::Escape((Get-PtL -Key 'hint_pipe')))
        (Get-PtToolScript -Command 'seedsplit combine') | Should -Match 'Write-Host .*; seedsplit combine;'
        (Get-PtToolScript -Command 'seedsplit split')   | Should -Match ([regex]::Escape((Get-PtL -Key 'hint_split')))
        (Get-PtToolScript -Command 'securetrash check') | Should -Not -Match 'Write-Host'
    }
    It 'лаунчеру паузы не надо — у него свой выход' {
        Get-PtToolScript -Command 'paranoid' | Should -Not -Match 'Read-Host'
    }
    It 'окно стартует без профиля пользователя и без -NoExit' {
        Mock Start-Process { }; Mock Test-PtAdmin { $true }
        Invoke-PtTool -Command 'securetrash check'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains '-NoProfile' -and $ArgumentList -notcontains '-NoExit' }
    }
}

Describe 'иконка на панели задач, а не под ^ (s48)' {
    BeforeEach {
        $script:PtKeys = @(
            [pscustomobject]@{ PSPath = 'k-old'; Promoted = 1 },
            [pscustomobject]@{ PSPath = 'k-new'; Promoted = 0 })
        Mock Get-PtNotifyIconKeys { $script:PtKeys }
        Mock Get-ItemProperty { [pscustomobject]@{ IsPromoted = ($script:PtKeys | Where-Object PSPath -eq $LiteralPath).Promoted } }
        Mock Set-PtIconPromotedKey { ($script:PtKeys | Where-Object PSPath -eq $Path).Promoted = 1 }
    }
    It 'выбор, сделанный раз, переносится на новый ключ после обновления pwsh' {
        Sync-PtIconPromotion | Should -BeTrue
        ($script:PtKeys | Where-Object PSPath -eq 'k-new').Promoted | Should -Be 1
    }
    It 'без выбора пользователя сам ничего не выносит' {
        $script:PtKeys[0].Promoted = 0
        Sync-PtIconPromotion | Should -BeFalse
        Should -Invoke Set-PtIconPromotedKey -Times 0 -Exactly
    }
    It 'кнопка «Показать» выносит и без прежнего выбора' {
        $script:PtKeys[0].Promoted = 0
        Sync-PtIconPromotion -Force | Should -BeTrue
        @($script:PtKeys | Where-Object Promoted -eq 1).Count | Should -Be 2
    }
    It 'чужую иконку с тем же текстом не трогаем — нужен ещё хост pwsh.exe' {
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'paranoid-tray.ps1') -Raw
        $src | Should -Match ([regex]::Escape("InitialTooltip -eq 'Paranoid Tools' -and [string]`$p.ExecutablePath -like '*\pwsh.exe'"))
    }
    It 'ключа ещё нет — честное $false, без исключения' {
        Mock Get-PtNotifyIconKeys { @() }
        Sync-PtIconPromotion -Force | Should -BeFalse
    }
}

Describe 'обработчики меню трея (s48)' {
    BeforeAll { $script:TraySrc = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'paranoid-tray.ps1') -Raw }
    It 'пункты меню не собираются через GetNewClosure' {
        # Замыкание видит только переменные области, где его сделали, — не $notify/$timer/$hkWin/
        # $rebuild трея: Quit не прятал иконку, балуны автозапуска и перерегистрация хоткея после
        # «Сохранить» молча не случались. Один обработчик + Tag видит всё.
        @([regex]::Matches($script:TraySrc, '\.GetNewClosure\(')) | Should -BeNullOrEmpty
        $script:TraySrc | Should -Match '\.Tag = \$cmd'
        $script:TraySrc | Should -Match 'Add_Click\(\$onItemClick\)'
    }
    It 'открытое меню не перестраивается под курсором — ждёт закрытия' {
        $script:TraySrc | Should -Match 'if \(\$menu\.Visible\) \{ \$trayState\.Pending = \$true; return \}'
        $script:TraySrc | Should -Match 'Add_Closed\(\{ param\(\$sender, \$e\) if \(\$trayState\.Pending\) \{ & \$rebuild \} \}\)'
    }
    It 'отказ в правах из меню называется, а не проходит молча' {
        $script:TraySrc | Should -Match "'notif_uac_declined'"
    }
}

Describe 'Get-PtAutostartSpec — спецификация автозапуска' {
    It 'указывает на HKCU Run и запускает сам tray-скрипт через pwsh' {
        $s = Get-PtAutostartSpec
        $s.Path  | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $s.Name  | Should -Be 'ParanoidTray'
        $s.Value | Should -Match 'pwsh'
        $s.Value | Should -Match 'paranoid-tray\.ps1'
        $s.Value | Should -Match '-NoProfile -ExecutionPolicy Bypass'
    }
    It 'Store-сборка pwsh: псевдоним вместо папки пакета с версией (s48)' {
        # Папку Microsoft.PowerShell_7.6.6.0_... следующее обновление из Store удаляет — и автозапуск
        # умер бы молча. Псевдоним в %LOCALAPPDATA% переживает обновления.
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*\Microsoft\WindowsApps\pwsh.exe' }
        $old = $env:LOCALAPPDATA; $env:LOCALAPPDATA = 'C:\Users\u\AppData\Local'
        try {
            Get-PtPwshPath -Resolved 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.6.0_arm64__8wekyb3d8bbwe\pwsh.exe' |
                Should -Be (Join-Path 'C:\Users\u\AppData\Local' 'Microsoft\WindowsApps\pwsh.exe')
            Get-PtPwshPath -Resolved 'C:\Program Files\PowerShell\7\pwsh.exe' | Should -Be 'C:\Program Files\PowerShell\7\pwsh.exe'
        } finally { $env:LOCALAPPDATA = $old }
    }
}

Describe 'Format-PtDuration — формат как у vaultwatch CLI' {
    It '3909s → 1h 5m 9s' { Format-PtDuration 3909 | Should -Be '1h 5m 9s' }
    It '309s → 5m 9s'     { Format-PtDuration 309  | Should -Be '5m 9s' }
    It '0s → 0m 0s'       { Format-PtDuration 0    | Should -Be '0m 0s' }
}

Describe 'Limit-PtTrayText — лимит NotifyIcon.Text (63 на .NET Framework)' {
    It 'короткий текст не трогает' {
        Limit-PtTrayText 'Vault closed' | Should -Be 'Vault closed'
    }
    It 'ровно 63 символа проходит без обрезки' {
        $t = 'x' * 63
        Limit-PtTrayText $t | Should -Be $t
    }
    It 'обрезает длиннее 63 до 63 с многоточием' {
        $out = Limit-PtTrayText ('x' * 70)
        $out.Length | Should -Be 63
        $out | Should -Be (('x' * 62) + [char]0x2026)
    }
    It 'RU worst-case tooltip (открыт + авто-выход) укладывается в лимит' {
        $t = "$(Get-PtL 'tip_open' -Lang 'ru') - $(Get-PtL 'auto_exit_in' -Lang 'ru') $(Format-PtDuration 86399)"
        $t.Length | Should -BeGreaterThan 63   # the scenario really overflows the limit before truncation
        (Limit-PtTrayText $t).Length | Should -BeLessOrEqual 63
    }
}

Describe 'Get-PtVaultwatchSessions — чтение session-файлов vaultwatch' {
    BeforeAll {
        $script:vwDir = Join-Path $TestDrive 'vw-sessions'
        New-Item -ItemType Directory -Path $vwDir -Force | Out-Null
        $env:VW_STATE_DIR = $vwDir
    }
    AfterAll { Remove-Item Env:\VW_STATE_DIR -ErrorAction SilentlyContinue }
    BeforeEach { Get-ChildItem -LiteralPath $vwDir | Remove-Item -Force -ErrorAction SilentlyContinue }

    It 'TTL-сессия: remaining = started + ttl_secs - now' {
        Set-Content -LiteralPath (Join-Path $vwDir '_Volumes_SecretVault') -Value @(
            'mount=/Volumes/SecretVault', 'started=1000', 'ttl_secs=3600', 'ttl_force=0')
        # @() is mandatory: under Windows PowerShell 5.1 a single [pscustomobject] has no
        # automatic .Count property (PS7 has it) — without the wrapper the comparison gets $null.
        $s = @(Get-PtVaultwatchSessions -Now 1900)
        $s.Count        | Should -Be 1
        $s[0].Mount     | Should -Be '/Volumes/SecretVault'
        $s[0].Remaining | Should -Be 2700
    }
    It 'сессия без TTL (ttl_secs=0) → Remaining = $null' {
        Set-Content -LiteralPath (Join-Path $vwDir 's2') -Value @('mount=/Volumes/V', 'started=1000', 'ttl_secs=0')
        (Get-PtVaultwatchSessions -Now 1900)[0].Remaining | Should -BeNullOrEmpty
    }
    It 'истёкший TTL → Remaining = 0 (не отрицательное)' {
        Set-Content -LiteralPath (Join-Path $vwDir 's3') -Value @('mount=/Volumes/V', 'started=1000', 'ttl_secs=100')
        (Get-PtVaultwatchSessions -Now 5000)[0].Remaining | Should -Be 0
    }
    It 'пустой каталог → пусто' {
        (Get-PtVaultwatchSessions -Now 1900).Count | Should -Be 0
    }
    It 'битый файл (нечисловые started/ttl) не валит чтение остальных сессий' {
        # `[int]'garbage'` used to throw → the whole menu/timer rebuild died. Now TryParse
        # swallows it and the valid session is still returned.
        Set-Content -LiteralPath (Join-Path $vwDir 'a_good') -Value @('mount=/Volumes/Good', 'started=1000', 'ttl_secs=3600')
        Set-Content -LiteralPath (Join-Path $vwDir 'b_bad')  -Value @('mount=/Volumes/Bad', 'started=xxx', 'ttl_secs=yyy')
        $s = @(Get-PtVaultwatchSessions -Now 1900)
        ($s | Where-Object { $_.Mount -eq '/Volumes/Good' }).Remaining | Should -Be 2700
        # broken one: started/ttl did not parse → ttl=0 → Remaining null, but no exception
        { Get-PtVaultwatchSessions -Now 1900 } | Should -Not -Throw
    }
    It 'файл, исчезнувший между листингом и чтением, пропускается (race-safe)' {
        Set-Content -LiteralPath (Join-Path $vwDir 'a_good') -Value @('mount=/Volumes/Good', 'started=1000', 'ttl_secs=0')
        # A real I/O failure instead of mocking Get-Content: Pester 6 broke the old semantics of a
        # ParameterFilter mock (unmocked calls no longer fall through to the original). An exclusive
        # lock imitates a file gone inaccessible between listing and reading — the same prod path.
        $gonePath = Join-Path $vwDir 'z_gone'
        Set-Content -LiteralPath $gonePath -Value @('mount=/Volumes/Gone', 'started=1', 'ttl_secs=0')
        $lock = [System.IO.File]::Open($gonePath, [System.IO.FileMode]::Open,
                                       [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            { Get-PtVaultwatchSessions -Now 1900 } | Should -Not -Throw
            @(@(Get-PtVaultwatchSessions -Now 1900) | Where-Object { $_.Mount -eq '/Volumes/Good' }).Count | Should -Be 1
        } finally { $lock.Dispose() }
    }
}

Describe 'Normalize-PtMount — скоуп vaultwatch-сессий к текущему тому (P1)' {
    It 'одинаковые пути (без нормализации) совпадают' {
        Normalize-PtMount 'C:\Vault' | Should -Be (Normalize-PtMount 'C:\Vault')
    }
    It 'конечный слэш (обоих стилей) игнорируется' {
        Normalize-PtMount 'C:\Vault\'      | Should -Be (Normalize-PtMount 'C:\Vault')
        Normalize-PtMount '/Volumes/Vault/' | Should -Be (Normalize-PtMount '/Volumes/Vault')
    }
    It 'регистр игнорируется' {
        Normalize-PtMount 'C:\VAULT' | Should -Be (Normalize-PtMount 'c:\vault')
    }
    It 'разные тома не совпадают' {
        Normalize-PtMount 'C:\Vault' | Should -Not -Be (Normalize-PtMount 'D:\Vault')
    }
    It 'пусто/$null → пустая строка' {
        Normalize-PtMount $null | Should -Be ''
        Normalize-PtMount ''    | Should -Be ''
    }
}

Describe 'Test-PtAutostart — честная проверка автозапуска' {
    It 'true только при совпадении с текущей спекой' {
        $spec = Get-PtAutostartSpec
        Mock Get-ItemProperty { [pscustomobject]@{ ParanoidTray = $spec.Value } }
        Test-PtAutostart | Should -BeTrue
    }
    It 'устаревшее значение (скрипт переехал) → false, а не «вкл»' {
        Mock Get-ItemProperty { [pscustomobject]@{ ParanoidTray = 'pwsh -File C:\old\paranoid-tray.ps1' } }
        Test-PtAutostart | Should -BeFalse
    }
    It 'нет записи → false' {
        Mock Get-ItemProperty { $null }
        Test-PtAutostart | Should -BeFalse
    }
}

Describe 'Invoke-PtTool — диспетчер CLI' {
    BeforeEach { Mock Start-Process { }; Mock Test-PtAdmin { $true } }

    It 'запускает реальную команду в новом окне' {
        Invoke-PtTool -Command 'securetrash check'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match '; securetrash check;' }
    }
    It 'разделитель ("") ничего не запускает' {
        Invoke-PtTool -Command ''
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It '__quit__ ничего не запускает (выход обрабатывает сам tray)' {
        Invoke-PtTool -Command '__quit__'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It '__autostart__ ничего не запускает (toggle обрабатывает сам tray)' {
        Invoke-PtTool -Command '__autostart__'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It '__settings__ ничего не запускает (диалог обрабатывает сам tray)' {
        Invoke-PtTool -Command '__settings__'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

# --- s45, живой прогон: отказ в UAC оставлял машину ровно как была, включая незапертый экран.
# Для сейфа это честно (без прав он не откроется), для паники — противоположность смыслу кнопки:
# буфер и блокировка экрана прав не требуют. ---
Describe 'отказ в правах: panic всё равно делает бесправную половину (s45)' {

    BeforeEach {
        Mock Test-PtAdmin { $false }
        $script:PtStarts = @()
        Mock Start-Process {
            $script:PtStarts += ($ArgumentList -join ' ') + $(if ($Verb) { " [verb=$Verb]" } else { '' })
            if ($Verb -eq 'RunAs') { throw 'UAC declined' }
        }
    }

    It 'после отказа запускает panic без прав и возвращает $false' {
        $ok = Invoke-PtTool -Command 'panic now --hard'
        $ok | Should -BeFalse
        ($script:PtStarts | Where-Object { $_ -match 'verb=RunAs' }).Count | Should -Be 1
        ($script:PtStarts | Where-Object { $_ -notmatch 'verb=' -and $_ -match 'panic now' }).Count | Should -Be 1
    }

    It 'для команд сейфа отказ остаётся отказом — без прав им делать нечего' {
        $ok = Invoke-PtTool -Command 'securetrash vault open'
        $ok | Should -BeFalse
        ($script:PtStarts | Where-Object { $_ -notmatch 'verb=' }).Count | Should -Be 0
    }

    It 'уведомление называет сделанную половину, а не «ничего не сделано»' {
        (Get-PtL notif_uac_declined_panic -Lang 'en') | Should -Match 'screen locked'
        (Get-PtL notif_uac_declined_panic -Lang 'en') | Should -Match 'NOT closed'
        (Get-PtL notif_uac_declined_panic -Lang 'ru') | Should -Match 'экран заперт'
    }
}

# --- s45: автозапуск с правами. HKCU Run поднимает трей обычным пользователем, и тогда каждое
# действие сейфа и ПАНИКА стоят диалога UAC. Задача планировщика с RunLevel Highest поднимает
# его уже с правами — хоткей паники срабатывает без диалога. Цена (трей администратором всю
# сессию) названа в самом пункте меню и в уведомлении, а не в сноске. ---
Describe 'автозапуск с правами администратора (s45)' {

    It 'спецификация задачи несёт скрытый запуск текущего пользователя' {
        $spec = Get-PtAutostartTaskSpec
        $spec.TaskName | Should -Be 'ParanoidTools-Tray'
        $spec.Argument | Should -Match 'WindowStyle Hidden'
        $spec.Argument | Should -Match 'ExecutionPolicy Bypass'
        $spec.Argument | Should -Match 'paranoid-tray\.ps1'
        $spec.UserId   | Should -Not -BeNullOrEmpty
    }

    It 'регистрация просит наивысший уровень прав — иначе смысла в ней нет' {
        # Проверяем контракт регистрации по исходнику: Register-ScheduledTask на раннере не
        # выполнить, а потеря -RunLevel Highest молча вернула бы диалог UAC на каждую панику.
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'paranoid-tray.ps1') -Raw
        $src | Should -Match 'New-ScheduledTaskPrincipal[^\n]*-RunLevel Highest'
        $src | Should -Match 'New-ScheduledTaskTrigger -AtLogOn'
        $src | Should -Match 'LogonType Interactive'
    }

    It 'считает автозапуск включённым только если задача совпадает с текущей спецификацией' {
        $spec = Get-PtAutostartTaskSpec
        Mock Get-PtScheduledTask { [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = $spec.Execute; Arguments = $spec.Argument }) } }
        Test-PtAutostartTask | Should -BeTrue
        # Устаревшая задача (скрипт переехал) — это сломанный автозапуск, а не включённый.
        Mock Get-PtScheduledTask { [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = 'pwsh'; Arguments = '-File C:\old\paranoid-tray.ps1' }) } }
        Test-PtAutostartTask | Should -BeFalse
        Mock Get-PtScheduledTask { $null }
        Test-PtAutostartTask | Should -BeFalse
    }

    It 'включение снимает обычный автозапуск — иначе трей стартует дважды' {
        Mock Invoke-PtAutostartAdminElevated { $true }
        Mock Test-PtAutostartTask { $true }
        Mock Disable-PtAutostart { }
        Set-PtAutostartAdmin -On $true | Should -BeTrue
        Should -Invoke Invoke-PtAutostartAdminElevated -Times 1 -Exactly -ParameterFilter { $Action -eq 'install' }
        Should -Invoke Disable-PtAutostart -Times 1 -Exactly
    }

    It 'отказ в правах ничего не меняет и честно возвращает $false' {
        Mock Invoke-PtAutostartAdminElevated { $false }
        Mock Disable-PtAutostart { }
        Set-PtAutostartAdmin -On $true | Should -BeFalse
        Should -Invoke Disable-PtAutostart -Times 0 -Exactly
    }

    It 'выключение снимает задачу и обычный автозапуск не трогает' {
        Mock Invoke-PtAutostartAdminElevated { $true }
        Mock Test-PtAutostartTask { $false }
        Mock Disable-PtAutostart { }
        Set-PtAutostartAdmin -On $false | Should -BeTrue
        Should -Invoke Invoke-PtAutostartAdminElevated -Times 1 -Exactly -ParameterFilter { $Action -eq 'remove' }
        Should -Invoke Disable-PtAutostart -Times 0 -Exactly
    }

    It 'успех — это состояние задачи после, а не «дочерний процесс отработал» (s48)' {
        # Дочерний процесс выходит с 0, даже если Register-ScheduledTask внутри упал.
        Mock Invoke-PtAutostartAdminElevated { $true }
        Mock Disable-PtAutostart { }
        Mock Test-PtAutostartTask { $false }
        Set-PtAutostartAdmin -On $true | Should -BeFalse
        Should -Invoke Disable-PtAutostart -Times 0 -Exactly
        Mock Test-PtAutostartTask { $true }
        Set-PtAutostartAdmin -On $false | Should -BeFalse
    }
    It 'обычный автозапуск не включается, если задачу с правами снять не дали (s48)' {
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'paranoid-tray.ps1') -Raw
        $src | Should -Match '\(Test-PtAutostartTask\) -and -not \(Set-PtAutostartAdmin -On \$false\)'
    }

    It 'сентинелы обрабатываются до запуска трея — элевированная копия не рисует меню' {
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'paranoid-tray.ps1') -Raw
        $src | Should -Match '_autostart_admin_install'
        $src | Should -Match 'Register-PtAutostartTask; exit 0'
        $src | Should -Match 'Unregister-PtAutostartTask; exit 0'
    }

    It 'текст пункта и уведомления называют цену, а не только выгоду' {
        (Get-PtL login_admin_item -Lang 'en') | Should -Match 'no UAC'
        (Get-PtL login_admin_on -Lang 'en')   | Should -Match 'compromised'
        (Get-PtL login_admin_on -Lang 'ru')   | Should -Match 'скомпрометирует'
        (Get-PtL login_admin_off -Lang 'ru')  | Should -Match 'обычным пользователем'
    }
}

# --- Контракт состояний (test/state-contract.json). На вопрос «сейф открыт?» отвечают три
# независимые реализации — bash `_volume_mounted`, приложение macOS и этот трей, — и совпадать
# их заставляет только общая таблица. Идентификаторы правил выписаны буквально: их ищет
# test/state-contract.bats, чтобы новое правило не осталось непокрытым ни в одном адаптере. ---
Describe 'контракт состояний сейфа (s45)' {

    BeforeEach {
        Mock Get-PtVaultMount { 'X:\' }
        Mock Get-PtVaultContainer { 'C:\Users\me\SecureVault.vhdx' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -and $LiteralPath -match 'vhdx' }
        # Проба готовности тома обращается к настоящему диску; остальные правила — про таблицу,
        # поэтому здесь она отвечает «том живой», а её собственные случаи стоят в R5.
        Mock Test-PtMountUsable { $true }
    }

    It 'R1-mounted: точка монтирования есть в таблице томов → open' {
        Mock Get-PtMountPoints { @('C:\', 'X:\') }
        Get-PtVaultState | Should -Be 'open'
    }

    It 'R2-path-exists-not-mounted: тома в таблице нет, контейнер есть → closed' {
        Mock Get-PtMountPoints { @('C:\') }
        Get-PtVaultState | Should -Be 'closed'
    }

    It 'R3-table-unreadable: таблицу прочитать не удалось → unknown, и никогда closed' {
        Mock Get-PtMountPoints { $null }
        Get-PtVaultState | Should -Be 'unknown'
    }

    It 'R4-no-container: контейнера нет → none, а не closed' {
        Mock Get-PtMountPoints { @('C:\') }
        Mock Get-PtVaultContainer { $null }
        Get-PtVaultState | Should -Be 'none'
    }

    It 'R5-attached-not-usable: буква занята чужим томом → не open' {
        Mock Get-PtMountPoints { @('C:\', 'Y:\') }
        Get-PtVaultState | Should -Not -Be 'open'
    }

    # Так это выглядит на живой машине, и прежняя фикстура утверждала обратное: «присоединённый,
    # но не разблокированный VHDX буквы не даёт». Даёт. Запертый BitLocker-том сохраняет и букву,
    # и запись в таблице томов — уходят только данные, — поэтому трей писал «Vault is OPEN» над
    # томом, который панику назад запёрла (живой Windows-прогон, s46).
    It 'R5-attached-not-usable: запертый том остаётся в таблице со своей буквой → не open' {
        Mock Get-PtMountPoints { @('C:\', 'X:\') }
        Mock Test-PtMountUsable { $false }
        Get-PtVaultState | Should -Be 'closed'
    }

    It 'R6-unknown-is-not-an-alarm: unknown не выдаётся за открытый и назван в меню' {
        Mock Get-PtMountPoints { $null }
        Get-PtVaultState | Should -Not -Be 'open'
        $spec = Get-PtMenuSpec -VaultState 'unknown' -Lang 'en' -Elevated $true
        ($spec | ForEach-Object { $_.Command }) -join ' ' | Should -Match 'vault status'
    }
}

# --- s45: собственный секундомер panic стартует уже внутри команды — после нового окна, после
# запуска pwsh и после диалога UAC. Момент нажатия знает только тот, кто запускал, поэтому трей
# передаёт его флагом (аудит 2026-09-07, §16.4). ---
Describe 'Invoke-PtTool — момент нажатия уходит в panic (s45)' {
    BeforeEach { Mock Start-Process { }; Mock Test-PtAdmin { $true } }

    It 'дописывает --trigger-ms к panic now' {
        Invoke-PtTool -Command 'panic now --hard'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -join ' ') -match 'panic now --hard --trigger-ms \d{13}'
        }
    }

    It 'не трогает команду, где момент уже проставлен' {
        Invoke-PtTool -Command 'panic now --hard --trigger-ms 1757000000000'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -join ' ') -notmatch 'trigger-ms.*trigger-ms'
        }
    }

    It 'непаническим командам ничего не дописывает' {
        Invoke-PtTool -Command 'securetrash check'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -join ' ') -notmatch 'trigger-ms'
        }
    }

    It 'спецификация меню остаётся чистой функцией — метки без времени' {
        $a = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en' -Elevated $true | ForEach-Object { $_.Command }) -join '|'
        $b = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en' -Elevated $true | ForEach-Object { $_.Command }) -join '|'
        $a | Should -Be $b
        $a | Should -Not -Match 'trigger-ms'
    }
}

# Аудит 2026-09-07, F02: трей запускал сейф и PANIC обычным Start-Process — без прав команды
# сейфа отказывают, а panic печатает предупреждение над открытым сейфом. Терминальный лаунчер
# уже ходил через UAC; здесь тот же маршрут.
Describe 'Invoke-PtTool — привилегированные команды идут через UAC (F02)' {
    BeforeEach { Mock Start-Process { }; Mock Test-PtAdmin { $false } }

    It 'команды сейфа запрашивают права' {
        foreach ($cmd in @('securetrash vault open', 'securetrash vault close', 'securetrash vault create',
                           'securetrash vault reset', 'securetrash vault destroy')) {
            Test-PtNeedsAdmin $cmd | Should -BeTrue -Because "«$cmd» без прав молча деградирует"
        }
    }
    It 'panic now запрашивает права, а read-only проверка — нет' {
        Test-PtNeedsAdmin 'panic now --hard' | Should -BeTrue
        Test-PtNeedsAdmin 'securetrash check' | Should -BeFalse
        Test-PtNeedsAdmin 'paranoid' | Should -BeFalse
    }
    It 'сейф из трея стартует с -Verb RunAs' {
        Invoke-PtTool -Command 'securetrash vault open' | Should -BeTrue
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $Verb -eq 'RunAs' }
    }
    It 'PANIC из трея стартует с -Verb RunAs' {
        Invoke-PtTool -Command 'panic now --hard'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $Verb -eq 'RunAs' }
    }
    It 'read-only команда идёт обычным запуском, без UAC' {
        Invoke-PtTool -Command 'securetrash check'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $null -eq $Verb }
    }
    It 'уже поднятый трей не просит права второй раз' {
        Mock Test-PtAdmin { $true }
        Invoke-PtTool -Command 'securetrash vault open'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $null -eq $Verb }
    }
    It 'отказ в правах = честный $false, а не «сделано»' {
        # Даже если и бесправный запуск не удался (здесь падает КАЖДЫЙ Start-Process),
        # вызывающий получает $false, а не исключение из обработчика хоткея.
        Mock Start-Process { throw 'UAC declined' }
        Invoke-PtTool -Command 'panic now --hard' | Should -BeFalse
    }
    It 'без прав пункт PANIC честно сообщает про UAC' {
        $panic = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en' -Elevated $false)[4]
        $panic.Label | Should -Match 'admin rights'
        $panic2 = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en' -Elevated $true)[4]
        $panic2.Label | Should -Not -Match 'admin rights'
    }
}

Describe 'Get-PtSettings / Set-PtSettings — хранилище настроек' {
    BeforeAll { $env:PT_SETTINGS_FILE = Join-Path $TestDrive 'settings.json' }
    AfterAll  { Remove-Item Env:\PT_SETTINGS_FILE -ErrorAction SilentlyContinue }
    BeforeEach { Remove-Item -LiteralPath $env:PT_SETTINGS_FILE -ErrorAction SilentlyContinue }

    It 'нет файла → дефолты (VaultVolume пуст, PollSeconds 15)' {
        $s = Get-PtSettings
        $s.VaultVolume | Should -BeNullOrEmpty
        $s.PollSeconds | Should -Be 15
    }
    It 'round-trip Set → Get' {
        Set-PtSettings -VaultVolume '/Volumes/X' -PollSeconds 30
        $s = Get-PtSettings
        $s.VaultVolume | Should -Be '/Volumes/X'
        $s.PollSeconds | Should -Be 30
    }
    It 'PollSeconds ниже 5 зажимается до 5' {
        Set-PtSettings -VaultVolume '' -PollSeconds 2
        (Get-PtSettings).PollSeconds | Should -Be 5
    }
    It 'PollSeconds выше 3600 зажимается до 3600 (иначе NumericUpDown.Value бросает)' {
        Set-PtSettings -VaultVolume '' -PollSeconds 99999
        (Get-PtSettings).PollSeconds | Should -Be 3600
    }
    It 'руками вписанный в JSON oversized PollSeconds читается зажатым' {
        Set-Content -LiteralPath $env:PT_SETTINGS_FILE -Value '{ "VaultVolume": "", "PollSeconds": 100000 }'
        (Get-PtSettings).PollSeconds | Should -Be 3600
    }
    It 'битый JSON → дефолты, без исключения' {
        Set-Content -LiteralPath $env:PT_SETTINGS_FILE -Value '{ not valid json'
        $s = Get-PtSettings
        $s.PollSeconds | Should -Be 15
    }
}

Describe 'Settings v2 (language/hotkey/onboarded)' {
    BeforeEach {
        $env:PT_SETTINGS_FILE = Join-Path $TestDrive 'settings.json'
        # a clean slate for every It: a file could be left over from a neighbouring test in the same TestDrive
        Remove-Item -LiteralPath $env:PT_SETTINGS_FILE -ErrorAction SilentlyContinue
    }
    AfterEach  { Remove-Item Env:\PT_SETTINGS_FILE -ErrorAction SilentlyContinue }
    It 'defaults: system language, hotkey on (ctrl-alt-p), not onboarded' {
        $s = Get-PtSettings
        $s.Language | Should -Be 'system'
        $s.PanicHotkey | Should -Be 'ctrl-alt-p'
        $s.Onboarded | Should -BeFalse
    }
    It 'round-trips new fields' {
        Set-PtSettings -VaultVolume 'X:' -PollSeconds 30 -Language 'ru' -PanicHotkey 'off' -Onboarded $true
        $s = Get-PtSettings
        $s.Language | Should -Be 'ru'
        $s.PanicHotkey | Should -Be 'off'
        $s.Onboarded | Should -BeTrue
    }
    It 'sanitizes garbage language/hotkey to defaults' {
        Set-PtSettings -Language 'xx' -PanicHotkey 'garbage'
        (Get-PtSettings).Language | Should -Be 'system'
        (Get-PtSettings).PanicHotkey | Should -Be 'ctrl-alt-p'
    }
    # s48: «четыре клавиши одновременно, очень быстро, два раза — слишком большая комбинация».
    It 'старый файл с прежним дефолтом переезжает на Ctrl+Alt+P один раз' {
        '{"VaultVolume":"","PollSeconds":15,"Language":"ru","PanicHotkey":"ctrl-alt-shift-p","Onboarded":true}' |
            Set-Content -LiteralPath $env:PT_SETTINGS_FILE
        Update-PtHotkeyDefault | Should -BeTrue
        $s = Get-PtSettings
        $s.PanicHotkey | Should -Be 'ctrl-alt-p'
        $s.Language    | Should -Be 'ru'        # остальное не тронуто
        $s.Onboarded   | Should -BeTrue
        Update-PtHotkeyDefault | Should -BeFalse   # второй раз — нечего
    }
    It 'сознательный выбор Ctrl+Alt+Shift+P после переезда сохраняется' {
        Set-PtSettings -PanicHotkey 'ctrl-alt-shift-p' -Onboarded $true
        Update-PtHotkeyDefault | Should -BeFalse
        (Get-PtSettings).PanicHotkey | Should -Be 'ctrl-alt-shift-p'
    }
    It 'другой выбор (L / выкл) и отсутствие файла не трогаются' {
        '{"PanicHotkey":"ctrl-alt-shift-l"}' | Set-Content -LiteralPath $env:PT_SETTINGS_FILE
        Update-PtHotkeyDefault | Should -BeFalse
        (Get-PtSettings).PanicHotkey | Should -Be 'ctrl-alt-shift-l'
        Remove-Item -LiteralPath $env:PT_SETTINGS_FILE
        Update-PtHotkeyDefault | Should -BeFalse
    }
    It 'подпись в настройках и гиде совпадает с пресетом' {
        Get-PtHotkeyLabel -Preset 'ctrl-alt-p' | Should -Be 'Ctrl+Alt+P'
        Get-PtHotkeyLabel -Preset 'ctrl-alt-shift-l' | Should -Be 'Ctrl+Alt+Shift+L'
        Get-PtHotkeyLabel -Preset 'off' | Should -BeNullOrEmpty
        (Get-PtL -Key 'notif_hotkey_moved' -Lang 'ru') | Should -Match 'Ctrl\+Alt\+Shift\+P'
    }
}

Describe 'Localization' {
    It 'returns en/ru strings and falls back to key' {
        Get-PtL -Key 'vault_closed' -Lang 'en' | Should -Be 'closed'
        Get-PtL -Key 'vault_closed' -Lang 'ru' | Should -Be 'закрыт'
        Get-PtL -Key 'no_such_key' -Lang 'en' | Should -Be 'no_such_key'
    }
    It 'resolves language: override beats system, system falls back to en' {
        Resolve-PtLang -Override 'ru' -SystemLang 'en' | Should -Be 'ru'
        Resolve-PtLang -Override 'system' -SystemLang 'ru' | Should -Be 'ru'
        Resolve-PtLang -Override 'system' -SystemLang 'fr' | Should -Be 'en'
    }
    It 'menu labels escape the ampersand the mnemonic parser would eat' {
        ConvertTo-PtMenuLabel 'PANIC NOW - hide & lock' | Should -Be 'PANIC NOW - hide && lock'
        ConvertTo-PtMenuLabel 'Settings...' | Should -Be 'Settings...'
    }
    It 'every menu-spec label goes through the escaper before it is drawn' {
        # A new item constructed straight from $entry.Label would lose its ampersand again.
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'paranoid-tray.ps1') -Raw
        @([regex]::Matches($src, 'ToolStripMenuItem\(\$entry\.Label\)')) | Should -BeNullOrEmpty
    }
    It 'the rebuild asks everything before it empties the menu' {
        # A probe that waits on WMI pumps messages on this thread, so a second rebuild could run
        # inside the first and every item showed up twice (s47). The WinForms loop cannot run in
        # Pester, so the order is checked in the source: probes, then Clear, then only Adds.
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'paranoid-tray.ps1') -Raw
        $core = $src.Substring($src.IndexOf('$rebuildCore = {'))
        $core = $core.Substring(0, $core.IndexOf('# notifications: the engine decides'))
        $core.IndexOf('$spec = @(Get-PtMenuSpec') | Should -BeGreaterThan -1
        $core.IndexOf('$spec = @(Get-PtMenuSpec') | Should -BeLessThan $core.IndexOf('$menu.Items.Clear()')
        $core | Should -Not -Match 'Checked = \[bool\]\(Test-Pt'
        $core | Should -Not -Match 'foreach \(\$entry in \(Get-PtMenuSpec'
        $src  | Should -Match 'if \(\$trayState\.Rebuilding\) \{ return \}'
    }
    It 'no event handler reads $_ for its event args' {
        # $_ is empty inside a scriptblock attached to a .NET event - the sender and args arrive
        # through param()/$args. `$_.Button` therefore compared $null and the mouse handlers
        # never fired (s47). Caught statically: the runtime says nothing when it happens.
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'paranoid-tray.ps1') -Raw
        @([regex]::Matches($src, '\$_\.(Button|Location|Clicks|X|Y|KeyCode|Delta)')) | Should -BeNullOrEmpty
    }
    It 'tray glyph differs by vault state and uses the icon-font codepoints' {
        # Same glyph for both states would put us back where we started: an icon that says nothing
        # and looks like every other shield in the tray.
        [int](Get-PtTrayGlyph -Open $false) | Should -Be 0xE72E   # Lock
        [int](Get-PtTrayGlyph -Open $true)  | Should -Be 0xE785   # Unlock
    }
    It 'fallback menu is never empty and always offers a way out' {
        # The click that returns nothing is the bug this guards: whatever the rebuild failed on,
        # the strip must still carry items, or Windows draws no menu at all.
        $spec = Get-PtFallbackMenuSpec -Message 'volume table unreadable' -Lang 'en'
        @($spec).Count | Should -BeGreaterThan 1
        ($spec | Where-Object { $_.Command -eq '__quit__' }).Label | Should -Be (Get-PtL -Key 'quit_item' -Lang 'en')
        ($spec | Where-Object { $_.Enabled -eq $false }).Label | Should -Be 'Paranoid Bar: volume table unreadable'
    }
    It 'fallback menu keeps the failure to one bounded line' {
        $long = ('x' * 400) + "`nsecond line"
        $head = (Get-PtFallbackMenuSpec -Message $long -Lang 'en')[0].Label
        $head | Should -Not -Match "`n"
        $head.Length | Should -BeLessOrEqual 134   # 'Paranoid Bar: ' + 120
        (Get-PtFallbackMenuSpec -Message '' -Lang 'en')[0].Label | Should -Be 'Paranoid Bar: menu could not be built'
    }
    It 'has identical key sets for en and ru' {
        ($PtStrings.en.Keys | Sort-Object) -join ',' | Should -Be (($PtStrings.ru.Keys | Sort-Object) -join ',')
    }
}

Describe 'Onboarding' {
    It 'builds checklist lines from readiness' {
        Get-PtChecklistLine -Ok $true -OkKey 'ob_cli_ok' -MissKey 'ob_cli_missing' -Lang 'en' |
            Should -Be ([char]0x2705 + ' ' + 'CLIs installed (all 5 tools + launcher)')
        Get-PtChecklistLine -Ok $false -OkKey 'ob_vault_ok' -MissKey 'ob_vault_missing' -Lang 'ru' |
            Should -Be ([char]0x274C + ' ' + 'Сейф ещё не создан')
    }
    It 'содержит пункт Setup guide (__setup__) в меню' {
        $set = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en') | Where-Object { $_.Command -eq '__setup__' }
        $set.Label | Should -Be (Get-PtL -Key 'setup_item' -Lang 'en')
    }
    It 'Invoke-PtTool игнорирует __setup__ (форму открывает сам tray)' {
        Mock Start-Process { }
        Invoke-PtTool -Command '__setup__'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'Cross-platform l10n parity' {
    It 'ps1 key set equals Swift key set' {
        # Join-Path accepts more than two segments only in PS7; under 5.1 — exactly two.
        $swiftPath = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'macos') 'ParanoidBar.swift'
        $swift = Get-Content -LiteralPath $swiftPath -Raw
        $swiftKeys = [regex]::Matches($swift, '(?m)^\s*"([a-z0-9_]+)":\s*\(') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        # Windows-only keys: UAC is a Windows mechanism, and macOS has no counterpart to mirror
        # (its vault is hdiutil, which needs no elevation). Mirroring them into ParanoidBar.swift
        # would add strings the macOS UI can never show. Everything else stays 1:1.
        # The tool submenus (vaultwatch guard, ghostdraft, seedsplit) are Windows-tray-only for now:
        # ParanoidBar leaves those tools to the terminal launcher.
        $winOnly = @('uac_suffix', 'notif_uac_declined', 'notif_uac_declined_panic',
                     'login_admin_item', 'login_admin_on', 'login_admin_off', 'login_admin_declined',
                     'vw_start', 'vw_stop', 'vw_needs_open', 'ttl_30m', 'ttl_1h', 'ttl_2h', 'ttl_4h', 'ttl_none',
                     'notepad_menu', 'ghost_note', 'ghost_pipe', 'secrets_menu', 'split_item', 'combine_item',
                     'press_enter_close', 'hint_combine', 'hint_pipe', 'hint_split', 'notif_hotkey_moved',
                     'ob_icon_line', 'ob_show_btn', 'ob_howto', 'set_vol_auto')
        foreach ($k in $winOnly) { $swiftKeys | Should -Not -Contain $k }
        $psKeys = $PtStrings.en.Keys | Where-Object { $_ -notin $winOnly } | Sort-Object -Unique
        ($psKeys -join ',') | Should -Be ($swiftKeys -join ',')
    }
    It 'every referenced l10n key exists in the strings table' {
        # A typo in a key (`set_titel`) would silently return the key name in the UI — L/Get-PtL never fail.
        # Caught statically: every literal reference in both sources must exist in the table.
        # Dynamic references (Get-PtL -Key $var / L(okKey...)) are deliberately not matched by the regexes.
        $table = @($PtStrings.en.Keys)
        $psSrc = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'paranoid-tray.ps1') -Raw
        $psRefs = [regex]::Matches($psSrc, "Get-PtL\s+'?([a-z][a-z0-9_]*)'?") |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $psRefs | Should -Not -BeNullOrEmpty
        @($psRefs | Where-Object { $_ -notin $table }) | Should -BeNullOrEmpty
        $swiftPath = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'macos') 'ParanoidBar.swift'
        $swift = Get-Content -LiteralPath $swiftPath -Raw
        # no_such_key is the Swift selftest sentinel for the L() fallback; it must not be in the table.
        $swiftRefs = [regex]::Matches($swift, 'L\("([a-z0-9_]+)"') |
            ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne 'no_such_key' } | Sort-Object -Unique
        $swiftRefs | Should -Not -BeNullOrEmpty
        @($swiftRefs | Where-Object { $_ -notin $table }) | Should -BeNullOrEmpty
    }
}

Describe 'Panic hotkey' {
    It 'double-press fires only within 2s window' {
        Test-PtPanicShouldFire -Now 1000.0 -ArmedAt $null | Should -BeFalse
        Test-PtPanicShouldFire -Now 1001.5 -ArmedAt 1000.0 | Should -BeTrue
        Test-PtPanicShouldFire -Now 1002.0 -ArmedAt 1000.0 | Should -BeTrue
        Test-PtPanicShouldFire -Now 1002.5 -ArmedAt 1000.0 | Should -BeFalse
    }
    It 'clock-jump назад (Now < ArmedAt) не считается мгновенным двойным нажатием (P2)' {
        Test-PtPanicShouldFire -Now 995.0 -ArmedAt 1000.0 | Should -BeFalse
    }
    It 'maps presets to vk codes, off/garbage to $null' {
        (Get-PtHotkeySpec -Preset 'ctrl-alt-shift-p').Vk | Should -Be 0x50
        (Get-PtHotkeySpec -Preset 'ctrl-alt-shift-l').Vk | Should -Be 0x4C
        (Get-PtHotkeySpec -Preset 'ctrl-alt-shift-p').Modifiers | Should -Be 7
        (Get-PtHotkeySpec -Preset 'ctrl-alt-p').Vk | Should -Be 0x50
        (Get-PtHotkeySpec -Preset 'ctrl-alt-p').Modifiers | Should -Be 3   # MOD_CONTROL|MOD_ALT, без Shift
        Get-PtHotkeySpec -Preset 'off' | Should -BeNullOrEmpty
        Get-PtHotkeySpec -Preset 'garbage' | Should -BeNullOrEmpty
    }
    # $env:OS, not $IsWindows: the latter is defined only in PowerShell 6+; under Windows
    # PowerShell 5.1 it is $null — and the test went down the Unix branch right on Windows.
    # Under Windows PowerShell 5.1 the helper will not compile, and it must not: it references
    # System.Windows.Forms.Primitives, and .NET Framework has no such assembly. The tray does not
    # go there either — it answers with an honest "pwsh 7 required" instead of a compiler error.
    It 'compiles the PtHotkeyWindow helper (windows-only)' -Skip:($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -lt 6) {
        # The snippet is taken from the tray itself, not copied here: a copy compiled fine while the
        # real one drifted (it had no ArmedAtSeconds and no ShowWindow by s48).
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'paranoid-tray.ps1') -Raw
        $snippet = [regex]::Match($src, "(?s)-TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
        $snippet | Should -Match 'class PtHotkeyWindow'
        $snippet | Should -Match 'ShowWindow\(Handle, 0\)'
        try {
            Add-Type -ReferencedAssemblies System.Windows.Forms, System.Windows.Forms.Primitives -TypeDefinition $snippet
        } catch {
            if ($_.FullyQualifiedErrorId -notmatch 'TYPE_ALREADY_EXISTS') { throw }
        }
        [PtHotkeyWindow] | Should -Not -BeNullOrEmpty
        $w = New-Object PtHotkeyWindow
        $w.Unregister()   # smoke: the instance + the P/Invoke binding are alive
    }
}

Describe 'Notification engine' {
    It 'fires each event once per episode and resets on close' {
        $s = New-PtNotifyState
        $r = Get-PtNotifyEvents -Open $true -Ttl 90 -HasSessions $true -Now 1000000 -State $s
        $r.Events | Should -Be @('ttl_warn')
        $r2 = Get-PtNotifyEvents -Open $true -Ttl 80 -HasSessions $true -Now 1000001 -State $r.State
        $r2.Events | Should -BeNullOrEmpty
        $r3 = Get-PtNotifyEvents -Open $true -Ttl 0 -HasSessions $true -Now 1000002 -State $r2.State
        $r3.Events | Should -Be @('ttl_expired')
        $r4 = Get-PtNotifyEvents -Open $false -Ttl $null -HasSessions $false -Now 1000003 -State $r3.State
        $r4.State.OpenSince | Should -BeNullOrEmpty
    }
    It 'warns once after 30 min open without vaultwatch' {
        $s = New-PtNotifyState
        $r = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $false -Now 1000000 -State $s
        $r.Events | Should -BeNullOrEmpty
        $r2 = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $false -Now 1001801 -State $r.State
        $r2.Events | Should -Be @('long_open')
        $r3 = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $false -Now 1003600 -State $r2.State
        $r3.Events | Should -BeNullOrEmpty
    }
    It 're-arms ttl warnings when a fresh/renewed session appears (>=120s)' {
        $s = New-PtNotifyState
        $r = Get-PtNotifyEvents -Open $true -Ttl 90 -HasSessions $true -Now 1000000 -State $s
        $r.Events | Should -Be @('ttl_warn')
        $r2 = Get-PtNotifyEvents -Open $true -Ttl 0 -HasSessions $true -Now 1000090 -State $r.State
        $r2.Events | Should -Be @('ttl_expired')
        $r3 = Get-PtNotifyEvents -Open $true -Ttl 300 -HasSessions $true -Now 1000100 -State $r2.State
        $r3.Events | Should -BeNullOrEmpty
        $r4 = Get-PtNotifyEvents -Open $true -Ttl 90 -HasSessions $true -Now 1000300 -State $r3.State
        $r4.Events | Should -Be @('ttl_warn')
    }
    It 'suppresses long_open while a vaultwatch session is alive' {
        $s = New-PtNotifyState
        $r = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $true -Now 1000000 -State $s
        $r2 = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $true -Now 1001801 -State $r.State
        $r2.Events | Should -BeNullOrEmpty
    }
}

# AUDIT_2026-08-03 P2-9: the tray lagged behind the CLI fixes — it did not know about ST_VAULT_PATH
# and judged "everything installed" by three tools out of five, without checking the launcher itself.
Describe 'readiness и путь сейфа — паритет с CLI (P2-9)' {
    AfterEach { Remove-Item Env:\ST_VAULT_PATH -ErrorAction SilentlyContinue }

    It 'Get-PtVaultContainer уважает ST_VAULT_PATH' {
        $env:ST_VAULT_PATH = 'C:\custom\myvault.vhdx'
        Get-PtVaultContainer | Should -Be 'C:\custom\myvault.vhdx'
    }
    It 'Get-PtVaultContainer падает на дефолт, когда ST_VAULT_PATH не задан' {
        Remove-Item Env:\ST_VAULT_PATH -ErrorAction SilentlyContinue
        Get-PtVaultContainer | Should -Match 'SecureVault\.vhdx$'
    }
    It 'состояние сейфа читается по кастомному контейнеру, а не по дефолтному' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pt-" + [System.Guid]::NewGuid().ToString('N') + '.vhdx')
        Set-Content -LiteralPath $tmp -Value 'x'
        try {
            $env:ST_VAULT_PATH = $tmp
            Get-PtVaultState | Should -Be 'closed'
        } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    It 'mount-sidecar читается рядом с кастомным контейнером, а не из профиля (находка Codex)' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pt-" + [System.Guid]::NewGuid().ToString('N') + '.vhdx')
        Set-Content -LiteralPath $tmp -Value 'x'
        Set-Content -LiteralPath "$tmp.mount" -Value 'Q:\' -NoNewline
        try {
            Remove-Item Env:\ST_VAULT_VOLUME -ErrorAction SilentlyContinue
            $env:ST_VAULT_PATH = $tmp
            Get-PtVaultMount | Should -Be 'Q:\'
        } finally {
            Remove-Item -LiteralPath $tmp, "$tmp.mount" -Force -ErrorAction SilentlyContinue
        }
    }
    It 'readiness покрывает все пять тулов и сам лаунчер' {
        $script:PtEcosystemClis.Count | Should -Be 6
        foreach ($t in @('securetrash', 'vaultwatch', 'panic', 'ghostdraft', 'seedsplit', 'paranoid')) {
            $script:PtEcosystemClis | Should -Contain $t
        }
    }
}
