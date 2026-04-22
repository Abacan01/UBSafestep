@echo off
REM ========================================
REM UBSafeStep - Deploy Firebase Functions
REM ========================================

echo.
echo ========================================
echo  UBSafeStep Cloud Functions Deployment
echo ========================================
echo.

echo [1/4] Checking Firebase CLI...
where firebase >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Firebase CLI not found!
    echo.
    echo Please install it first:
    echo   npm install -g firebase-tools
    echo.
    pause
    exit /b 1
)
echo ✓ Firebase CLI found

echo.
echo [2/4] Installing function dependencies...
cd functions
if not exist node_modules (
    echo Installing packages...
    call npm install
    if %ERRORLEVEL% NEQ 0 (
        echo ERROR: Failed to install dependencies
        cd ..
        pause
        exit /b 1
    )
) else (
    echo ✓ Dependencies already installed
)
cd ..

echo.
echo [3/4] Checking Firebase login...
firebase projects:list >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo You need to login to Firebase first
    echo.
    firebase login
    if %ERRORLEVEL% NEQ 0 (
        echo ERROR: Login failed
        pause
        exit /b 1
    )
)
echo ✓ Logged in to Firebase

echo.
echo [4/4] Deploying Cloud Functions...
echo This may take a few minutes...
echo.
firebase deploy --only functions

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo  ✓ Deployment Successful!
    echo ========================================
    echo.
    echo Your Cloud Function is now live and will:
    echo  - Monitor new notifications in Firestore
    echo  - Send FCM push notifications to parents
    echo  - Track safezone entry/exit events
    echo.
    echo Next steps:
    echo  1. Open the Flutter app
    echo  2. Navigate to the Map screen
    echo  3. Test safezone entry/exit
    echo  4. Check notifications
    echo.
    echo To view logs:
    echo   firebase functions:log
    echo.
    echo For detailed testing instructions, see:
    echo   TESTING_SAFEZONE_NOTIFICATIONS.md
    echo.
) else (
    echo.
    echo ========================================
    echo  ✗ Deployment Failed
    echo ========================================
    echo.
    echo Please check the error messages above.
    echo.
    echo Common issues:
    echo  - Wrong Firebase project selected
    echo  - Insufficient permissions
    echo  - Network connection issues
    echo.
    echo For help, run:
    echo   firebase --help
    echo.
)

pause


