@echo off
REM ========================================
REM Setup Notification Icon
REM ========================================

echo.
echo Setting up notification icon...
echo.

REM Create drawable folders if they don't exist
if not exist "android\app\src\main\res\drawable-mdpi" mkdir "android\app\src\main\res\drawable-mdpi"
if not exist "android\app\src\main\res\drawable-hdpi" mkdir "android\app\src\main\res\drawable-hdpi"
if not exist "android\app\src\main\res\drawable-xhdpi" mkdir "android\app\src\main\res\drawable-xhdpi"
if not exist "android\app\src\main\res\drawable-xxhdpi" mkdir "android\app\src\main\res\drawable-xxhdpi"
if not exist "android\app\src\main\res\drawable-xxxhdpi" mkdir "android\app\src\main\res\drawable-xxxhdpi"

echo.
echo Copying launcher icons as notification icons...
echo Note: For best results, create monochrome (white) versions of your logo
echo and place them in the drawable-* folders as ic_notification.png
echo.

REM Copy launcher icons to drawable folders (temporary solution)
copy "android\app\src\main\res\mipmap-mdpi\ic_launcher.png" "android\app\src\main\res\drawable-mdpi\ic_notification.png" >nul 2>&1
copy "android\app\src\main\res\mipmap-hdpi\ic_launcher.png" "android\app\src\main\res\drawable-hdpi\ic_notification.png" >nul 2>&1
copy "android\app\src\main\res\mipmap-xhdpi\ic_launcher.png" "android\app\src\main\res\drawable-xhdpi\ic_notification.png" >nul 2>&1
copy "android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png" "android\app\src\main\res\drawable-xxhdpi\ic_notification.png" >nul 2>&1
copy "android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png" "android\app\src\main\res\drawable-xxxhdpi\ic_notification.png" >nul 2>&1

echo.
echo ========================================
echo  Notification Icon Setup Complete!
echo ========================================
echo.
echo IMPORTANT: Android notification icons should be MONOCHROME (white/transparent)
echo.
echo For best results:
echo 1. Go to: https://romannurik.github.io/AndroidAssetStudio/icons-notification.html
echo 2. Upload your UBSafestepslogo.png
echo 3. Download the generated monochrome icons
echo 4. Extract and copy to android\app\src\main\res\drawable-* folders
echo.
echo The notification service is configured to use @mipmap/ic_launcher
echo If you create ic_notification.png, update push_notifications_service.dart
echo to use @drawable/ic_notification instead.
echo.
pause


