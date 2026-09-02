@echo off
rem install.cmd - the one command that installs Paranoid Tools on Windows (BETA).
rem
rem It exists so that nothing about the user's shell matters. windows\install.ps1 needs
rem PowerShell 7 and would be refused outright under the default ExecutionPolicy
rem (Restricted); a .cmd is run by cmd.exe from any shell - cmd, Windows PowerShell 5.1
rem or pwsh 7 - and starts pwsh itself with the right flags. Bypass applies to THIS
rem process only: nothing about the machine's policy is changed.
rem
rem Usage (from the clone root):
rem   windows\install.cmd              install/update all five + the launcher
rem   windows\install.cmd -Uninstall   remove them (vaults and notes are untouched)

where pwsh >nul 2>&1
if not errorlevel 1 goto :run

rem winget hands its new PATH to new processes only, so a PowerShell 7 installed minutes
rem ago in this very window is invisible to `where`. Look where winget puts it before
rem telling the user anything is missing.
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "PATH=%ProgramFiles%\PowerShell\7;%PATH%"
    goto :run
)

echo PowerShell 7 was not found. Install it once:
echo     winget install --id Microsoft.PowerShell -e
echo Then run this command again - no need to reopen the window.
exit /b 1

:run
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
exit /b %errorlevel%
