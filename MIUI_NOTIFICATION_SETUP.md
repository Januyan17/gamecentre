# 🔴 CRITICAL: MIUI/Xiaomi Notification Setup (Redmi Note 11)

MIUI has **EXTREMELY AGGRESSIVE** battery optimization that kills notifications. You MUST follow ALL these steps for notifications to work when the app is closed.

## ⚠️ Why MIUI is Different

Xiaomi/MIUI devices (Redmi, Mi, Poco) have the most aggressive battery optimization of any Android manufacturer. They kill background apps and scheduled alarms even when you think you've enabled everything. You need to configure MULTIPLE settings.

---

## 🎯 Step-by-Step Guide for Redmi Note 11

### Step 1: Disable Battery Saver (CRITICAL)

1. Open **Security** app
2. Tap **Battery**
3. Turn **OFF** Battery Saver
4. If it's already off, toggle it on then off again

### Step 2: Enable Autostart (MOST IMPORTANT)

1. Open **Settings**
2. Tap **Apps** → **Manage apps**
3. Find and tap **Rowzow**
4. Tap **Autostart**
5. **Enable** the toggle (it must be ON/blue)
6. You should see "Allowed" next to Autostart

**Without Autostart, notifications will NEVER work when app is closed!**

### Step 3: Battery Settings for the App

1. Still in **Settings** → **Apps** → **Manage apps** → **Rowzow**
2. Tap **Battery saver**
3. Select **No restrictions**
4. Enable **Run in background**

### Step 4: Notification Settings

1. Still in **Settings** → **Apps** → **Manage apps** → **Rowzow**
2. Tap **Notifications**
3. Enable **Show notifications**
4. Ensure **Service Time Up** is enabled
5. Enable **Lock screen notifications**

### Step 5: Display Pop-up Windows

1. Still in **Settings** → **Apps** → **Manage apps** → **Rowzow**
2. Tap **Other permissions**
3. Enable **Display pop-up windows**

### Step 6: Exact Alarm Permission

1. Go to **Settings** → **Apps** → **Manage apps** → **Rowzow**
2. Tap **Special app access** (at the bottom)
3. Tap **Alarms & reminders**
4. **Enable** for Rowzow

### Step 7: Disable Memory Optimization

1. Open **Security** app
2. Tap **Boost speed** or **Clear memory**
3. Go to settings (gear icon)
4. Find **Rowzow** in the list
5. **Add to exceptions** or **Lock** the app

### Step 8: Developer Options (Advanced)

If still not working:

1. Go to **Settings** → **About phone**
2. Tap **MIUI version** 7 times to enable Developer options
3. Go to **Settings** → **Additional settings** → **Developer options**
4. Enable **Stay awake when charging** (if testing while charging)
5. Find **Standby apps** → Set Rowzow to **Active**

---

## 🧪 Testing

After completing ALL steps above:

1. **Restart your phone** (important!)
2. Open the Rowzow app
3. Tap the bell icon → **Test Scheduled Notification (10s)**
4. **Close the app completely** (swipe away from recent apps)
5. **Lock your phone**
6. Wait 10 seconds
7. You should hear/see the notification!

If you don't receive it, go back and verify:
- Autostart is enabled (Step 2)
- Battery Saver is OFF (Step 1)
- Battery saver for app is "No restrictions" (Step 3)

---

## 🔧 Additional MIUI-Specific Troubleshooting

### If Notifications Still Don't Work:

1. **Clear MIUI Security cache:**
   - Settings → Apps → Manage apps → Security
   - Clear cache and data

2. **Disable MIUI Optimization:**
   - Developer options → Turn OFF MIUI optimization
   - Restart phone

3. **Check Memory Optimization:**
   - Security app → Boost speed → Settings
   - Make sure Rowzow is NOT in the "Apps to clear" list

4. **Disable Adaptive Battery:**
   - Settings → Battery → Battery optimization
   - Find Rowzow → Don't optimize

5. **Reset App Preferences:**
   - Settings → Apps → (three dots) → Reset app preferences
   - Then redo all the steps above

---

## 📱 MIUI Version-Specific Notes

### MIUI 12/13/14:
- Security app → Battery → Clear background apps → Add Rowzow to exceptions

### MIUI 14 (Android 13):
- Settings → Notifications → Advanced settings → Enable "Show on lock screen"

---

## ⚡ Quick Checklist

Before reporting issues, verify ALL these are done:

- [ ] Battery Saver is OFF
- [ ] Autostart is ENABLED for Rowzow
- [ ] Battery saver for app: No restrictions
- [ ] Notifications are enabled
- [ ] Display pop-up windows enabled
- [ ] Exact alarm permission granted
- [ ] App is in Security app exceptions
- [ ] Phone has been restarted
- [ ] Tested with phone locked

---

## 🆘 Still Not Working?

If you've done ALL the steps above and restarted your phone, and notifications still don't work:

1. Check MIUI version: Settings → About phone → MIUI version
2. Check Android version: Settings → About phone → Android version
3. Try disabling "Deep clean" in Security app
4. Try setting a longer test time (2-3 minutes instead of 10 seconds)
5. Make sure phone has good network/WiFi connection
6. Check if other apps' scheduled notifications work

MIUI is notoriously difficult with background tasks. Some users report that certain MIUI versions/regions have persistent issues that can only be fixed by switching to a different ROM.

---

## 💡 Pro Tips for MIUI Users

1. **Keep the app locked in recent apps:** When viewing recent apps, tap and hold Rowzow → tap the lock icon
2. **Don't use Ultra battery saver mode**
3. **Keep your MIUI updated** (some versions have fixed notification bugs)
4. **Check Xiaomi forums** for your specific device model - there may be device-specific quirks

---

**Remember: MIUI requires ALL these settings to be configured. Missing even one can cause notifications to fail!**




