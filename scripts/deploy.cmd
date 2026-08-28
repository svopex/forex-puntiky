@echo off
REM Spusti nasazeni strategie i na strojich, kde je zakazane spousteni
REM PowerShell skriptu (ExecutionPolicy Restricted).
REM Pouziti:  deploy.cmd  [-Broker "IC Markets"]  [-NoCompile]
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*
