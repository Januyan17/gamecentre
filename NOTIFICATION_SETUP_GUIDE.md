# Notification Setup Guide

Your app needs special permissions to show notifications when the app is closed. Follow these steps:

## Step 1: Grant Exact Alarm Permission (CRITICAL)

**This is the most important step for scheduled notifications to work when app is closed!**

1. Open **Settings** on your Android device
2. Go to **Apps** → **Rowzow** (or your app name)
3. Tap **Special app access**
4. Tap **Alarms & reminders**
5. **Enable** permission for Rowzow
6. You should see "Allowed" next to the app

**Without this permission, notifications will ONLY work when the app is open.**

## Step 2: Disable Battery Optimization

1. Open **Settings**
2. Go to **Apps** → **Rowzow**
3. Tap **Battery**
4. Select **Unrestricted**

This prevents Android from killing the app and blocking notifications.

## Step 3: Enable All Notifications

1. Open **Settings**
2. Go to **Apps** → **Rowzow**
3. Tap **Notifications**
4. **Enable** all notification options
5. Ensure "Service Time Up" notifications are enabled

## Step 4: Disable Do Not Disturb for App (Optional)

1. Open **Settings**
2. Go to **Sound & vibration** → **Do Not Disturb**
3. Tap **Apps**
4. Add **Rowzow** to allowed apps

## Testing Scheduled Notifications

After completing the steps above:

1. Open the app
2. Tap the **bell icon** in the dashboard
3. Select **"Test Scheduled Notification (10s)"**
4. **Close the app completely** (swipe away from recent apps)
5. Wait 10 seconds
6. You should receive a notification

If you don't receive the notification:
- Check that you completed Step 1 (Exact Alarm Permission)
- Check that Battery Optimization is disabled
- Reboot your device and try again

## Troubleshooting

### Notifications only work when app is open
- **Solution**: Grant exact alarm permission (Step 1)

### No notifications at all
- **Solution**: Enable all notifications (Step 3)

### Notifications delayed or inconsistent
- **Solution**: Disable battery optimization (Step 2)

### Still not working?
- Reboot your device
- Reinstall the app
- Check Android version (Android 12+ has stricter alarm policies)

## For Developers

The app uses `flutter_local_notifications` with:
- `AndroidScheduleMode.exactAllowWhileIdle` for precise timing
- Maximum importance notifications
- Wake lock and boot permissions
- Alarm category for system priority

Required permissions in AndroidManifest.xml:
- `SCHEDULE_EXACT_ALARM`
- `USE_EXACT_ALARM`
- `WAKE_LOCK`
- `RECEIVE_BOOT_COMPLETED`
- `POST_NOTIFICATIONS`
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`

