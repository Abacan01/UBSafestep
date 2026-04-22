# 🎨 Setting Up App Icons and Notification Icons

This guide will help you set up the UBSafestepslogo.png as both the app icon and notification icon.

## 📋 Prerequisites

- UBSafestepslogo.png file in the `asset/` folder
- Flutter SDK installed
- Android Studio (for icon generation tools)

---

## 🚀 Step 1: Install Dependencies

Run this command to install the icon generation package:

```bash
flutter pub get
```

---

## 🎯 Step 2: Generate App Icons

The `flutter_launcher_icons` package has been added to your `pubspec.yaml`. Now generate the app icons:

```bash
flutter pub run flutter_launcher_icons
```

This will:
- ✅ Generate app icons in all required sizes for Android
- ✅ Replace existing `ic_launcher.png` files in `android/app/src/main/res/mipmap-*/` folders
- ✅ Create adaptive icons for modern Android devices

---

## 📱 Step 3: Create Notification Icon

**Important:** Android notification icons must be:
- **Monochrome** (white/transparent only)
- **Simple design** (no colors, gradients, or complex shapes)
- **24x24dp base size** (but we need multiple sizes)

### Option A: Use Online Tool (Easiest)

1. Go to [Android Asset Studio - Notification Icon Generator](https://romannurik.github.io/AndroidAssetStudio/icons-notification.html)
2. Upload your `UBSafestepslogo.png`
3. The tool will convert it to monochrome
4. Download the generated icons
5. Extract the `drawable-*` folders
6. Copy them to `android/app/src/main/res/`

### Option B: Manual Creation

If the logo is too complex, create a simplified version:

1. Create a simple white icon based on the logo (just the arrow or "S" shape)
2. Save as PNG with transparent background
3. Use the tool above or manually create sizes:
   - `drawable-mdpi/ic_notification.png` (24x24px)
   - `drawable-hdpi/ic_notification.png` (36x36px)
   - `drawable-xhdpi/ic_notification.png` (48x48px)
   - `drawable-xxhdpi/ic_notification.png` (72x72px)
   - `drawable-xxxhdpi/ic_notification.png` (96x96px)

### Option C: Use Existing Launcher Icon (Quick Fix)

For now, you can use the launcher icon as notification icon:

1. Copy `ic_launcher.png` from each `mipmap-*` folder
2. Create corresponding `drawable-*` folders if they don't exist
3. Paste and rename to `ic_notification.png`

**Note:** This might not work perfectly because launcher icons are colored, but it's a quick solution.

---

## 🔧 Step 4: Update Notification Service

The notification service is already configured to use `@mipmap/ic_launcher`. If you created a separate notification icon, update `lib/services/push_notifications_service.dart`:

Change:
```dart
icon: '@mipmap/ic_launcher',
```

To:
```dart
icon: '@drawable/ic_notification',
```

**However**, if you want to use the launcher icon for notifications (simpler), keep it as `@mipmap/ic_launcher`.

---

## ✅ Step 5: Verify Setup

1. **App Icon:**
   - Rebuild the app: `flutter clean && flutter build apk`
   - Install on device
   - Check that the app icon shows your logo

2. **Notification Icon:**
   - Trigger a safezone notification
   - Check notification tray
   - Verify icon appears correctly

---

## 🎨 Recommended: Create Simplified Notification Icon

Since the UBSafesteps logo has colors and gradients, create a simplified monochrome version:

### Design Guidelines:
- Use only the arrow shape or "S" shape from the logo
- Make it white on transparent background
- Keep it simple and recognizable
- Test at small sizes (24x24px) to ensure clarity

### Tools:
- [Android Asset Studio](https://romannurik.github.io/AndroidAssetStudio/icons-notification.html) - Best option
- [Icon Kitchen](https://icon.kitchen/) - Alternative
- Photoshop/GIMP - Manual creation

---

## 📝 Quick Commands Summary

```bash
# 1. Install dependencies
flutter pub get

# 2. Generate app icons
flutter pub run flutter_launcher_icons

# 3. Clean and rebuild
flutter clean
flutter build apk

# 4. Install and test
flutter install
```

---

## 🐛 Troubleshooting

### App Icon Not Updating
- Run `flutter clean`
- Delete `build/` folder
- Rebuild: `flutter build apk`

### Notification Icon Not Showing
- Check icon is in `drawable-*` folders (not `mipmap-*`)
- Verify icon is monochrome (white/transparent)
- Check notification service uses correct icon name
- Rebuild app after adding icons

### Icon Looks Blurry
- Ensure all size variants are created
- Check icon resolution matches requirements
- Use proper DPI folders (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi)

---

## 📚 Additional Resources

- [Flutter Launcher Icons Documentation](https://pub.dev/packages/flutter_launcher_icons)
- [Android Notification Icon Guidelines](https://developer.android.com/guide/practices/ui_guidelines/icon_design_notification)
- [Android Asset Studio](https://romannurik.github.io/AndroidAssetStudio/)

---

**Last Updated:** January 22, 2026


