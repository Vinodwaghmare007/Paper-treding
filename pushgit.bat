@echo off
REM ============================================================================
REM  Crypto Paper Trader - Git push helper (Windows)
REM
REM  Run this from the project ROOT folder (same folder as pubspec.yaml).
REM  Requires: git on PATH, and this folder already set up as a git repo
REM  with a remote named "origin" (git remote -v to check).
REM
REM  This script pushes to whatever branch is currently checked out - it
REM  never force-pushes and never touches git config/credentials.
REM ============================================================================

setlocal enabledelayedexpansion
cd /d "%~dp0"

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] "git" command not found on PATH.
    echo Install Git for Windows and add it to PATH, then run this script again.
    pause
    exit /b 1
)

git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
    echo [ERROR] This folder is not a git repository.
    echo Run this script from the project root ^(same folder as pubspec.yaml^).
    pause
    exit /b 1
)

for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set BRANCH=%%b

echo.
echo ============================================
echo  Crypto Paper Trader - Git Push
echo  Current branch: %BRANCH%
echo ============================================
echo  1. Commit all changes and push
echo  2. Pull latest first, then commit and push
echo  3. Just push existing commits (nothing new to commit)
echo  4. Show git status
echo  0. Exit
echo ============================================
set /p choice="Choose an option (0-4): "

if "%choice%"=="0" exit /b 0
if "%choice%"=="4" goto status
if "%choice%"=="1" goto commit_push
if "%choice%"=="2" goto pull_then_commit_push
if "%choice%"=="3" goto push_only

echo Invalid choice.
pause
exit /b 1

:status
echo.
git status
pause
exit /b 0

:pull_then_commit_push
echo.
echo Pulling latest changes from origin/%BRANCH%...
call git pull origin %BRANCH%
if errorlevel 1 (
    echo [ERROR] Pull failed - resolve any conflicts shown above, then re-run.
    pause
    exit /b 1
)

:commit_push
echo.
echo Current changes:
git status --short
echo.

REM git status --porcelain prints nothing at all when the working tree is
REM fully clean (no staged/unstaged/untracked changes) - findstr against
REM that empty output fails to match, which is how we detect "nothing to
REM commit" without three separate git-diff checks.
git status --porcelain | findstr /r "." >nul 2>nul
if errorlevel 1 (
    echo Nothing to commit - working tree is clean.
    goto push_only
)

set /p commitmsg="Commit message (leave blank for a generic 'Update' message): "
if "%commitmsg%"=="" set commitmsg=Update

echo.
echo About to run:
echo   git add -A
echo   git commit -m "%commitmsg%"
echo   git push -u origin %BRANCH%
echo.
set /p confirm="Proceed? (y/n): "
if /i not "%confirm%"=="y" (
    echo Cancelled.
    pause
    exit /b 0
)

git add -A
git commit -m "%commitmsg%"
if errorlevel 1 (
    echo [ERROR] Commit failed - see the error above ^(e.g. git user.name/
    echo user.email not configured yet - run "git config --global user.name
    echo ..." and "git config --global user.email ..." once, then re-run^).
    pause
    exit /b 1
)

:push_only
echo.
echo Pushing %BRANCH% to origin...
git push -u origin %BRANCH%
if errorlevel 1 (
    echo [ERROR] Push failed - see the error above. If it's a "rejected" error,
    echo someone else pushed first: run option 2 ^(pull, then push^) instead.
    pause
    exit /b 1
)

echo.
echo Done. Pushed to origin/%BRANCH%.
pause
exit /b 0
