# VHS tape для демо securetrash. Рендер: vhs demo/securetrash.tape
# Изолированный HOME, реальный hdiutil-цикл vault.
Output demo/demo.gif

Set Shell bash
Set FontSize 17
Set Width 1180
Set Height 760
Set Theme "Dracula"
Set Padding 22
Set TypingSpeed 45ms
Set PlaybackSpeed 1.0

Hide
Type `export HOME=$(mktemp -d); export PATH="/Volumes/X10 Pro/projects/securetrash:/opt/homebrew/bin:$PATH"; clear`
Enter
Sleep 600ms
Show

Type "# SecureTrash — honest secure deletion for macOS"
Enter
Sleep 1200ms

Type "securetrash check"
Enter
Sleep 3500ms

Type "# Real crypto-shred: an encrypted vault"
Enter
Sleep 1000ms

Type "securetrash vault create 20m"
Enter
Sleep 1800ms
Type@90ms "MyStr0ngPass"
Enter
Sleep 4500ms

Type "securetrash vault open"
Enter
Sleep 1200ms
Type@90ms "MyStr0ngPass"
Enter
Sleep 3000ms

Type "echo 'bank PINs, keys, secrets' > /Volumes/SecretVault/secrets.txt"
Enter
Sleep 1200ms
Type "ls /Volumes/SecretVault"
Enter
Sleep 1800ms

Type "securetrash vault close"
Enter
Sleep 2500ms

Type "# destroy = crypto-shred (real on SSD, key is gone)"
Enter
Sleep 1000ms
Type "securetrash vault destroy"
Enter
Sleep 1500ms
Type@90ms "yes"
Enter
Sleep 3500ms
