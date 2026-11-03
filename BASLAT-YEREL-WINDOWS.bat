@echo off
setlocal
cd /d "%~dp0"
title YEMEK TADINDA - Yerel Onizleme

echo.
echo YEMEK TADINDA yerel onizleme baslatiliyor...
echo Tarayici adresi: http://localhost:8080
echo Bu pencereyi kapatmayin; kapatirsaniz yerel sunucu durur.
echo.

where py >nul 2>&1
if not errorlevel 1 (
  start "" http://localhost:8080
  py -m http.server 8080
  goto :eof
)

where python >nul 2>&1
if not errorlevel 1 (
  start "" http://localhost:8080
  python -m http.server 8080
  goto :eof
)

echo Python bulunamadi. Node.js ile gecici yerel sunucu deneniyor...
where node >nul 2>&1
if not errorlevel 1 (
  start "" http://localhost:8080
  npx --yes http-server . -p 8080 -c-1
  goto :eof
)

echo HATA: Python 3 veya Node.js bulunamadi.
echo Python 3 ya da Node.js 18+ kurup bu dosyayi tekrar calistirin.
pause
