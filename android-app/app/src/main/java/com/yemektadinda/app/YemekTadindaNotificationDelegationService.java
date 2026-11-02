package com.yemektadinda.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationManagerCompat;

import com.google.androidbrowserhelper.trusted.DelegationService;

/**
 * Displays TWA Web Push notifications as native YEMEK TADINDA Android notifications.
 * The dedicated high-importance channel enables sound and vibration when the user allows them.
 */
public class YemekTadindaNotificationDelegationService extends DelegationService {
    private static final String TAG = "YemekTadindaPush";
    private static final String CHANNEL_ID = "yemek_tadinda_alerts";
    private static final String CHANNEL_NAME = "YEMEK TADINDA Bildirimleri";

    private NotificationManager notificationManager() {
        return (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
    }

    private void ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;

        NotificationManager manager = notificationManager();
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return;

        Uri sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        AudioAttributes audioAttributes = new AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build();

        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
        );
        channel.setDescription("YEMEK TADINDA kampanya ve yeni sipariş uyarıları");
        channel.setSound(sound, audioAttributes);
        channel.enableVibration(true);
        channel.setVibrationPattern(new long[]{0, 300, 180, 300, 180, 650});
        channel.setShowBadge(true);
        manager.createNotificationChannel(channel);
    }

    @Override
    public boolean onNotifyNotificationWithChannel(
            @NonNull String platformTag,
            int platformId,
            @NonNull Notification notification,
            @NonNull String channelName) {
        try {
            if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) {
                Log.w(TAG, "Android notifications are disabled for this app.");
                return false;
            }

            ensureNotificationChannel();

            Notification.Builder builder = Notification.Builder.recoverBuilder(this, notification);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationChannel channel = notificationManager().getNotificationChannel(CHANNEL_ID);
                if (channel == null || channel.getImportance() == NotificationManager.IMPORTANCE_NONE) {
                    Log.w(TAG, "YEMEK TADINDA notification channel is disabled.");
                    return false;
                }
                builder.setChannelId(CHANNEL_ID);
            } else {
                builder.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION));
                builder.setVibrate(new long[]{0, 300, 180, 300, 180, 650});
            }

            notificationManager().notify(platformTag, platformId, builder.build());
            return true;
        } catch (SecurityException error) {
            Log.e(TAG, "Android notification permission is not granted.", error);
            return false;
        } catch (RuntimeException error) {
            Log.e(TAG, "Unable to display delegated Web Push notification.", error);
            return false;
        }
    }

    @Override
    public boolean onAreNotificationsEnabled(@NonNull String channelName) {
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) return false;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true;

        NotificationChannel channel = notificationManager().getNotificationChannel(CHANNEL_ID);
        return channel == null || channel.getImportance() != NotificationManager.IMPORTANCE_NONE;
    }
}
