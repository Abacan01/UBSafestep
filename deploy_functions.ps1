# ========================================
# UBSafeStep - Deploy Firebase Functions
# ========================================

Write-Host ""
Write-Host "========================================"
Write-Host " UBSafeStep Cloud Functions Deployment"
Write-Host "========================================"
Write-Host ""

# Check Firebase CLI
Write-Host "[1/4] Checking Firebase CLI..." -ForegroundColor Cyan
try {
    $firebaseVersion = firebase --version 2>$null
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Host "✓ Firebase CLI found" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Firebase CLI not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install it first:" -ForegroundColor Yellow
    Write-Host "  npm install -g firebase-tools" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Install dependencies
Write-Host ""
Write-Host "[2/4] Installing function dependencies..." -ForegroundColor Cyan
Push-Location functions
if (-not (Test-Path "node_modules")) {
    Write-Host "Installing packages..." -ForegroundColor Yellow
    npm install
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install dependencies" -ForegroundColor Red
        Pop-Location
        Read-Host "Press Enter to exit"
        exit 1
    }
} else {
    Write-Host "✓ Dependencies already installed" -ForegroundColor Green
}
Pop-Location

# Check login
Write-Host ""
Write-Host "[3/4] Checking Firebase login..." -ForegroundColor Cyan
firebase projects:list 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "You need to login to Firebase first" -ForegroundColor Yellow
    Write-Host ""
    firebase login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Login failed" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}
Write-Host "✓ Logged in to Firebase" -ForegroundColor Green

# Deploy
Write-Host ""
Write-Host "[4/4] Deploying Cloud Functions..." -ForegroundColor Cyan
Write-Host "This may take a few minutes..." -ForegroundColor Yellow
Write-Host ""

firebase deploy --only functions

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " ✓ Deployment Successful!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your Cloud Function is now live and will:" -ForegroundColor Cyan
    Write-Host " - Monitor new notifications in Firestore"
    Write-Host " - Send FCM push notifications to parents"
    Write-Host " - Track safezone entry/exit events"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host " 1. Open the Flutter app"
    Write-Host " 2. Navigate to the Map screen"
    Write-Host " 3. Test safezone entry/exit"
    Write-Host " 4. Check notifications"
    Write-Host ""
    Write-Host "To view logs:" -ForegroundColor Cyan
    Write-Host "  firebase functions:log" -ForegroundColor White
    Write-Host ""
    Write-Host "For detailed testing instructions, see:" -ForegroundColor Cyan
    Write-Host "  TESTING_SAFEZONE_NOTIFICATIONS.md" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " ✗ Deployment Failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please check the error messages above." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Common issues:" -ForegroundColor Cyan
    Write-Host " - Wrong Firebase project selected"
    Write-Host " - Insufficient permissions"
    Write-Host " - Network connection issues"
    Write-Host ""
    Write-Host "For help, run:" -ForegroundColor Cyan
    Write-Host "  firebase --help" -ForegroundColor White
    Write-Host ""
}

Read-Host "Press Enter to exit"


