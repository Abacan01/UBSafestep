# 🔔 Testing Safezone Notifications Guide

This guide will help you verify that FCM notifications work properly when students enter/exit safezones.

## ✅ System Overview

Your notification system works like this:

1. **ESP32** → Sends GPS location to Firebase Realtime Database
2. **Flutter App** → Listens to location updates in `map_screen.dart`
3. **Location Monitor** → Checks if student entered/exited safezone
4. **Firestore** → Saves notification document
5. **Cloud Function** → Triggers on new notification
6. **FCM** → Sends push notification to parent's device

---

## 📋 Pre-requisites Checklist

Before testing, ensure:

- [ ] ESP32 device is powered on and sending GPS data
- [ ] Flutter app is installed on parent's device
- [ ] Parent has logged in at least once (to save FCM token)
- [ ] At least one safezone is configured (predefined or custom)
- [ ] Firebase Cloud Functions are deployed

---

## 🚀 Step 1: Deploy Cloud Functions

If you haven't deployed the Cloud Functions yet, follow these steps:

### Install Firebase CLI (if not already installed)
```bash
npm install -g firebase-tools
```

### Login to Firebase
```bash
firebase login
```

### Initialize Firebase (if first time)
```bash
cd "C:\Users\Cielo Mar\Downloads\UBSafestep-main (1)\UBSafestep-main"
firebase init functions
```
- Select your existing Firebase project
- Choose JavaScript
- Do NOT overwrite existing files

### Install Dependencies
```bash
cd functions
npm install
```

### Deploy Cloud Functions
```bash
cd ..
firebase deploy --only functions
```

**Expected Output:**
```
✔  Deploy complete!

Functions:
  pushOnNotificationCreate(us-central1)
```

---

## 🔍 Step 2: Verify Cloud Function is Deployed

### Option A: Check Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to **Build** → **Functions**
4. You should see `pushOnNotificationCreate` listed

### Option B: Check via CLI
```bash
firebase functions:list
```

---

## 📱 Step 3: Verify FCM Token is Saved

1. Open Firebase Console → **Firestore Database**
2. Navigate to `Parents_Guardian` collection
3. Find your parent document (use your email or StudentID to identify)
4. Check that there's an `fcmTokens` array field with at least one token

**Example:**
```
Parents_Guardian/{parentId}
  ├─ email: "parent@example.com"
  ├─ StudentID: "..."
  └─ fcmTokens: ["eXaMpLeToKeN123..."]
```

---

## 🧪 Step 4: Test Notification - Method 1 (Easiest)

### Test the "Test Notification" Button
1. Open the Flutter app
2. Go to **Settings**
3. Click **"Test Notification Now"**
4. You should receive a local notification immediately

✅ **If this works**, FCM setup is correct. The issue might be with safezone detection or Cloud Functions.

❌ **If this doesn't work**, check:
- Android notification permissions are granted
- App is not in battery optimization mode

---

## 🧪 Step 5: Test Safezone Entry/Exit Notifications

### Setup Test Safezones

1. **Option A: Use Predefined Safezones (Easier)**
   - The app already has 3 UB safezones configured
   - Check `safe_zones_screen.dart` lines 36-63 for coordinates

2. **Option B: Create Custom Safezone**
   - Open app → **Safe Zones** tab
   - Click **+** button
   - Pick a location near your current GPS position
   - Set radius (e.g., 100m)
   - Save

### Trigger Safezone Event

**Method 1: Move ESP32 Device**
- Physically move the ESP32 device in/out of the safezone radius
- Wait for GPS update (should be real-time)

**Method 2: Manually Update Realtime Database (For Testing)**
1. Open Firebase Console → **Realtime Database**
2. Navigate to `devices/ESP32_189426166412052`
3. Update `latitude` and `longitude` to coordinates:
   - **Inside safezone**: Use safezone coordinates ± 0.0001
   - **Outside safezone**: Use coordinates far away (e.g., 13.5, 121.0)
4. Save changes

### Expected Behavior

When student **ENTERS** safezone:
- ✅ App logs: `🟢 [SAFEZONE] Student ENTERED safezone: {Name}`
- ✅ Firestore: New document in `Notification` collection
- ✅ Cloud Function logs: `🔔 [FCM CLOUD FUNCTION] New notification detected!`
- ✅ **Push notification appears on parent's device**

When student **EXITS** safezone:
- ✅ App logs: `🔴 [SAFEZONE] Student LEFT safezone area`
- ✅ Firestore: New document in `Notification` collection
- ✅ Cloud Function logs: `🔔 [FCM CLOUD FUNCTION] New notification detected!`
- ✅ **Push notification appears on parent's device**

---

## 🔎 Step 6: View Logs for Debugging

### Flutter App Logs (Android Studio / VS Code)
Run the app in debug mode and watch the console for:
```
🟢 [SAFEZONE] Student ENTERED safezone: University Of Batangas
📍 [SAFEZONE] Location: Batangas City
👨‍👩‍👧 [SAFEZONE] Sending notification to parent: {parentId}
✅ [SAFEZONE] Entry notification saved to Firestore
⏳ [SAFEZONE] Cloud Function should now send FCM push notification...
```

### Cloud Function Logs
```bash
firebase functions:log
```

Or view in Firebase Console → **Functions** → Click function → **Logs**

Look for:
```
🔔 [FCM CLOUD FUNCTION] New notification detected!
📋 [FCM] Notification ID: ...
🔍 [FCM] Found 1 token(s) for parent
🚀 [FCM] Sending notification to 1 device(s)...
✅ [FCM] Send complete!
📊 [FCM] Success: 1 | Failed: 0
🎉 [FCM] Notification delivery complete!
```

### Realtime Database Logs
Check Firebase Console → **Realtime Database** → `devices/ESP32_189426166412052`
- Verify `latitude` and `longitude` are updating
- Check `timestamp` to see last update time

### Firestore Logs
Check Firebase Console → **Firestore** → `Notification` collection
- New documents should appear when entering/exiting safezones
- Check fields: `ParentGuardianID`, `Message`, `EmergencySOS`, `Timestamp`

---

## 🐛 Troubleshooting

### ❌ No notification received

**1. Check FCM Token**
- Firestore → `Parents_Guardian/{parentId}` → verify `fcmTokens` array exists
- If missing, restart the app to re-register

**2. Check Cloud Function Deployment**
```bash
firebase functions:list
```
- Should show `pushOnNotificationCreate`
- If missing, run `firebase deploy --only functions`

**3. Check Cloud Function Logs**
```bash
firebase functions:log --limit 50
```
- Look for errors or missing token warnings

**4. Check Notification was Created**
- Firestore → `Notification` collection → verify new document was created
- If missing, safezone detection might not be triggering

**5. Check App is on Map Screen**
- The GPS listener only runs when `map_screen.dart` is active
- Navigate to the Map tab in the app

**6. Check Android Permissions**
- Settings → Apps → UBSafeStep → Permissions
- Ensure notifications are enabled
- Disable battery optimization

---

### ❌ Notification saves but FCM doesn't send

**1. Check FCM Token in Firestore**
```bash
# Verify token exists and is valid
firebase firestore:get Parents_Guardian/{your-parent-id}
```

**2. Check Cloud Function Logs for Errors**
```bash
firebase functions:log --only pushOnNotificationCreate
```

**3. Verify Cloud Function Has Correct Permissions**
- Firebase Console → **Functions** → Check function status
- Should be "Active" with no errors

---

### ❌ Safezone not detecting

**1. Verify Safezone Coordinates**
- Open app → Safe Zones → Check coordinates
- Use Google Maps to verify coordinates are correct

**2. Check Radius**
- Default radius is 150m
- If ESP32 is far away, increase radius to test

**3. Check GPS Data Flow**
- Firebase Console → Realtime Database → `devices/ESP32_189426166412052`
- Verify `latitude` and `longitude` are updating in real-time

**4. Check Map Screen is Active**
- The listener starts in `_startStudentGPSListener()` (line 115 of map_screen.dart)
- Make sure you're on the Map tab

---

## 📊 Testing Checklist

Use this checklist to verify everything:

- [ ] Firebase Cloud Functions deployed
- [ ] `pushOnNotificationCreate` function visible in Firebase Console
- [ ] FCM token saved in `Parents_Guardian` collection
- [ ] Test notification button works
- [ ] ESP32 sending GPS data to Realtime Database
- [ ] Map screen shows student location
- [ ] At least one safezone configured
- [ ] Manually trigger entry: Update GPS to inside safezone
- [ ] Check Flutter logs for entry detection
- [ ] Check Firestore for new Notification document
- [ ] Check Cloud Function logs for FCM send
- [ ] Receive push notification on device
- [ ] Manually trigger exit: Update GPS to outside safezone
- [ ] Check Flutter logs for exit detection
- [ ] Check Firestore for new Notification document
- [ ] Check Cloud Function logs for FCM send
- [ ] Receive push notification on device

---

## 🎯 Quick Test Script

For rapid testing, update Realtime Database manually:

### Test Entry
```json
{
  "devices": {
    "ESP32_189426166412052": {
      "latitude": 13.763555,
      "longitude": 121.059865,
      "timestamp": 1234567890,
      "satellites": 8,
      "connection_type": "GPS"
    }
  }
}
```
This puts the device at UB Main Campus (inside safezone).

### Test Exit
```json
{
  "devices": {
    "ESP32_189426166412052": {
      "latitude": 13.500000,
      "longitude": 121.000000,
      "timestamp": 1234567890,
      "satellites": 8,
      "connection_type": "GPS"
    }
  }
}
```
This moves the device far from any safezone.

---

## ✅ Success Criteria

Your system is working correctly when:

1. ✅ ESP32 location updates appear in Realtime Database
2. ✅ Map screen shows real-time student location
3. ✅ Entering safezone creates Firestore notification
4. ✅ Exiting safezone creates Firestore notification
5. ✅ Cloud Function logs show successful FCM send
6. ✅ Push notifications appear on parent's device
7. ✅ Notifications show in app's Alerts tab

---

## 📞 Need Help?

If notifications still don't work after following this guide:

1. Share the Flutter app logs
2. Share Cloud Function logs (`firebase functions:log`)
3. Share screenshot of Firestore `Notification` collection
4. Share screenshot of `Parents_Guardian` document (with FCM token)

---

**Last Updated:** January 22, 2026
**System Version:** UBSafeStep v1.0


