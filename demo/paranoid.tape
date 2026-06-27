# VHS tape для демо лаунчера `paranoid`. Рендер: vhs demo/paranoid.tape
# Изолированный HOME, реальные подписанные CLI из репо-подкаталогов в PATH.
Output demo/demo.gif

Set Shell bash
Set FontSize 17
Set Width 1180
Set Height 800
Set Theme "Dracula"
Set Padding 22
Set TypingSpeed 45ms
Set PlaybackSpeed 1.0

Hide
Type `PROOT="/Volumes/X10 Pro/projects/paranoid-tools"; export PATH="$PROOT:$PROOT/panic:$PROOT/seedsplit:$PROOT/securetrash:$PROOT/ghostdraft:$PROOT/vaultwatch:/opt/homebrew/bin:$PATH"; export HOME=$(mktemp -d); clear`
Enter
Sleep 600ms
Show

Type "# Paranoid Tools — one launcher over five honest CLIs"
Enter
Sleep 1400ms

Type "paranoid"
Enter
Sleep 3500ms

# Пункт 3 — подменю «Сейф»: все операции с контейнером в одном месте
Type "3"
Enter
Sleep 3800ms

# 0 — назад в главное меню
Type "0"
Enter
Sleep 1800ms

# Пункт 1 — живой honest-статус (securetrash check) прямо из дашборда
Type "1"
Enter
Sleep 4500ms

# Enter — назад в меню
Enter
Sleep 2000ms

# 0 — чистый выход
Type "0"
Enter
Sleep 1500ms

Type "# No secrets touched, nothing hidden — it just runs the signed tools"
Enter
Sleep 2500ms
