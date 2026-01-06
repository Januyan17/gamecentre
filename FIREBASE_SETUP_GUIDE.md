# Firebase Setup Guide - Fixing DEVELOPER_ERROR

## The Error
The error `ConnectionResult{statusCode=DEVELOPER_ERROR}` means your app's SHA-1/SHA-256 fingerprints are not registered in Firebase Console.

## Solution Steps

### Step 1: Get Your App's SHA-1 and SHA-256 Fingerprints

**For Debug Build:**
```bash
cd android
./gradlew signingReport
```

Look for output like:
```
Variant: debug
Config: debug
Store: C:\Users\...\.android\debug.keystore
Alias: AndroidDebugKey
SHA1: XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
SHA256: XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
```

**Or use keytool directly:**
```bash
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

### Step 2: Add SHA Fingerprints to Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **gaming-center-staff**
3. Click the gear icon ⚙️ next to "Project Overview"
4. Select **Project Settings**
5. Scroll down to **Your apps** section
6. Find your Android app: **com.company.rowzow**
7. Click **Add fingerprint**
8. Add both **SHA-1** and **SHA-256** fingerprints
9. Click **Save**

### Step 3: Download Updated google-services.json

1. After adding fingerprints, download the updated `google-services.json`
2. Replace the file at: `android/app/google-services.json`

### Step 4: Clean and Rebuild

```bash
flutter clean
flutter pub get
flutter run
```

## Alternative: Quick Fix (If you just want to test)

If you're just testing and don't want to add fingerprints right now, the app should still work for basic Firestore operations. The error is a warning and won't prevent the app from functioning.

## Note
- Package name: `com.company.rowzow` ✅ (matches google-services.json)
- Google Services plugin: ✅ (configured correctly)
- The issue is just missing SHA fingerprints in Firebase Console



