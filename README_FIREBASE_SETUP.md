# Firebase Integration Setup Guide

This guide will help you connect your PHP admin dashboard to Firebase to display student data from your Flutter mobile app.

## Prerequisites

- Firebase project with Realtime Database or Firestore
- PHP server with cURL enabled
- Your Flutter app already storing student data in Firebase

## Step 1: Get Your Firebase Credentials

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Click on the gear icon ⚙️ > **Project Settings**
4. Scroll down to **Your apps** section
5. If you don't have a web app, click **Add app** > **Web** (</> icon)
6. Copy the following:
   - **Project ID** (you'll need this for the database URL)
   - **API Key** (optional, for authentication)

## Step 2: Configure Firebase Database URL

1. In Firebase Console, go to **Realtime Database** (or **Firestore**)
2. For **Realtime Database**:
   - The URL format is: `https://YOUR_PROJECT_ID.firebaseio.com`
   - Example: `https://ubsafesteps-12345.firebaseio.com`
3. For **Firestore**:
   - You'll need to use the REST API endpoint
   - Format: `https://firestore.googleapis.com/v1/projects/YOUR_PROJECT_ID/databases/(default)/documents`

## Step 3: Update Configuration File

Edit `firebase_config.php` and update these values:

```php
'database_url' => 'https://YOUR_PROJECT_ID.firebaseio.com',  // Replace with your Firebase URL
'api_key' => 'YOUR_API_KEY',  // Optional: Your Firebase API key
'students_path' => 'students',  // Change this to match your Flutter app's data path
```

### Finding Your Data Path

Check your Flutter app code to see where students are stored. Common paths:
- `students`
- `users/students`
- `tracking/students`
- `attendance/students`

## Step 4: Adjust Field Names (Important!)

Your Flutter app might use different field names. Edit `firebase_service.php` in the `formatStudentData()` function to match your Flutter app's data structure.

**Common field name variations:**
- Name: `name`, `fullName`, `studentName`, `full_name`
- Student ID: `studentId`, `id`, `student_id`, `uid`
- Level: `level`, `studentLevel`, `schoolLevel`, `educationLevel`
- Grade: `grade`, `gradeLevel`, `grade_level`, `class`
- Status: `status`, `attendanceStatus`, `isPresent`, `present`
- Time In: `timeIn`, `time_in`, `checkInTime`, `check_in`
- Time Out: `timeOut`, `time_out`, `checkOutTime`, `check_out`

## Step 5: Test the Connection

1. Make sure your Firebase database has student data
2. Open `dashboard.php` in your browser
3. Check the browser console (F12) for any errors
4. If you see errors, check:
   - PHP error logs
   - Firebase database URL is correct
   - Data path matches your Flutter app
   - Field names are correctly mapped

## Step 6: Firebase Security Rules

Make sure your Firebase Realtime Database rules allow reading:

```json
{
  "rules": {
    "students": {
      ".read": true,  // Or use authentication: "auth != null"
      ".write": false  // Admin dashboard is read-only
    }
  }
}
```

For Firestore:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /students/{document=**} {
      allow read: if true;  // Or use: request.auth != null
      allow write: if false;
    }
  }
}
```

## Troubleshooting

### No students showing up?
1. Check `firebase_config.php` - is the database URL correct?
2. Check the `students_path` - does it match your Flutter app?
3. Check field names in `formatStudentData()` function
4. Check browser console for JavaScript errors
5. Check PHP error logs

### Connection errors?
1. Make sure cURL is enabled in PHP: `php -m | grep curl`
2. Check if your server can access Firebase (firewall/network)
3. Verify the Firebase database URL is accessible

### Authentication errors?
If your Firebase requires authentication:
1. Generate a service account key from Firebase Console
2. Save it as `serviceAccountKey.json` in the project folder
3. Use Firebase Admin SDK (requires Composer)

## Alternative: Using Firebase Admin SDK

For better security and features, you can use the Firebase Admin SDK:

1. Install Composer (if not installed)
2. Run: `composer require kreait/firebase-php`
3. Download service account key from Firebase Console
4. Update `firebase_service.php` to use the SDK

## Support

If you need help:
1. Check Firebase documentation: https://firebase.google.com/docs
2. Verify your Flutter app's data structure
3. Check PHP and browser console for error messages

