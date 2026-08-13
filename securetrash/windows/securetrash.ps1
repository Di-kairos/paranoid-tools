# securetrash.ps1 — honest secure file deletion on Windows (BETA port).
# Mirror of the macOS version (bash). Baseline: Windows PowerShell 5.1 (no PS7-only syntax).
# IMPORTANT: the port is marked BETA — logic is tested via Pester, BitLocker/VHDX/VeraCrypt
# behavior is NOT verified on real hardware.

$VERSION = '0.5.7'

# --- language detection ---
# Output language selection. English by default. Russian — if ST_LANG starts
# with 'ru' OR $PSUICulture starts with 'ru'. The result is fixed once.
# A pre-set ST_LOCALE is respected (the host — launcher/GUI — may override it).
function Get-StLocale {
    $want = $env:ST_LANG
    if ($want) {
        if ($want -match '^(?i)ru') { return 'ru' } else { return 'en' }
    }
    if ($PSUICulture -and ($PSUICulture -match '^(?i)ru')) { return 'ru' }
    return 'en'
}
$script:ST_LOCALE = if ($env:ST_LOCALE) { $env:ST_LOCALE } else { Get-StLocale }

# --- i18n strings ---
# Message hashtable, key "<locale>:<key>". Dynamic values go through -f in T().
$script:Messages = @{
    'en:beta_banner'        = 'BETA: Windows port. Logic tested via Pester; BitLocker/VHDX/VeraCrypt behavior NOT validated on real hardware.'
    'ru:beta_banner'        = 'BETA: порт под Windows. Логика проверена через Pester; поведение BitLocker/VHDX/VeraCrypt на реальном железе НЕ проверено.'

    'en:confirm_suffix'     = '[type yes]'
    'ru:confirm_suffix'     = '[введите yes]'

    'en:usage'              = @'
Usage: securetrash <command> [args]

Commands:
  check                       Audit the environment and give an honest verdict on guarantees
  setup                       Create %USERPROFILE%\SecureTrash and check BitLocker
  empty                       Empty %USERPROFILE%\SecureTrash
  shred <path>...             Delete a file/folder (best-effort; on SSD NOT a guarantee — see check)
  vault create|open|close|reset|destroy|status|destroy-old   Encrypted container (crypto-shred)
  version                     Show the version

Flags:
  --yes                       Skip confirmation prompts (for scripts)
'@
    'ru:usage'              = @'
Usage: securetrash <command> [args]

Commands:
  check                       Аудит окружения и честный вердикт о гарантиях
  setup                       Создать %USERPROFILE%\SecureTrash, проверить BitLocker
  empty                       Опустошить %USERPROFILE%\SecureTrash
  shred <path>...             Удалить файл/папку (best-effort; на SSD НЕ гарантия — см. check)
  vault create|open|close|reset|destroy|status|destroy-old   Зашифрованный контейнер (crypto-shred)
  version                     Показать версию

Flags:
  --yes                       Пропустить подтверждения (для скриптов)
'@

    'en:setup_dir_ready'    = 'Folder ready: {0}'
    'ru:setup_dir_ready'    = 'Папка готова: {0}'

    'en:bl_off_setup'       = 'BitLocker is OFF — turn it on, otherwise deletion on SSD gives no guarantees.'
    'ru:bl_off_setup'       = 'BitLocker ВЫКЛЮЧЕН — включи его, иначе удаление на SSD не даёт гарантий.'

    'en:check_header'       = '=== SecureTrash: environment audit ==='
    'ru:check_header'       = '=== SecureTrash: аудит окружения ==='

    'en:bl_on'              = 'BitLocker: ON — system drive is encrypted, base protection present.'
    'ru:bl_on'              = 'BitLocker: ВКЛЮЧЕН — системный диск зашифрован, базовая защита есть.'

    'en:bl_off_check'       = 'BitLocker is OFF — the main protection is missing! Enable it: Settings -> Privacy & security -> Device encryption / BitLocker.'
    'ru:bl_off_check'       = 'BitLocker ВЫКЛЮЧЕН — главная защита отсутствует! Включи: Параметры -> Конфиденциальность и защита -> Шифрование устройства / BitLocker.'
    'en:bl_unknown_check'   = 'BitLocker: unknown — could not determine status; assume the drive is NOT protected.'
    'ru:bl_unknown_check'   = 'BitLocker: неизвестно — не удалось определить статус; считай, что диск НЕ защищён.'

    'en:disk_ssd'           = '  Disk: SSD.'
    'ru:disk_ssd'           = '  Диск: SSD.'

    'en:ssd_no_guarantee'   = 'Overwriting (cipher /w) on SSD gives NO guarantees (wear leveling, COW, TRIM).'
    'ru:ssd_no_guarantee'   = 'Перезапись (cipher /w) на SSD НЕ даёт гарантий (wear leveling, COW, TRIM).'

    'en:ssd_real_guarantee' = "Real guarantee on SSD: BitLocker + crypto-shred via 'securetrash vault'."
    'ru:ssd_real_guarantee' = "Реальная гарантия на SSD: BitLocker + crypto-shred через 'securetrash vault'."

    'en:disk_hdd'           = '  Disk: HDD.'
    'ru:disk_hdd'           = '  Диск: HDD.'

    'en:disk_unknown'       = '  Disk: type could not be determined.'
    'ru:disk_unknown'       = '  Диск: тип определить не удалось.'

    'en:hdd_effective'      = 'On HDD, overwriting (cipher /w) is best-effort and usually helps — but it is NOT a guarantee (no control over bad/remapped sectors).'
    'ru:hdd_effective'      = 'На HDD перезапись (cipher /w) — best-effort и обычно помогает, но это НЕ гарантия (нет контроля над bad/remapped-секторами).'

    'en:unknown_effective'  = 'Disk type unknown — treat overwriting as NO guarantee (it may be an SSD). Rely on BitLocker + vault.'
    'ru:unknown_effective'  = 'Тип диска неизвестен — считай перезапись БЕЗ гарантии (это может быть SSD). Полагайся на BitLocker + vault.'

    'en:vault_native'       = 'Vault: native BitLocker VHDX available.'
    'ru:vault_native'       = 'Vault: доступен нативный BitLocker VHDX.'

    'en:vault_veracrypt'    = 'Vault: BitLocker unavailable; VeraCrypt is present, but use its GUI (automated VeraCrypt is disabled in BETA — CLI password leaks on argv).'
    'ru:vault_veracrypt'    = 'Vault: BitLocker недоступен; VeraCrypt найден, но используйте его GUI (автоматический VeraCrypt в BETA отключён — пароль CLI утекает в argv).'

    'en:vault_none'         = 'Vault: unavailable — enable BitLocker or install VeraCrypt.'
    'ru:vault_none'         = 'Vault: недоступен — включи BitLocker или поставь VeraCrypt.'

    'en:check_verdict'      = "Verdict: for secrets, use 'securetrash vault' (preventively)."
    'ru:check_verdict'      = "Итог: для секретов используй 'securetrash vault' (превентивно)."

    'en:snap_present'       = 'Volume Shadow Copies: {0}. A shadow copy taken while the file was still outside the vault holds a FULL copy of it, and neither shred nor cipher /w can reach into one. List them with `vssadmin list shadows`, delete with `vssadmin delete shadows /for=C: /oldest` (both need an elevated prompt). Files kept inside the vault are safe from this: a shadow copy captures the container as ciphertext.'
    'ru:snap_present'       = 'Теневых копий (VSS): {0}. Копия, снятая пока файл ещё лежал вне сейфа, хранит его ПОЛНУЮ копию — ни shred, ни cipher /w туда не дотянутся. Посмотреть: `vssadmin list shadows`, удалить: `vssadmin delete shadows /for=C: /oldest` (то и другое — из консоли администратора). На то, что лежит В СЕЙФЕ, это не действует: копия захватывает контейнер шифротекстом.'
    'en:snap_none'          = 'Volume Shadow Copies: none right now. System Protection creates them on its own, so a file left outside the vault can end up inside one later. (File History does not leave shadow copies behind — it keeps its own file copies, a separate channel.) Files created inside the vault are unaffected.'
    'ru:snap_none'          = 'Теневых копий (VSS) сейчас нет. «Защита системы» создаёт их сама, поэтому файл вне сейфа может попасть в копию позже. («История файлов» теневых копий не оставляет — она хранит собственные копии файлов, это отдельный канал.) На созданное внутри сейфа это не влияет.'
    'en:snap_unknown'       = 'Volume Shadow Copies: unknown — reading them needs an elevated prompt. Assume one may hold a copy of anything that was outside the vault.'
    'ru:snap_unknown'       = 'Теневые копии (VSS): неизвестно — чтобы их прочитать, нужна консоль администратора. Считай, что копия того, что лежало вне сейфа, может быть в одной из них.'
    'en:ssd_note'           = 'SSD: overwriting is not a guarantee. Real protection is BitLocker.'
    'ru:ssd_note'           = 'SSD: перезапись не гарантия. Реальная защита — BitLocker.'

    'en:ssd_bl_off_note'    = 'And BitLocker is OFF — data may be recoverable.'
    'ru:ssd_bl_off_note'    = 'И BitLocker ВЫКЛЮЧЕН — данные могут быть восстановимы.'

    'en:hdd_note'           = 'HDD: free-space overwrite attempted (best-effort). On SSD/COW filesystems this is NOT a guarantee — rely on BitLocker + vault.'
    'ru:hdd_note'           = 'HDD: перезапись свободного места выполнена (best-effort). На SSD/COW-ФС это НЕ гарантия — полагайтесь на BitLocker + vault.'

    'en:unknown_note'       = 'Disk type unknown: free-space overwrite is best-effort and NOT a guarantee (could be an SSD) — rely on BitLocker + vault.'
    'ru:unknown_note'       = 'Тип диска неизвестен: перезапись свободного места — best-effort и НЕ гарантия (может быть SSD) — полагайтесь на BitLocker + vault.'

    'en:cipher_wipe_note'   = 'Best-effort: overwriting free space via cipher /w (this can be SLOW). Not a guarantee on SSD/COW filesystems.'
    'ru:cipher_wipe_note'   = 'Best-effort: перезапись свободного места через cipher /w (это может быть МЕДЛЕННО). Не гарантия на SSD/COW-ФС.'

    'en:cipher_failed'      = 'cipher /w failed (exit {0}) — free space was NOT overwritten.'
    'ru:cipher_failed'      = 'cipher /w завершился с ошибкой (код {0}) — свободное место НЕ перезаписано.'

    'en:shred_need_path'    = 'shred: provide a path.'
    'ru:shred_need_path'    = 'shred: укажи путь.'

    'en:not_found'          = 'Not found: {0}'
    'ru:not_found'          = 'Не найдено: {0}'

    'en:shred_confirm'      = 'Permanently delete {0}?'
    'ru:shred_confirm'      = 'Удалить безвозвратно {0}?'

    'en:shred_protected'    = 'Refusing to shred a protected system path: {0}'
    'ru:shred_protected'    = 'Отказ: защищённый системный путь не удаляем: {0}'

    'en:shred_reparse'      = 'Refusing to shred a junction/symlink/reparse-point: {0} — pass the real target path instead.'
    'ru:shred_reparse'      = 'Отказ: {0} — junction/symlink/reparse-point; передай реальный путь к цели вместо ссылки.'

    'en:cancelled'          = 'Cancelled.'
    'ru:cancelled'          = 'Отменено.'

    'en:deleted'            = 'Deleted: {0}'
    'ru:deleted'            = 'Удалено: {0}'

    'en:empty_no_dir'       = "No {0} folder (run 'securetrash setup')."
    'ru:empty_no_dir'       = "Нет папки {0} (запусти 'securetrash setup')."

    'en:empty_already'      = 'Folder is already empty.'
    'ru:empty_already'      = 'Папка уже пуста.'

    'en:empty_confirm'      = 'Empty {0} permanently?'
    'ru:empty_confirm'      = 'Опустошить {0} безвозвратно?'

    'en:emptied'            = 'Folder emptied: {0}'
    'ru:emptied'            = 'Папка опустошена: {0}'

    'en:vault_pass'         = 'Container password'
    'ru:vault_pass'         = 'Пароль контейнера'

    'en:vault_exists'       = 'Container already exists: {0}'
    'ru:vault_exists'       = 'Контейнер уже существует: {0}'

    'en:vault_created'      = 'Container created: {0} (size {1}).'
    'ru:vault_created'      = 'Контейнер создан: {0} (размер {1}).'

    'en:vault_preventive'   = 'Vault protects only what is created/moved INSIDE it. Plaintext that already existed outside is not erased by this — for that you need BitLocker. While mounted, contents can still leak via Windows Search, swap/pagefile, VSS shadow copies or cloud sync.'
    'ru:vault_preventive'   = 'Vault защищает только то, что создано/перемещено ВНУТРЬ. Уже лежавший снаружи plaintext этим не стирается — для него нужен BitLocker. Пока контейнер смонтирован, содержимое может утечь через Windows Search, swap/pagefile, теневые копии VSS или облачную синхронизацию.'

    'en:vault_no_container_open' = "No container. Run 'securetrash vault create' first."
    'ru:vault_no_container_open' = "Нет контейнера. Сначала 'securetrash vault create'."

    'en:vault_mounted'      = 'Mounted: {0}'
    'ru:vault_mounted'      = 'Смонтировано: {0}'
    'en:vault_already_open' = 'Already open: {0}'
    'ru:vault_already_open' = 'Уже открыт: {0}'

    'en:vault_detach_fail'  = 'Could not unmount (not open?).'
    'ru:vault_detach_fail'  = 'Не удалось размонтировать (не открыт?).'

    'en:vault_hook_failed'  = 'vault {0} hook failed (ignored)'
    'ru:vault_hook_failed'  = 'хук vault {0} завершился с ошибкой (игнорирую)'

    'en:vault_reveal_failed' = 'could not open the volume in Explorer (ignored)'
    'ru:vault_reveal_failed' = 'не удалось открыть том в Explorer (игнорирую)'

    'en:vault_closed'       = 'Unmounted — data is encrypted at rest again. Note: copies that leaked while mounted (swap/pagefile, VSS, Search index, cloud sync) are NOT covered by this.'
    'ru:vault_closed'       = 'Размонтировано — данные снова зашифрованы на диске. Внимание: копии, утёкшие пока контейнер был смонтирован (swap/pagefile, VSS, индекс Search, облако), этим НЕ покрываются.'

    'en:vault_no_container' = 'No container: {0}'
    'ru:vault_no_container' = 'Нет контейнера: {0}'

    'en:vault_bad_container' = 'Not a valid vault container (expected an encrypted container file): {0}'
    'ru:vault_bad_container' = 'Невалидный контейнер (ожидается файл зашифрованного контейнера): {0}'

    'en:vault_destroy_confirm' = 'DESTROY the container and everything inside ({0})?'
    'ru:vault_destroy_confirm' = 'УНИЧТОЖИТЬ контейнер и всё внутри ({0})?'

    'en:vault_destroyed'    = 'Container removed (crypto-shred). Recovery now depends on password strength and that no copies/backups/snapshots (VSS, File History, cloud) remain.'
    'ru:vault_destroyed'    = 'Контейнер удалён (crypto-shred). Восстановление теперь зависит от стойкости пароля и того, что не осталось копий/бэкапов/снимков (VSS, История файлов, облако).'

    'en:vault_destroy_busy' = 'Vault is still MOUNTED (or its state could not be determined) and was not unmounted — refusing to delete while the volume may be decrypted and live. Close it first: ''securetrash vault close'', then destroy.'
    'ru:vault_destroy_busy' = 'Контейнер ещё СМОНТИРОВАН (или состояние определить не удалось) и не был размонтирован — не удаляю, пока том может быть расшифрован и активен. Сначала закрой: ''securetrash vault close'', потом destroy.'

    'en:vault_unavailable'  = 'Vault unavailable — enable BitLocker or install VeraCrypt. No silent fake encryption.'
    'ru:vault_unavailable'  = 'Vault недоступен — включи BitLocker или поставь VeraCrypt. Никакого молчаливого "как будто зашифровали".'

    'en:vault_status_open'  = 'Container is OPEN (mounted at {0}).'
    'ru:vault_status_open'  = 'Контейнер ОТКРЫТ (смонтирован: {0}).'

    'en:vault_status_closed' = 'Container exists but is CLOSED (not mounted): {0}'
    'ru:vault_status_closed' = 'Контейнер существует, но ЗАКРЫТ (не смонтирован): {0}'

    'en:vault_status_unknown' = 'Container exists, but its state could NOT be determined (Storage cmdlets unavailable or the image could not be read): {0}. Do not assume it is closed.'
    'ru:vault_status_unknown' = 'Контейнер есть, но состояние определить НЕ удалось (нет Storage-командлетов или образ не читается): {0}. Не считай его закрытым.'

    'en:vault_usage'        = 'vault: provide create|open|close|reset|destroy|status|destroy-old'
    'ru:vault_usage'        = 'vault: укажи create|open|close|reset|destroy|status|destroy-old'
    'en:vault_old_none'     = 'Nothing is set aside: {0} does not exist.'
    'ru:vault_old_none'     = 'Отставленного контейнера нет: {0} не существует.'
    'en:vault_old_confirm'  = 'DESTROY the set-aside container and everything inside ({0})?'
    'ru:vault_old_confirm'  = 'УНИЧТОЖИТЬ отставленный контейнер и всё внутри ({0})?'
    'en:vault_old_destroyed' = 'Set-aside container removed (crypto-shred): {0}.'
    'ru:vault_old_destroyed' = 'Отставленный контейнер удалён (crypto-shred): {0}.'
    'en:vault_create_fail'  = 'Could not create the container ({0}).'
    'ru:vault_create_fail'  = 'Не удалось создать контейнер ({0}).'
    'en:vault_aside_exists' = 'A previous container is still set aside at {0} — an interrupted reset, or your own backup. It holds real data, so it will not be removed automatically. Move or delete it yourself, then run reset again.'
    'ru:vault_aside_exists' = 'Рядом лежит отставленный контейнер {0} — прерванный reset или твой бэкап. В нём реальные данные, автоматически он не удаляется. Убери или удали его сам, затем повтори reset.'
    'en:vault_aside_notice' = 'Note: {0} is on disk — a container set aside by an interrupted reset. Your older data is in there, not in the active vault. Destroy it for good: securetrash vault destroy-old.'
    'ru:vault_aside_notice' = 'Внимание: на диске лежит {0} — контейнер, отставленный прерванным reset. Прежние данные там, а не в активном сейфе. Уничтожить насовсем: securetrash vault destroy-old.'
    'en:vault_reset_rolled_back' = 'Reset rolled back: the previous vault is back in place ({0}). Nothing was destroyed.'
    'ru:vault_reset_rolled_back' = 'Reset откачен: прежний сейф вернулся на место ({0}). Ничего не уничтожено.'
    'en:vault_restore_fail' = 'Could not move the vault back. Your data is NOT lost — it is at {0}. Move it to {1} manually.'
    'ru:vault_restore_fail' = 'Не удалось вернуть сейф на место. Данные НЕ потеряны — они в {0}. Перенеси их в {1} вручную.'
    'en:vault_aside_busy'  = 'The old container at {0} appears to be MOUNTED — refusing to crypto-shred a live decrypted volume. Eject it, then delete it yourself. The new vault is already in place.'
    'ru:vault_aside_busy'  = 'Старый контейнер {0} выглядит СМОНТИРОВАННЫМ — не уничтожаю живой расшифрованный том. Извлеки его и удали сам. Новый сейф уже на месте.'
    'en:vault_aside_left'   = 'The new vault was created, but the old container could NOT be removed: {0} is still on disk and is still decryptable with the old password. Delete it yourself — until then the crypto-shred promise does not hold.'
    'ru:vault_aside_left'   = 'Новый сейф создан, но старый контейнер удалить НЕ удалось: {0} остался на диске и по-прежнему расшифровывается старым паролем. Удали его сам — до этого обещание crypto-shred не выполнено.'
    'en:vault_reset_confirm' = 'RESET the vault — destroy {0} and EVERYTHING inside, then create a fresh empty one?'
    'ru:vault_reset_confirm' = 'СБРОСИТЬ сейф — уничтожить {0} и ВСЁ внутри, затем создать новый пустой?'
    'en:vault_reset_done'   = 'Vault reset — old container crypto-shredded, fresh empty vault created. (Old contents are unrecoverable only if your password was strong and no copies/backups/snapshots (VSS, File History, cloud) remain.)'
    'ru:vault_reset_done'   = 'Сейф сброшен — старый контейнер crypto-shred, создан новый пустой. (Старое невосстановимо только если пароль был стойким и не осталось копий/бэкапов/снимков (VSS, История файлов, облако).)'

    # VeraCrypt: automated creation/mounting is disabled in BETA (the password leaks via argv).
    'en:vault_vc_manual'    = 'VeraCrypt detected, but automated VeraCrypt vault is NOT supported in this BETA: passing the password on the command line would leak it (visible via ps/WMI/ETW). Create and mount the container with the VeraCrypt GUI instead, then move secrets into the mounted drive.'
    'ru:vault_vc_manual'    = 'VeraCrypt найден, но автоматический VeraCrypt-vault в этой BETA НЕ поддерживается: передача пароля в командной строке привела бы к его утечке (виден через ps/WMI/ETW). Создайте и смонтируйте контейнер через GUI VeraCrypt, затем перенесите секреты на смонтированный диск.'

    'en:vault_unlock_prompt' = 'Enter BitLocker password to unlock the vault'
    'ru:vault_unlock_prompt' = 'Введите пароль BitLocker, чтобы разблокировать vault'

    'en:vault_unlock_fail'  = 'BitLocker unlock FAILED — the volume is still locked, contents are not accessible.'
    'ru:vault_unlock_fail'  = 'Разблокировка BitLocker НЕ удалась — том всё ещё заблокирован, содержимое недоступно.'

    'en:diskpart_failed'    = 'diskpart failed (exit {0}).'
    'ru:diskpart_failed'    = 'diskpart завершился с ошибкой (код {0}).'

    'en:bad_size'           = 'Invalid size (must be a positive integer, MB): {0}'
    'ru:bad_size'           = 'Некорректный размер (нужно целое положительное число, МБ): {0}'

    'en:bad_letter'         = 'Invalid drive letter (must be A-Z): {0}'
    'ru:bad_letter'         = 'Некорректная буква диска (нужна A-Z): {0}'

    'en:bad_path'           = 'Unsafe container path (contains quotes or newlines): {0}'
    'ru:bad_path'           = 'Небезопасный путь контейнера (содержит кавычки или переводы строк): {0}'

    'en:no_free_letter'     = 'No free drive letter available (D..Z all in use).'
    'ru:no_free_letter'     = 'Нет свободной буквы диска (D..Z все заняты).'

    'en:unknown_cmd'        = 'Unknown command: {0}'
    'ru:unknown_cmd'        = 'Неизвестная команда: {0}'
}

# T — localized string by key. Dynamics via -f with positional arguments.
# Fallback: if the key is not in the table, return the key itself.
function T {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(ValueFromRemainingArguments = $true)][object[]]$FmtArgs
    )
    $full = "$script:ST_LOCALE`:$Key"
    if ($script:Messages.ContainsKey($full)) {
        $tmpl = $script:Messages[$full]
        if ($FmtArgs -and $FmtArgs.Count -gt 0) { return ($tmpl -f $FmtArgs) }
        return $tmpl
    }
    return $Key
}

# --- output helpers ---
# info → stdout, warn/err → stderr. Same as the bash version (info to stdout, warn/err to &2)
# and the other four ps1 ports. Write-Host won't do here: it writes to the host, so
# `securetrash check > file` and output parsing by the launcher (windows/paranoid.ps1) got nothing.
function Write-StInfo { param([string]$Msg) Write-Output "[ok] $Msg" }
function Write-StWarn { param([string]$Msg) [Console]::Error.WriteLine("[!] $Msg") }
function Write-StErr  { param([string]$Msg) [Console]::Error.WriteLine("[x] $Msg") }

# Finish a command with an exit code. Inside commands we do NOT call exit directly
# (that would kill the Pester runner) — we throw StExit, the dispatcher catches it and exits.
class StExit : System.Exception {
    [int]$Code
    StExit([int]$code) : base("StExit:$code") { $this.Code = $code }
}
function Stop-StCommand {
    param([int]$Code = 1)
    throw [StExit]::new($Code)
}

# The --yes flag (set in Invoke-Main). Confirmation is required by default.
$script:ST_ASSUME_YES_FLAG = $false

# Ask for confirmation. Bypassed by the --yes flag (script scope) or ST_ASSUME_YES=1 (tests).
function Confirm-StAction {
    param([string]$Prompt)
    if ($script:ST_ASSUME_YES_FLAG) { return $true }
    if ($env:ST_ASSUME_YES -eq '1') { return $true }
    $ans = Read-Host "$Prompt $(T 'confirm_suffix')"
    return ($ans -eq 'yes')
}

# --- platform detection (each function wraps an external call for Mock) ---

# Disk kind — tri-state: 'ssd' | 'hdd' | 'unknown' (wrapper for Mock). Honesty over
# guessing (mirror of macOS _disk_kind): an unknown MediaType is NOT treated as HDD — otherwise
# on an SSD with an undeterminable type we would reassure the user "HDD, overwriting helps".
# 'unknown' is read as the worst case (may be an SSD → overwriting is not a guarantee).
function Get-StDiskKind {
    try {
        $disks = Get-PhysicalDisk -ErrorAction Stop
        if (-not $disks) { return 'unknown' }
        $kinds = @($disks | ForEach-Object { $_.MediaType })
        if ($kinds -contains 'SSD') { return 'ssd' }
        if ($kinds -contains 'HDD') { return 'hdd' }
        return 'unknown'   # MediaType empty/Unspecified → honestly unknown
    } catch {
        return 'unknown'
    }
}

# Is BitLocker on for the system drive? ProtectionStatus -eq 'On'.
# try/catch: on Windows Home the cmdlet is absent → $false.
function Get-StBitLockerOn {
    try {
        $v = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        return ($v.ProtectionStatus -eq 'On')
    } catch {
        return $false
    }
}

# Tri-state BitLocker: on / off / unknown. Distinguishes "off" from "could not determine"
# (cmdlet absent on Windows Home / status neither On nor Off), so that `check` does not print
# a false "OFF" when the status is actually unknown. Mirror of macOS `_fv_state` (F5, v0.4.12).
# The boolean Get-StBitLockerOn is untouched — it remains a correct guard on the setup/rm paths.
function Get-StBitLockerState {
    try {
        $v = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        if ($v.ProtectionStatus -eq 'On')  { return 'on' }
        if ($v.ProtectionStatus -eq 'Off') { return 'off' }
        return 'unknown'
    } catch {
        return 'unknown'
    }
}

# Are the BitLocker cmdlets available (for the native VHDX vault path)?
# The presence of Enable-BitLocker = the machine has BitLocker management.
function Get-StBitLockerCapable {
    try {
        $cmd = Get-Command Enable-BitLocker -ErrorAction Stop
        return ($null -ne $cmd)
    } catch {
        return $false
    }
}

# Path to VeraCrypt: on PATH or in the standard Program Files.
function Get-StVeraCryptPath {
    try {
        $cmd = Get-Command VeraCrypt -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    } catch { }
    # On Windows ProgramFiles is always set; guard against null (cross-platform run).
    if ($env:ProgramFiles) {
        $std = Join-Path $env:ProgramFiles 'VeraCrypt\VeraCrypt.exe'
        if (Test-Path $std) { return $std }
    }
    return $null
}

# --- input validation (#3: protection against diskpart injection) ---

# Validate the size: digits only (MB for diskpart), zero is forbidden — `reset 0` would pass
# validation, destroy the vault and fail on recreate (Codex review AUDIT_2026-08-03 P0-1).
function Assert-StValidSize {
    param([string]$Size)
    if ($Size -notmatch '^\d+[bkmgtBKMGT]?$' -or (Convert-StSizeToMb -Size $Size) -le 0) {
        Write-StErr (T 'bad_size' $Size); Stop-StCommand
    }
}

# Size in MB for diskpart. bash accepts hdiutil suffixes (`1g`, `500m`), and a user
# coming from the macOS version or from the GUIDE writes those — ps1 used to just reject them.
# A bare number is read as MB (the historical ps1 format, and what diskpart expects).
# A fractional result is rounded UP: `vault create 1500k` must yield a container, not 1 MB.
function Convert-StSizeToMb {
    param([string]$Size)
    if ($Size -notmatch '^(\d+)([bkmgtBKMGT]?)$') { return 0 }
    # The regex lets through any number of digits. Without this cutoff `vault create 999...9t`
    # would crash the [int64] cast with a raw OverflowException past Write-StErr/Stop-StCommand.
    # 0 = "invalid size" → Assert-StValidSize handles it with the regular error.
    if ($Matches[1].Length -gt 15) { return 0 }
    $n = [double]$Matches[1]
    $mb = switch ($Matches[2].ToLower()) {
        'b' { $n / 1MB }
        'k' { $n / 1KB }
        'g' { $n * 1KB }
        't' { $n * 1MB }
        default { $n }        # '' and 'm' are already megabytes
    }
    return [int64][Math]::Ceiling($mb)
}

# Validate the drive letter: exactly one A-Z.
function Assert-StValidDriveLetter {
    param([string]$DriveLetter)
    if ($DriveLetter -notmatch '^[A-Za-z]$') { Write-StErr (T 'bad_letter' $DriveLetter); Stop-StCommand }
}

# Validate the container path: no CR/LF or double quotes (they break the diskpart script).
function Assert-StValidVaultPath {
    param([string]$Path)
    if ($Path -match '["\r\n]') { Write-StErr (T 'bad_path' $Path); Stop-StCommand }
}

# Pick a FREE drive letter D..Z (the first one not taken by the FileSystem provider).
function Get-StFreeDriveLetter {
    $used = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
              ForEach-Object { $_.Name.ToUpperInvariant() })
    foreach ($c in [char[]]([char]'D'..[char]'Z')) {
        if ($used -notcontains "$c") { return "$c" }
    }
    Write-StErr (T 'no_free_letter'); Stop-StCommand
}

# --- vault external-call wrappers (for Mock in Pester) ---
# TODO: long-term, replace diskpart with the native cmdlets New-VHD / Mount-DiskImage
#       (they need no text-script generation and are more injection-resistant).

# Create a BitLocker-protected VHDX. Wrapper over diskpart + Enable-BitLocker.
# $Size/$DriveLetter/$Path must be validated by the caller (#3).
function New-StBitLockerVault {
    param(
        [string]$Path,
        [string]$Size,
        [System.Security.SecureString]$Password,
        [string]$DriveLetter = 'V'
    )
    # diskpart script: create vdisk, attach, partition, format NTFS, assign.
    $script = @"
create vdisk file="$Path" maximum=$Size type=expandable
select vdisk file="$Path"
attach vdisk
create partition primary
format fs=ntfs quick label=SecretVault
assign letter=$DriveLetter
"@
    Invoke-StDiskpart -Script $script
    Enable-BitLocker -MountPoint "$($DriveLetter):" -PasswordProtector -Password $Password -EncryptionMethod Aes256 -ErrorAction Stop | Out-Null
}

# Run diskpart with a script (wrapper for Mock). We check the exit code (#3).
function Invoke-StDiskpart {
    param([string]$Script)
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tmp -Value $Script -Encoding ASCII
        & diskpart /s $tmp | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-StErr (T 'diskpart_failed' $LASTEXITCODE); Stop-StCommand }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# Best-effort free-space overwrite on the target's drive root (#1a).
# cipher /w gives NO guarantees on SSD/COW; just a call wrapper + Mock.
function Invoke-StCipherWipe { param([string]$DriveRoot) & cipher /w:$DriveRoot | Out-Null }

# Unlock a BitLocker volume and check the status (#9). Wrapper for Mock.
function Unlock-StBitLockerVault {
    param([string]$MountPoint, [System.Security.SecureString]$Password)
    Unlock-BitLocker -MountPoint $MountPoint -Password $Password -ErrorAction Stop | Out-Null
    $v = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    return ($v.LockStatus -eq 'Unlocked')
}

# State of the BitLocker/vhdx container — tri-state (wrapper for Mock). Prints one of:
#   'mounted'   — vhdx attached (the volume may be decrypted and live);
#   'unmounted' — vhdx definitely NOT attached;
#   'unknown'   — could not determine (no Get-DiskImage / error / non-Windows run).
# Critical for destroy: on 'unknown' we must not delete blindly (fail-closed) — otherwise
# uncertainty would be read as "not mounted" and we would wipe a live volume.
function Get-StVaultState {
    param([string]$Path)
    try {
        $img = Get-DiskImage -ImagePath $Path -ErrorAction Stop
        if ($null -eq $img) { return 'unknown' }
        if ($img.Attached) { return 'mounted' } else { return 'unmounted' }
    } catch {
        return 'unknown'
    }
}

# Current root of the mounted VHDX (e.g. 'D:\'); $null if it could not be determined
# (no Storage module / no letter). Wrapper for Mock.
function Get-StMountedVaultRoot {
    param([string]$Path)
    try {
        $part = Get-DiskImage -ImagePath $Path -ErrorAction Stop | Get-Disk -ErrorAction Stop |
                Get-Partition -ErrorAction Stop | Where-Object DriveLetter | Select-Object -First 1
        if ($part -and $part.DriveLetter) { return "$($part.DriveLetter):\" }
    } catch { }
    return $null
}

# Unmount/detach the container (wrapper for Mock).
function Dismount-StVault {
    param([string]$Path)
    $script = @"
select vdisk file="$Path"
detach vdisk
"@
    Invoke-StDiskpart -Script $script
}

# Delete the container file = crypto-shred (wrapper for Mock).
function Remove-StVaultContainer {
    param([string]$Path)
    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
}

# --- "set the old container aside" (reset without a data-loss window) ---
# reset must survive a create failure: the old vault moves to <vault>.old, the new one
# is created in the regular place, and only after success is the old one crypto-shredded.
# Mirror of bash (_vault_aside_path / mv). Wrappers — so Pester can mock them.
# IMPORTANT: .old is inserted BEFORE the extension, not appended. Get-DiskImage accepts
# only .vhd/.vhdx/.iso — with the name `SecureVault.vhdx.old` any state check
# would answer with an error, an eternal 'unknown' and a fail-closed refusal, i.e. there
# would be nothing to check or delete the set-aside container with.
function Get-StAsidePath {
    param([string]$VaultPath)
    $ext = [System.IO.Path]::GetExtension($VaultPath)
    if ([string]::IsNullOrEmpty($ext)) { return "$VaultPath.old" }
    $base = $VaultPath.Substring(0, $VaultPath.Length - $ext.Length)
    return "$base.old$ext"
}

# Is there a set-aside container. Deliberately via .NET, not Test-Path: the check runs
# on EVERY vault command, and Test-Path is mocked in tests with narrow -ParameterFilter —
# an extra call would break unrelated tests ("no mock matched the call").
function Test-StAsidePresent {
    param([string]$VaultPath)
    $p = Get-StAsidePath $VaultPath
    return ([System.IO.File]::Exists($p) -or [System.IO.Directory]::Exists($p))
}

function Move-StVaultAside {
    param([string]$VaultPath)
    $aside = Get-StAsidePath $VaultPath
    # An existing .old is the user's DATA, deleting it here is forbidden. The caller
    # must refuse beforehand; the check is duplicated because Move-Item -Force
    # with an existing .old DIRECTORY would put the container INSIDE it and stay silent.
    if (Test-StAsidePresent -VaultPath $VaultPath) { Write-StErr (T 'vault_aside_exists' $aside); Stop-StCommand }
    Move-Item -LiteralPath $VaultPath -Destination $aside -ErrorAction Stop
}

function Restore-StVaultAside {
    param([string]$VaultPath)
    $aside = Get-StAsidePath $VaultPath
    if (-not (Test-StAsidePresent -VaultPath $VaultPath)) { return }
    if ([System.IO.File]::Exists($VaultPath) -or [System.IO.Directory]::Exists($VaultPath)) {
        # The most likely create failure is Enable-BitLocker AFTER diskpart has already
        # attached the vhdx. Such a file is locked: without detach it can't be deleted and the rollback won't pass.
        try { Dismount-StVault -Path $VaultPath } catch { }
        Remove-Item -LiteralPath $VaultPath -Force -Recurse -ErrorAction SilentlyContinue
    }
    # Move-Item -Force into an existing DIRECTORY puts the source INSIDE it and stays silent,
    # so the target must be free: more honest to fail than to "successfully" bury the vault.
    if ([System.IO.File]::Exists($VaultPath) -or [System.IO.Directory]::Exists($VaultPath)) { throw "restore target still present: $VaultPath" }
    Move-Item -LiteralPath $aside -Destination $VaultPath -ErrorAction Stop
}

# Restrict the object's ACL to the current user + SYSTEM/Administrators (#15).
# Wrapper for Mock: on non-Windows / with the API absent we skip silently.
function Set-StPrivateAcl {
    param([string]$Path)
    try {
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $acl = New-Object System.Security.AccessControl.FileSecurity
        }
        $acl.SetAccessRuleProtection($true, $false)  # disable inheritance, drop inherited entries
        $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
        $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
        $prop = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        $ids = @(
            [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
            (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-18'),  # SYSTEM
            (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544') # Administrators
        )
        foreach ($id in $ids) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($id, $rights, $inherit, $prop, $allow)
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
    } catch {
        # ACL is best-effort hardening; unavailable on a non-Windows run (Pester on mac).
    }
}

# --- backend metadata (#10: which backend created the container) ---
# The sidecar file <vault>.backend holds 'bitlocker' or 'veracrypt' (one line).
function Get-StBackendPath { param([string]$VaultPath) return "$VaultPath.backend" }

function Write-StVaultBackend {
    param([string]$VaultPath, [string]$Backend)
    $bp = Get-StBackendPath $VaultPath
    Set-Content -LiteralPath $bp -Value $Backend -Encoding ASCII -NoNewline
    Set-StPrivateAcl -Path $bp
}

# Read the recorded backend; if there is no sidecar — $null (legacy/unknown).
function Read-StVaultBackend {
    param([string]$VaultPath)
    $bp = Get-StBackendPath $VaultPath
    if (Test-Path -LiteralPath $bp) { return (Get-Content -LiteralPath $bp -Raw).Trim() }
    return $null
}

# Does it look like a valid container (not an arbitrary path)? Mirror of bash
# _is_sparsebundle: destroy/reset must not destroy what we did not create
# (e.g. ST_VAULT_PATH pointed at a directory or a foreign file). VHDX starts
# with the magic 'vhdxfile'; a VeraCrypt container is indistinguishable random bytes,
# so only the structural check remains for it (a file, not a directory).
function Test-StVaultContainer {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.PSIsContainer) { return $false }
    if ((Read-StVaultBackend -VaultPath $Path) -eq 'veracrypt') { return $true }
    try {
        # FileShare ReadWrite|Delete: a mounted VHDX is held by the virtual-disk stack —
        # a plain OpenRead would fail and a legitimate destroy would get a false bad_container.
        $fs = [System.IO.FileStream]::new($item.FullName,
            [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
            [System.IO.FileShare]([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            $buf = New-Object byte[] 8
            if ($fs.Read($buf, 0, 8) -lt 8) { return $false }
            return ([System.Text.Encoding]::ASCII.GetString($buf) -eq 'vhdxfile')
        } finally { $fs.Dispose() }
    } catch {
        # The file exists but is unreadable (locked by the mounted stack) — we cannot disprove it,
        # so we let it pass: destroy itself stays fail-closed on state (Get-StVaultState).
        return $true
    }
}

# --- vault lifecycle hooks (ecosystem integration point; mirror of bash ST_HOOK_DIR) ---
# The hook directory matches where `vaultwatch install-hooks` puts post-open.cmd/
# post-close.cmd. Resolved at call time — the env override (ST_HOOK_DIR) works in tests.
function Get-StHookDir {
    if ($env:ST_HOOK_DIR) { return $env:ST_HOOK_DIR }
    return (Join-Path (Get-StHomeDir) '.securetrash\hooks')
}

# Run a vault lifecycle hook (securetrash/CLAUDE.md contract + mirror of bash
# _run_vault_hook): invoked ONLY if the file exists; a hook failure does NOT fail the vault
# operation (warn only) — the integration (vaultwatch/panic) is optional.
function Invoke-StVaultHook {
    param([string]$Event, [string]$Mount)
    $hook = Join-Path (Get-StHookDir) "$Event.cmd"
    if (-not (Test-Path -LiteralPath $hook)) { return }
    try {
        $global:LASTEXITCODE = 0   # reset so a stale code doesn't produce a false warn
        & $hook $Mount | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-StWarn (T 'vault_hook_failed' $Event) }
    } catch {
        Write-StWarn (T 'vault_hook_failed' $Event)
    }
}

# Open the mounted volume in Explorer so the user immediately sees where to put files
# (mirror of macOS `open <mount>`). The volume is ALREADY mounted → reveal is best-effort: an
# Explorer launch error does NOT fail a successful open. Disable: ST_VAULT_NO_REVEAL=1.
function Show-StVaultInExplorer {
    param([string]$Mount)
    if ($env:ST_VAULT_NO_REVEAL -eq '1') { return }
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList $Mount -ErrorAction Stop | Out-Null }
    catch { Write-StWarn (T 'vault_reveal_failed') }
}

# The sidecar <vault>.mount holds the active mount point (drive letter with '\'). Needed because
# Get-StFreeDriveLetter picks the letter dynamically: the close hook and the launcher (paranoid.ps1)
# otherwise don't know the real volume. Written on open, read on close, cleaned on close/destroy.
function Get-StMountPath { param([string]$VaultPath) return "$VaultPath.mount" }

function Write-StVaultMount {
    param([string]$VaultPath, [string]$Mount)
    $mp = Get-StMountPath $VaultPath
    Set-Content -LiteralPath $mp -Value $Mount -Encoding ASCII -NoNewline
    Set-StPrivateAcl -Path $mp
}

function Read-StVaultMount {
    param([string]$VaultPath)
    $mp = Get-StMountPath $VaultPath
    if (Test-Path -LiteralPath $mp) { return (Get-Content -LiteralPath $mp -Raw).Trim() }
    return $null
}

function Remove-StVaultMount {
    param([string]$VaultPath)
    $mp = Get-StMountPath $VaultPath
    if (Test-Path -LiteralPath $mp) { Remove-Item -LiteralPath $mp -Force -ErrorAction SilentlyContinue }
}

# --- paths ---
# Profile base: USERPROFILE on Windows; HOME as fallback (cross-platform Pester run).
function Get-StHomeDir {
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    return (Get-Location).Path
}
function Get-StTrashDir { return (Join-Path (Get-StHomeDir) 'SecureTrash') }
# ST_VAULT_PATH lets a GUI/tray/launcher (paranoid.ps1 reads the same env) point at a
# non-standard container — otherwise destroy/reset/open would silently work on the default
# while the UI shows a custom one (AUDIT_2026-07-03 P0-1). Parity with bash securetrash.
function Get-StVaultPath {
    if ($env:ST_VAULT_PATH) { return $env:ST_VAULT_PATH }
    return (Join-Path (Get-StHomeDir) 'SecureVault.vhdx')
}

# --- commands ---

function Invoke-StVersion {
    Write-Output "securetrash $VERSION (Windows, beta)"
}

# Environment audit: an honest verdict on deletion guarantees.
# Are we running with administrator rights (wrapper for Mock).
function Test-StElevated {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# How many shadow copies (VSS) the system holds — the Windows analog of local APFS snapshots.
# A copy taken while the file still lay outside the vault stores it IN FULL: neither shred
# nor `cipher /w` can reach into it. Wrapper for Mock; CIM unavailability → 'unknown'.
function Get-StSnapshotCount {
    # Without administrator rights the VSS provider returns an EMPTY list, not an error —
    # counting that as "no copies" would mean lying in the most dangerous direction.
    if (-not (Test-StElevated)) { return 'unknown' }
    try {
        # A hung VSS/WMI provider would otherwise stall every shred.
        $shadows = @(Get-CimInstance -ClassName Win32_ShadowCopy -OperationTimeoutSec 10 -ErrorAction Stop)
        return $shadows.Count
    } catch {
        return 'unknown'
    }
}

function Write-StSnapshotNote {
    $n = Get-StSnapshotCount
    if ($n -eq 'unknown') { Write-StWarn (T 'snap_unknown') }
    elseif ($n -eq 0)     { Write-StInfo (T 'snap_none') }
    else                  { Write-StWarn (T 'snap_present' $n) }
}

function Invoke-StCheck {
    Write-Output (T 'beta_banner')
    Write-Output (T 'check_header')

    switch (Get-StBitLockerState) {
        'on'    { Write-StInfo (T 'bl_on') }
        'off'   { Write-StWarn (T 'bl_off_check') }
        default { Write-StWarn (T 'bl_unknown_check') }   # undetermined → conservative, assume unprotected
    }

    switch (Get-StDiskKind) {
        'ssd' {
            Write-Output (T 'disk_ssd')
            Write-StWarn (T 'ssd_no_guarantee')
            Write-StInfo (T 'ssd_real_guarantee')
        }
        'hdd' {
            Write-Output (T 'disk_hdd')
            Write-StInfo (T 'hdd_effective')
        }
        default {
            Write-Output (T 'disk_unknown')
            Write-StWarn (T 'unknown_effective')
        }
    }

    # Vault availability: native BitLocker / VeraCrypt fallback / none.
    if (Get-StBitLockerCapable) {
        Write-StInfo (T 'vault_native')
    } elseif (Get-StVeraCryptPath) {
        Write-StInfo (T 'vault_veracrypt')
    } else {
        Write-StWarn (T 'vault_none')
    }

    Write-StSnapshotNote

    Write-Output ''
    Write-Output (T 'check_verdict')
}

# Environment setup: trash folder, BitLocker warning. Idempotent.
function Invoke-StSetup {
    $trash = Get-StTrashDir
    if (-not (Test-Path -LiteralPath $trash)) {
        New-Item -ItemType Directory -Path $trash -Force | Out-Null
    }
    Set-StPrivateAcl -Path $trash   # #15: restrict access to the trash folder
    Write-StInfo (T 'setup_dir_ready' $trash)
    if (-not (Get-StBitLockerOn)) {
        Write-StWarn (T 'bl_off_setup')
    }
}

# Drive root (e.g. 'C:\') for a given path — the target of cipher /w.
function Get-StDriveRootForPath {
    param([string]$Path)
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetPathRoot($full)
        if ($root) { return $root }
    } catch { }
    return $null
}

# Honest note on guarantees by disk kind.
# Post-shred note: disk kind + shadow copies. Snapshots cut across disk type —
# even where the overwrite is honest, a copy inside a shadow copy survives the deletion.
function Write-StHonestDiskNote {
    $kind = Get-StDiskKind
    if ($kind -eq 'ssd') {
        Write-StWarn (T 'ssd_note')
        if (-not (Get-StBitLockerOn)) { Write-StErr (T 'ssd_bl_off_note') }
    } elseif ($kind -eq 'unknown') {
        Write-StWarn (T 'unknown_note')
    } else {
        Write-StInfo (T 'hdd_note')
    }
    Write-StSnapshotNote
}

# Best-effort overwrite of free space on the roots of affected drives (#1a).
# This is NOT a guarantee (especially SSD/COW) — we warn honestly. cipher /w is slow.
function Invoke-StFreeSpaceWipe {
    param([string[]]$Paths)
    $roots = @($Paths | ForEach-Object { Get-StDriveRootForPath $_ } |
               Where-Object { $_ } | Select-Object -Unique)
    foreach ($root in $roots) {
        Write-StWarn (T 'cipher_wipe_note')
        Invoke-StCipherWipe -DriveRoot $root
        if ($LASTEXITCODE -ne 0) { Write-StWarn (T 'cipher_failed' $LASTEXITCODE) }
    }
}

# Delete a path without following junctions/symlinks/reparse points.
# Remove-Item -Recurse in PS 5.1 traverses junctions and deletes the target directory's contents.
# Solution: recurse ourselves; each ReparsePoint is deleted without -Recurse (the link entry only).
function Remove-StItemSafe {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return }
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        # Delete only the junction/symlink entry, NOT the target.
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        return
    }
    if ($item.PSIsContainer) {
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-StItemSafe -Path $_.FullName
        }
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    } else {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
}

# Protected system path? We refuse to shred drive roots and system trees
# (Windows, ProgramFiles, ProgramData, the Users root, the user's own profile). Children
# of the profile (~\file) and user-temp are allowed. Mirror of macOS _is_protected_path: canon
# path via GetFullPath (resolves .., normalizes separators) + case-insensitive comparison
# (the Windows FS is case-insensitive). GetFullPath does not resolve reparse points — which is
# exactly what we want (the guard checks the path "as given"; reparse points are caught by the
# separate check below) — the guard catches the path as given; acceptable for a local-deletion CLI.
function Test-StProtectedPath {
    param([string]$Path)
    # Failed to parse → fail-closed. On .NET Framework (Windows PowerShell 5.1) paths with
    # an asterisk land here too: GetFullPath throws on `*`/`?` there, while .NET Core (7) doesn't.
    # NTFS won't let such a filename be created anyway, so the refusal blocks no one.
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return $true }
    if (-not $full) { return $true }
    $norm = $full.TrimEnd('\')
    if ($norm -match '^[A-Za-z]:$') { $norm = "$norm\" }   # "C:" → "C:\" (drive root)

    $sysDrive = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd('\') } else { 'C:' }
    $sysRoot  = if ($env:SystemRoot)  { $env:SystemRoot.TrimEnd('\') }  else { "$sysDrive\Windows" }
    $userProf = if ($env:USERPROFILE) { $env:USERPROFILE.TrimEnd('\') } else { '' }

    # Exact matches: system drive root, system trees, the Users root, the profile itself.
    $exact = @("$sysDrive\", $sysRoot, "$sysDrive\Program Files",
               "$sysDrive\Program Files (x86)", "$sysDrive\ProgramData", "$sysDrive\Users")
    if ($userProf) { $exact += $userProf }
    foreach ($e in $exact) { if ($e -and ($norm -ieq $e)) { return $true } }

    # System subtrees — by prefix (but NOT \Users\*: profile children are allowed).
    $prefixes = @($sysRoot, "$sysDrive\Program Files",
                  "$sysDrive\Program Files (x86)", "$sysDrive\ProgramData")
    foreach ($pre in $prefixes) { if ($pre -and ($norm -like "$pre\*")) { return $true } }

    # The root of any drive X:\ (not just the system one).
    if ($norm -match '^[A-Za-z]:\\$') { return $true }
    return $false
}

# Permanently delete the given paths + best-effort wipe + honest note (#1,#7).
function Invoke-StShred {
    param([string[]]$Paths)
    if (-not $Paths -or $Paths.Count -eq 0) {
        Write-StErr (T 'shred_need_path'); Stop-StCommand
    }
    foreach ($p in $Paths) {
        if (-not (Test-Path -LiteralPath $p)) { Write-StErr (T 'not_found' $p); Stop-StCommand }
        if (Test-StProtectedPath $p) { Write-StErr (T 'shred_protected' $p); Stop-StCommand }
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            Write-StErr (T 'shred_reparse' $p); Stop-StCommand
        }
    }
    if (-not (Confirm-StAction (T 'shred_confirm' ($Paths -join ' ')))) {
        Write-StWarn (T 'cancelled'); Stop-StCommand
    }
    foreach ($p in $Paths) {
        Remove-StItemSafe -Path $p
        Write-StInfo (T 'deleted' $p)
    }
    Invoke-StFreeSpaceWipe -Paths $Paths
    Write-StHonestDiskNote
}

# Empty the trash folder while keeping the folder itself (#1,#7).
function Invoke-StEmpty {
    $trash = Get-StTrashDir
    if (-not (Test-Path -LiteralPath $trash)) { Write-StErr (T 'empty_no_dir' $trash); Stop-StCommand }
    $items = Get-ChildItem -LiteralPath $trash -Force -ErrorAction SilentlyContinue
    if (-not $items -or $items.Count -eq 0) { Write-StInfo (T 'empty_already'); return }
    if (-not (Confirm-StAction (T 'empty_confirm' $trash))) {
        Write-StWarn (T 'cancelled'); Stop-StCommand
    }
    # Enumerate the contents and delete via Remove-StItemSafe — junctions are not followed.
    Get-ChildItem -LiteralPath $trash -Force | ForEach-Object {
        Remove-StItemSafe -Path $_.FullName
    }
    Write-StInfo (T 'emptied' $trash)
    Invoke-StFreeSpaceWipe -Paths @($trash)
    Write-StHonestDiskNote
}

# Read the container password as a SecureString (#13: keep the password SecureString
# end-to-end, never materialize plaintext). ST_VAULT_PASS is a TEST-ONLY hook
# (documented as test-only); in production the plain password never goes to argv (#2).
function Get-StVaultPasswordSecure {
    param([string]$Prompt = (T 'vault_pass'))
    # TEST-ONLY hook: ST_VAULT_PASS is used only in Pester/scripts, not in production.
    if ($env:ST_VAULT_PASS) {
        return (ConvertTo-SecureString -String $env:ST_VAULT_PASS -AsPlainText -Force)
    }
    return (Read-Host -AsSecureString $Prompt)
}

# --- shared low-level operations (reused by create/destroy/reset) ---
# Create the container. WITHOUT an existence check — the caller does it (create checks;
# reset calls after destroy, when the container is known to be gone). Size is in MB for diskpart.
function Invoke-StVaultCreateNow {
    param([string]$Size = '1024')
    $vaultPath = Get-StVaultPath
    Assert-StValidVaultPath -Path $vaultPath
    Assert-StValidSize -Size $Size
    if (Get-StBitLockerCapable) {
        # Native: VHDX + Enable-BitLocker. The password is SecureString end-to-end (#13).
        $sec = Get-StVaultPasswordSecure
        $letter = Get-StFreeDriveLetter                 # #3: a free letter, not a hardcoded 'V'
        Assert-StValidDriveLetter -DriveLetter $letter
        # diskpart understands only an MB number: suffixes (1g/500m) are expanded here,
        # the message keeps what the user typed.
        New-StBitLockerVault -Path $vaultPath -Size (Convert-StSizeToMb -Size $Size) -Password $sec -DriveLetter $letter
        Set-StPrivateAcl -Path $vaultPath               # #15: ACL on the container
        Write-StVaultBackend -VaultPath $vaultPath -Backend 'bitlocker'  # #10
        Write-StInfo (T 'vault_created' $vaultPath $Size)
        Write-StWarn (T 'vault_preventive')
    } elseif (Get-StVeraCryptPath) {
        # #2: automated VeraCrypt is disabled (the password would leak via argv). Use the GUI.
        Write-StWarn (T 'vault_vc_manual'); Stop-StCommand
    } else {
        Write-StErr (T 'vault_unavailable'); Stop-StCommand
    }
}
# Container destruction mechanism WITHOUT confirm (the caller does it: destroy and reset
# confirm their own way). fail-closed as on macOS: a BitLocker/vhdx is deleted ONLY on a
# reliable 'unmounted' (mounted → unmount and re-check; unknown → refusal).
# VeraCrypt: the state cannot be determined via Get-DiskImage — Remove with -ErrorAction Stop
# fails on its own if the file is busy (also fail-closed). Cleans up the backend+mount sidecars.
function Assert-StVaultUnmounted {
    param([string]$VaultPath)
    $backend = Read-StVaultBackend -VaultPath $VaultPath
    if ($backend -ne 'veracrypt') {
        $state = Get-StVaultState -Path $VaultPath
        switch ($state) {
            'mounted' {
                Dismount-StVault -Path $VaultPath
                if ((Get-StVaultState -Path $VaultPath) -ne 'unmounted') {
                    Write-StErr (T 'vault_destroy_busy'); Stop-StCommand
                }
            }
            'unmounted' { }
            default { Write-StErr (T 'vault_destroy_busy'); Stop-StCommand }  # unknown → fail-closed
        }
    }
}

function Invoke-StVaultDestroyNow {
    $vaultPath = Get-StVaultPath
    Assert-StVaultUnmounted -VaultPath $vaultPath
    Remove-StVaultContainer -Path $vaultPath
    $bp = Get-StBackendPath $vaultPath
    if (Test-Path -LiteralPath $bp) { Remove-Item -LiteralPath $bp -Force -ErrorAction SilentlyContinue }
    Remove-StVaultMount -VaultPath $vaultPath
    Write-StInfo (T 'vault_destroyed')
}

# Encrypted container management: create|open|close|reset|destroy.
# Backend (#10): create writes the sidecar <vault>.backend; open/close/destroy
# read it and dispatch. The VeraCrypt path (#2) is GUI instructions only;
# the password NEVER goes to argv.
function Invoke-StVault {
    param([string[]]$VaultArgs)
    $sub = if ($VaultArgs -and $VaultArgs.Count -ge 1) { $VaultArgs[0] } else { '' }
    $vaultPath = Get-StVaultPath
    # A surviving .old is the trace of an interrupted reset. The user must learn WHERE their
    # data is: status would otherwise show "vault closed", but it's a different vault (mirror of bash).
    if (Test-StAsidePresent -VaultPath $vaultPath) {
        Write-StWarn (T 'vault_aside_notice' (Get-StAsidePath $vaultPath))
    }

    switch ($sub) {
        'create' {
            if (Test-Path -LiteralPath $vaultPath) { Write-StErr (T 'vault_exists' $vaultPath); Stop-StCommand }
            $size = if ($VaultArgs.Count -ge 2) { $VaultArgs[1] } else { '1024' }  # MB for diskpart
            Invoke-StVaultCreateNow -Size $size
        }
        'open' {
            if (-not (Test-Path -LiteralPath $vaultPath)) { Write-StErr (T 'vault_no_container_open'); Stop-StCommand }
            # Idempotency: already mounted → don't duplicate the attach (AUDIT P2-5, parity with bash).
            if ((Get-StVaultState -Path $vaultPath) -eq 'mounted') {
                # Refresh the mount sidecar: a legacy vault may have been mounted before the
                # sidecar existed (or the write failed) — without it ghostdraft/paranoid can't find
                # the volume's real letter (AUDIT_2026-08-03 P0-3, Codex review). Best-effort.
                try {
                    $curRoot = Get-StMountedVaultRoot -Path $vaultPath
                    if ($curRoot) { Write-StVaultMount -VaultPath $vaultPath -Mount $curRoot }
                } catch { }
                Write-StInfo (T 'vault_already_open' $vaultPath); return
            }
            $backend = Read-StVaultBackend -VaultPath $vaultPath
            # Legacy/unknown sidecar: assume bitlocker only if the cmdlet exists.
            if (-not $backend) { $backend = if (Get-StBitLockerCapable) { 'bitlocker' } else { '' } }

            if ($backend -eq 'veracrypt') {
                # #2/#10: a VeraCrypt container opens only through the GUI.
                Write-StWarn (T 'vault_vc_manual'); Stop-StCommand
            } elseif ($backend -eq 'bitlocker') {
                Assert-StValidVaultPath -Path $vaultPath
                $letter = Get-StFreeDriveLetter
                Assert-StValidDriveLetter -DriveLetter $letter
                # Attach VHDX...
                Invoke-StDiskpart -Script "select vdisk file=`"$vaultPath`"`nattach vdisk`nselect partition 1`nassign letter=$letter"
                $vol = "$($letter):"
                # ...then unlock BitLocker and check the status (#9).
                $sec = Get-StVaultPasswordSecure -Prompt (T 'vault_unlock_prompt')
                if (-not (Unlock-StBitLockerVault -MountPoint $vol -Password $sec)) {
                    Write-StErr (T 'vault_unlock_fail'); Stop-StCommand
                }
                Write-StInfo (T 'vault_mounted' $vol)
                Write-StWarn (T 'vault_preventive')
                # Post-mount actions are best-effort: the volume is ALREADY mounted, so a
                # sidecar/ACL write error or a hook failure must NOT turn a successful open into a
                # failure (mirror of the hook policy: an integration failure = warn, not fatal).
                try {
                    $mountRoot = "$($letter):\"
                    Write-StVaultMount -VaultPath $vaultPath -Mount $mountRoot
                    Invoke-StVaultHook -Event 'post-open' -Mount $mountRoot
                } catch {
                    Write-StWarn (T 'vault_hook_failed' 'post-open')
                }
                # Reveal — after the hook and regardless of its outcome (mirror of the macOS order).
                Show-StVaultInExplorer -Mount "$($letter):\"
            } else {
                Write-StErr (T 'vault_unavailable'); Stop-StCommand
            }
        }
        'close' {
            $backend = Read-StVaultBackend -VaultPath $vaultPath
            if ($backend -eq 'veracrypt') {
                Write-StWarn (T 'vault_vc_manual'); Stop-StCommand
            }
            # Read the real volume BEFORE unmounting (after detach the letter disappears).
            $mount = Read-StVaultMount -VaultPath $vaultPath
            try {
                Dismount-StVault -Path $vaultPath
                Write-StInfo (T 'vault_closed')
                # post-close hook + mount-sidecar cleanup (only after a successful detach).
                if ($mount) { Invoke-StVaultHook -Event 'post-close' -Mount $mount }
                Remove-StVaultMount -VaultPath $vaultPath
            } catch {
                Write-StErr (T 'vault_detach_fail'); Stop-StCommand
            }
        }
        'destroy' {
            # Checked BEFORE the confirm prompt: don't ask about a nonexistent/foreign path
            # (mirror of bash _vault_assert_destroyable).
            if (-not (Test-Path -LiteralPath $vaultPath)) { Write-StErr (T 'vault_no_container' $vaultPath); Stop-StCommand }
            if (-not (Test-StVaultContainer -Path $vaultPath)) { Write-StErr (T 'vault_bad_container' $vaultPath); Stop-StCommand }
            if (-not (Confirm-StAction (T 'vault_destroy_confirm' $vaultPath))) {
                Write-StWarn (T 'cancelled'); Stop-StCommand
            }
            Invoke-StVaultDestroyNow
        }
        'reset' {
            # "Clear the vault, keep the vault itself" with a REAL guarantee: in-place overwrite
            # is best-effort (the same key keeps decrypting the residual blocks). The honest
            # way is a crypto-shred of the container (throw away the key) + create a new empty one
            # (new key → the old is dead). One confirm for the whole operation.
            # The size is validated BEFORE destroy: a typo in the size must not get to destroy
            # the old vault (mirror of bash, AUDIT_2026-07-03 P2-2 / AUDIT_2026-08-03 P0-1).
            $resetSize = if ($VaultArgs.Count -ge 2) { $VaultArgs[1] } else { '1024' }
            Assert-StValidSize -Size $resetSize
            if (-not (Test-Path -LiteralPath $vaultPath)) { Write-StErr (T 'vault_no_container' $vaultPath); Stop-StCommand }
            if (-not (Test-StVaultContainer -Path $vaultPath)) { Write-StErr (T 'vault_bad_container' $vaultPath); Stop-StCommand }
            if (-not (Confirm-StAction (T 'vault_reset_confirm' $vaultPath))) {
                Write-StWarn (T 'cancelled'); Stop-StCommand
            }
            # There must be no window between "the old vault is gone" and "the new one is
            # ready": destroy used to go first, and a create failure (no space, diskpart/BitLocker
            # refusal, cancel at the password prompt) left the user with no vault at all. Now
            # the old container is set aside to <vault>.old, the new one is created in the
            # regular place, and only after success is the old one crypto-shredded. Mirror of bash.
            $aside = Get-StAsidePath $vaultPath
            # A surviving .old is an interrupted reset or the user's manual backup. Silently
            # razing it = destroying the only copy of the data. We refuse.
            if (Test-StAsidePresent -VaultPath $vaultPath) { Write-StErr (T 'vault_aside_exists' $aside); Stop-StCommand }
            Assert-StVaultUnmounted -VaultPath $vaultPath   # only a detached vhdx may be renamed
            Move-StVaultAside -VaultPath $vaultPath
            # finally, not catch: the rollback must run even on a cancel/StExit from inside
            # create, and the original error must not be swallowed in the process.
            $stCreated = $false
            try {
                Invoke-StVaultCreateNow -Size $resetSize
                $stCreated = $true
            } finally {
                if (-not $stCreated) {
                    try {
                        Restore-StVaultAside -VaultPath $vaultPath
                        Write-StWarn (T 'vault_reset_rolled_back' $vaultPath)
                    } catch {
                        Write-StErr (T 'vault_restore_fail' $aside $vaultPath)
                    }
                }
            }
            # While create was running, a volume may have been mounted from .old — shredding
            # blindly is forbidden, it would raze the backing store of a live decrypted volume (mirror of bash).
            if ((Get-StVaultState -Path $aside) -ne 'unmounted') {
                Write-StErr (T 'vault_aside_busy' $aside); Stop-StCommand
            }
            # Only now is the old container destroyed. A failure here is no small thing:
            # a copy decryptable with the old password remains next to the new vault.
            try {
                Remove-StVaultContainer -Path $aside
            } catch {
                Write-StErr (T 'vault_aside_left' $aside); Stop-StCommand
            }
            Remove-StVaultMount -VaultPath $vaultPath
            Write-StInfo (T 'vault_destroyed')
            Write-StInfo (T 'vault_reset_done')
        }
        'destroy-old' {
            # The official way to remove a container set aside by an interrupted reset.
            # A separate command, not part of destroy: the targets differ, and mixing them
            # in one confirmation is a straight road to a miss.
            $oldPath = Get-StAsidePath $vaultPath
            if (-not (Test-StAsidePresent -VaultPath $vaultPath)) {
                Write-StErr (T 'vault_old_none' $oldPath); Stop-StCommand
            }
            if (-not (Test-StVaultContainer -Path $oldPath)) {
                Write-StErr (T 'vault_bad_container' $oldPath); Stop-StCommand
            }
            # Early check — so we don't ask about a volume known to be busy.
            if ((Get-StVaultState -Path $oldPath) -ne 'unmounted') {
                Write-StErr (T 'vault_aside_busy' $oldPath); Stop-StCommand
            }
            if (-not (Confirm-StAction (T 'vault_old_confirm' $oldPath))) {
                Write-StWarn (T 'cancelled'); Stop-StCommand
            }
            # And AGAIN before the deletion: the confirmation waits for input indefinitely,
            # and in that time the container can be mounted. The backing store of a live
            # decrypted volume must not be razed.
            if ((Get-StVaultState -Path $oldPath) -ne 'unmounted') {
                Write-StErr (T 'vault_aside_busy' $oldPath); Stop-StCommand
            }
            Remove-StVaultContainer -Path $oldPath
            Write-StInfo (T 'vault_old_destroyed' $oldPath)
        }
        'status' {
            # Read-only: does the container exist and is it mounted. Mirror of bash `vault status`
            # (no container → error and a non-zero code; otherwise OPEN/CLOSED).
            if (-not (Test-Path -LiteralPath $vaultPath)) { Write-StErr (T 'vault_no_container' $vaultPath); Stop-StCommand }
            $state = Get-StVaultState -Path $vaultPath
            # 'unknown' (no Storage module, Get-DiskImage failed) is NOT the same as "closed".
            # Saying "CLOSED" without having been able to check means lying in the reassuring direction.
            # The divergence from bash is deliberate: hdiutil has no such failure mode.
            if ($state -eq 'unknown') {
                Write-StWarn (T 'vault_status_unknown' $vaultPath)
            } elseif ($state -eq 'mounted') {
                # The real volume, not a guess: the letter is picked dynamically at open.
                $mount = Get-StMountedVaultRoot -Path $vaultPath
                if (-not $mount) { $mount = Read-StVaultMount -VaultPath $vaultPath }
                if (-not $mount) { $mount = $vaultPath }
                Write-StInfo (T 'vault_status_open' $mount)
            } else {
                Write-StInfo (T 'vault_status_closed' $vaultPath)
            }
        }
        default {
            Write-StErr (T 'vault_usage'); Stop-StCommand
        }
    }
}

function Show-StUsage {
    Write-Output (T 'usage')
}

# Subcommand dispatcher. Commands throw StExit on error — we catch and exit.
function Invoke-Main {
    param([string[]]$Argv)
    try {
        # #14: --yes is the global confirmation flag. Cut it from args, set script scope.
        $script:ST_ASSUME_YES_FLAG = $false
        if ($Argv -and ($Argv -contains '--yes')) {
            $script:ST_ASSUME_YES_FLAG = $true
            $Argv = @($Argv | Where-Object { $_ -ne '--yes' })
        }
        $cmd = if ($Argv -and $Argv.Count -ge 1) { $Argv[0] } else { '' }
        if (-not $cmd) { Show-StUsage; exit 1 }
        # The outer @() is mandatory: if-as-expression unwraps a one-element
        # array into a scalar string, and indexing would yield the first CHARACTER, not the argument.
        $rest = @(if ($Argv.Count -ge 2) { $Argv[1..($Argv.Count - 1)] } else { @() })

        # Aliases -v/--version/-h/--help — parity with bash: a user coming from the
        # macOS version or plain habit must not get "Unknown command".
        switch ($cmd) {
            { $_ -in @('version', '-v', '--version') } { Invoke-StVersion; break }
            { $_ -in @('help', '-h', '--help') }       { Show-StUsage; break }
            'check'   { Invoke-StCheck }
            'setup'   { Invoke-StSetup }
            'shred'   { Invoke-StShred -Paths $rest }
            'empty'   { Invoke-StEmpty }
            'vault'   { Invoke-StVault -VaultArgs $rest }
            default {
                Write-StErr (T 'unknown_cmd' $cmd)
                Show-StUsage
                exit 1
            }
        }
    } catch [StExit] {
        exit $_.Exception.Code
    }
}

# --- dot-source guard ---
# On dot-source ($MyInvocation.InvocationName -eq '.') or ST_NO_MAIN=1 the dispatcher
# does NOT run — only the functions are defined (needed for Pester).
if ($MyInvocation.InvocationName -ne '.' -and -not $env:ST_NO_MAIN) {
    Invoke-Main -Argv $args
}
