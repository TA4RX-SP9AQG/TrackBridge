package com.sp9aqg.trackbridge

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Message notifications for the notification shade and for Android Auto.
 *
 * Android Auto shows `MessagingStyle` notifications, reads them aloud and lets the driver dictate a
 * reply, which arrives as a `RemoteInput` on the reply action. Replies are handed to Dart over the
 * method channel, where the safety rules (off by default, only to the sender, ASCII, rate limits)
 * are enforced. Everything here runs on the main thread.
 */
object CarMessaging {
    const val CHANNEL_NAME = "trackbridge/native"
    const val NOTIFICATION_CHANNEL_ID = "trackbridge_messages"
    const val ACTION_REPLY = "com.sp9aqg.trackbridge.action.REPLY"
    const val ACTION_MARK_READ = "com.sp9aqg.trackbridge.action.MARK_READ"
    const val EXTRA_PEER = "peer"
    const val KEY_REPLY_TEXT = "reply_text"

    /** Android Auto recommends at most five messages per conversation. */
    private const val MAX_MESSAGES = 5
    private const val REPLY_TIMEOUT_MS = 10_000L

    private class Entry(val text: String, val timeMillis: Long)

    private val unread = mutableMapOf<String, MutableList<Entry>>()
    private val extraNotes = mutableMapOf<String, String>()
    private var channel: MethodChannel? = null

    /** Wires the method channel to the (cached) Flutter engine. Called once from the Application. */
    fun install(context: Context, engine: FlutterEngine) {
        ensureNotificationChannel(context)
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        ch.setMethodCallHandler { call, result -> handle(context.applicationContext, call, result) }
        channel = ch
    }

    private fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "showMessage" -> {
                val peer = call.argument<String>("peer")
                val text = call.argument<String>("text")
                val time = call.argument<Number>("timeMillis")?.toLong() ?: System.currentTimeMillis()
                if (peer == null || text == null) {
                    result.error("bad_args", "peer and text are required", null)
                } else {
                    showMessage(context, peer, text, time)
                    result.success(null)
                }
            }
            "clearMessages" -> {
                call.argument<String>("peer")?.let { clear(context, it) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, "APRS mesajları", NotificationManager.IMPORTANCE_HIGH)
        channel.description = "Size gelen APRS mesajları. Android Auto'da sesli okunur."
        manager.createNotificationChannel(channel)
    }

    /** Stable and distinct per conversation (also used as PendingIntent request code base). */
    private fun idFor(peer: String): Int = (peer.hashCode() and 0x3fffffff) or 0x1000

    fun showMessage(context: Context, peer: String, text: String, timeMillis: Long) {
        val list = unread.getOrPut(peer) { mutableListOf() }
        list.add(Entry(text, timeMillis))
        while (list.size > MAX_MESSAGES) list.removeAt(0)
        extraNotes.remove(peer)
        post(context, peer)
    }

    fun clear(context: Context, peer: String) {
        unread.remove(peer)
        extraNotes.remove(peer)
        NotificationManagerCompat.from(context).cancel(idFor(peer))
    }

    @SuppressLint("MissingPermission")
    private fun post(context: Context, peer: String) {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return

        val me = Person.Builder().setName("Siz").setKey("self").build()
        val sender = Person.Builder().setName(peer).setKey(peer).build()
        val style = NotificationCompat.MessagingStyle(me)
        unread[peer].orEmpty().forEach { style.addMessage(it.text, it.timeMillis, sender) }
        extraNotes[peer]?.let { style.addMessage(it, System.currentTimeMillis(), Person.Builder().setName("TrackBridge").setKey("app").build()) }

        val id = idFor(peer)
        val remoteInput = RemoteInput.Builder(KEY_REPLY_TEXT).setLabel("Yanıt").build()
        val replyAction = NotificationCompat.Action.Builder(R.drawable.ic_stat_trackbridge, "Yanıtla", receiverIntent(context, peer, ACTION_REPLY, id * 2, mutable = true))
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
            .setShowsUserInterface(false)
            .addRemoteInput(remoteInput)
            .build()
        val readAction = NotificationCompat.Action.Builder(R.drawable.ic_stat_trackbridge, "Okundu", receiverIntent(context, peer, ACTION_MARK_READ, id * 2 + 1, mutable = false))
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ)
            .setShowsUserInterface(false)
            .build()

        val open = PendingIntent.getActivity(
            context, id, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_trackbridge)
            .setStyle(style)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .setAutoCancel(true)
            .addAction(replyAction)
            .addInvisibleAction(readAction)
            .setOnlyAlertOnce(false)
            .build()
        manager.notify(id, notification)
    }

    private fun receiverIntent(context: Context, peer: String, action: String, requestCode: Int, mutable: Boolean): PendingIntent {
        val intent = Intent(context, CarMessageReceiver::class.java).setAction(action).putExtra(EXTRA_PEER, peer)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (mutable && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE)
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    /** The driver dictated [text] to [peer] in the car. Dart decides whether it is sent. */
    fun reply(context: Context, peer: String, text: String, done: () -> Unit) {
        val ch = channel
        if (ch == null) {
            failReply(context, peer, "Uygulama hazır değil, yanıt gönderilemedi.")
            done()
            return
        }
        val handler = Handler(Looper.getMainLooper())
        var finished = false
        val finish = { onResult: () -> Unit ->
            if (!finished) {
                finished = true
                onResult()
                done()
            }
        }
        val timeout = Runnable { finish { failReply(context, peer, "Yanıt zaman aşımına uğradı, gönderilemedi.") } }
        handler.postDelayed(timeout, REPLY_TIMEOUT_MS)
        ch.invokeMethod("reply", mapOf("peer" to peer, "text" to text), object : MethodChannel.Result {
            override fun success(result: Any?) {
                handler.removeCallbacks(timeout)
                val map = result as? Map<*, *>
                val sent = map?.get("sent") == true
                val spoken = map?.get("spoken") as? String ?: "Yanıt gönderilemedi."
                finish { if (sent) markRead(context, peer) else failReply(context, peer, spoken) }
            }

            override fun error(code: String, message: String?, details: Any?) {
                handler.removeCallbacks(timeout)
                finish { failReply(context, peer, "Yanıt gönderilemedi.") }
            }

            override fun notImplemented() {
                handler.removeCallbacks(timeout)
                finish { failReply(context, peer, "Yanıt gönderilemedi.") }
            }
        })
    }

    /** Keeps the conversation visible and adds a line that Android Auto reads aloud. */
    private fun failReply(context: Context, peer: String, spoken: String) {
        extraNotes[peer] = spoken
        post(context, peer)
    }

    /** The driver (or the notification shade) marked the conversation read. */
    fun markRead(context: Context, peer: String) {
        clear(context, peer)
        channel?.invokeMethod("markRead", mapOf("peer" to peer))
    }
}
