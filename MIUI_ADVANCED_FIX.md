# MIUI Background Notification Fix - Advanced Settings

## The Problem You're Having

Notifications are being **queued/held by MIUI** and only appear when you reopen the app. This is MIUI's "Smart Notification" feature blocking background notifications.

## 🔴 Additional MIUI Settings You MUST Configure

You said you enabled all permissions, but MIUI has **hidden settings** that still block notifications. Follow these additional steps:

### 1. Disable MIUI Optimization (CRITICAL!)

1. Enable Developer Options:
   - Settings → About phone → Tap MIUI version 7 times
2. Go to Settings → Additional settings → Developer options
3. Scroll down and find **"MIUI optimization"**
4. **Turn it OFF**
5. **Restart your phone**

**This is the most likely cause of delayed notifications!**

### 2. Smart Notifications Settings

1. Open **Security** app
2. Tap **Notifications** (or Manage notifications)
3. Find **Rowzow** in the list
4. Set to **"Allow all notifications"**
5. Enable **"Show on lock screen"**
6. Enable **"Show notification dot"**

### 3. Battery & Performance Deep Settings

1. Open **Security** app
2. Tap **Battery**
3. Tap the **Settings icon** (gear) in top right
4. Tap **"App battery saver"**
5. Find **Rowzow**
6. Set to **"No restrictions"**

Then go back and:
7. Tap **"Manage apps' battery usage"**
8. Tap **"Choose apps"**
9. Find **Rowzow** and select **"No restrictions"**

### 4. Display Pop-up Windows While Running in Background

1. Settings → Apps → Manage apps → Rowzow
2. Tap **"Other permissions"**
3. Enable **"Display pop-up windows while running in background"**
4. Enable **"Display pop-up windows"**

### 5. Notifications - Advanced Settings

1. Settings → Notifications & Control Center → Notifications
2. Tap **Rowzow**
3. Enable **ALL** toggles:
   - Lock screen notifications
   - Notification shade
   - Banners
   - Sound
   - Vibration
4. Set Importance to **"Urgent"** (highest level)

### 6. Memory Settings (Clear from "Boost Speed")

1. Open **Security** app
2. Tap **Boost speed** or **Cleaner**
3. Tap the **Settings icon** (gear)
4. Find **Rowzow** in the list
5. **Add to exceptions** or **Lock** it

### 7. Focus Mode / Do Not Disturb

1. Settings → Sound & vibration → Do Not Disturb
2. Make sure it's **OFF**, or
3. If ON, tap **Exceptions** → Apps → Add **Rowzow**

### 8. Notification Restrictions (Hidden Setting)

1. Settings → Apps → Manage apps → Rowzow
2. Tap **Notifications**
3. Tap **"Service Time Up"** channel
4. Set to **"Urgent"**
5. Enable **"Override Do Not Disturb"**

### 9. Check Special Restrictions (MIUI 13/14)

1. Settings → Apps → Manage apps
2. Tap **three dots** (⋮) in top right
3. Tap **"Special restrictions"**
4. Find **Rowzow** and remove any restrictions

### 10. Background Activity Monitor

1. Settings → Apps → Manage apps → Rowzow
2. Look for **"Background activity monitor"**
3. If present, **Disable it**

---

## 🧪 After Completing ALL Steps Above:

1. **RESTART YOUR PHONE** (critical!)
2. Open the app
3. Add a PS4/PS5 with **2 minute** duration (not 1 minute, give it time)
4. **Close the app** (swipe away from recent apps)
5. **Lock your phone**
6. **Wait 2 minutes without touching the phone**
7. Notification should appear!

---

## 📱 Still Not Working? Nuclear Options:

### Option A: Disable All Battery Optimization
1. Settings → Apps → Permissions
2. Tap **Special app access**
3. Tap **"Display over other apps"** → Enable for Rowzow
4. Go back → Tap **"Battery optimization"**
5. Select **"All apps"** from dropdown
6. Find **Rowzow** → Select **"Don't optimize"**

### Option B: Reset MIUI Security App
1. Settings → Apps → Manage apps
2. Find **"Security"**
3. Tap **Storage** → **Clear data**
4. Restart phone
5. Redo all security app settings

### Option C: Use Third-Party Notification Tool
If MIUI still blocks after ALL the above:
- Some MIUI versions are known to be broken
- Consider using "Don't Kill My App" in Play Store
- Check XDA forums for your specific MIUI version

---

## 🔍 How to Check if MIUI is Blocking

Check the logs in your computer when alarm should fire:
- If you see "Received alarm!" → MIUI delivered it
- If you see nothing → MIUI is blocking at system level

---

## 💡 MIUI Version Matters

- **MIUI 12**: Known issues with background alarms
- **MIUI 13**: Better, but still aggressive
- **MIUI 14**: Most reliable, but still needs all settings

Check your MIUI version: Settings → About phone → MIUI version

---

**Remember: MIUI is designed to block background activity. You need to configure MULTIPLE hidden settings for it to work!**



