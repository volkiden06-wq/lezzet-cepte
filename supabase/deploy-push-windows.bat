@echo off
setlocal
title LEZZET CEPTE - Supabase Siparis Bildirimini Dagit

cd /d "%~dp0.."

echo.
echo LEZZET CEPTE - Siparis bildirim fonksiyonu
echo ------------------------------------------
echo Bu islem yalnizca Supabase Edge Function dosyasini dagitir.
echo Urunleri, kategorileri veya siparis tablosunu silmez.
echo.

where supabase >nul 2>&1
if errorlevel 1 (
  echo HATA: Supabase CLI bulunamadi.
  echo Once resmi kurulum sayfasindan Supabase CLI kurun:
  echo https://supabase.com/docs/guides/cli/getting-started
  echo Ardindan bu dosyayi tekrar calistirin.
  pause
  exit /b 1
)

echo Supabase hesabi aciliyor...
supabase login
if errorlevel 1 (
  echo HATA: Supabase girisi tamamlanamadi.
  pause
  exit /b 1
)

echo.
echo send-order-notification fonksiyonu dagitiliyor...
supabase functions deploy send-order-notification --project-ref jlpqdjhxdpmighnpebkj --no-verify-jwt
if errorlevel 1 (
  echo HATA: Fonksiyon dagitilamadi. Yukaridaki hata mesajini kontrol edin.
  pause
  exit /b 1
)

echo.
echo BASARILI: Siparis bildirim fonksiyonu Supabase'e dagitildi.
echo Simdi Supabase SQL Editor'de supabase\verify-push-setup.sql dosyasini calistirip
echo ardindan yonetici cihazini sitedeki Bildirim Gonder sayfasindan kaydedin.
pause
