@echo off
setlocal EnableExtensions
title futbol_sim_app - GitHub Yukleme

REM This script publishes this folder to https://github.com/ysf66123/futbol_sim_app
REM Git will open a browser sign-in window if this computer is not signed in yet.
set "REPO_URL=https://github.com/ysf66123/futbol_sim_app.git"
set "COMMIT_EMAIL=unsalyusuf891@gmail.com"
set "COMMIT_NAME=ysf66123"

cd /d "%~dp0"

where git >nul 2>nul
if errorlevel 1 (
    echo.
    echo Git bulunamadi. Once https://git-scm.com/download/win adresinden Git'i kurun.
    echo Kurulumdan sonra bu dosyaya tekrar cift tiklayin.
    pause
    exit /b 1
)

if not exist ".git" (
    echo Git deposu baslatiliyor...
    git init
    if errorlevel 1 goto :error
)

git branch -M main
git config user.name "%COMMIT_NAME%"
git config user.email "%COMMIT_EMAIL%"

git remote get-url origin >nul 2>nul
if errorlevel 1 (
    git remote add origin "%REPO_URL%"
) else (
    git remote set-url origin "%REPO_URL%"
)
if errorlevel 1 goto :error

echo.
echo Dosyalar hazirlaniyor...
git add -A
if errorlevel 1 goto :error

git diff --cached --quiet
if errorlevel 1 (
    git commit -m "Projeyi guncelle"
    if errorlevel 1 goto :error
) else (
    echo Yeni bir dosya degisikligi yok; var olan commit gonderilecek.
)

REM The target repository already has an initial README commit.  Merge it once,
REM resolving a possible README clash in favour of this project's README.
git fetch origin main
if errorlevel 1 goto :error

git show-ref --verify --quiet refs/remotes/origin/main
if not errorlevel 1 (
    git merge origin/main --allow-unrelated-histories --no-edit -X ours
    if errorlevel 1 goto :error
)

echo.
echo GitHub'a yukleniyor...
git push -u origin main
if errorlevel 1 goto :error

echo.
echo Basarili: tum proje dosyalari GitHub'a yuklendi.
echo https://github.com/ysf66123/futbol_sim_app
pause
exit /b 0

:error
echo.
echo Yukleme tamamlanamadi. Ilk kullanimda acilan tarayici penceresinden
echo GitHub hesabi ile oturum acin ve bu dosyayi tekrar calistirin.
pause
exit /b 1
