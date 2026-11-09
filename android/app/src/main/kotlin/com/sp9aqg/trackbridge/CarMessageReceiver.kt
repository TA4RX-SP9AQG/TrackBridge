package com.sp9aqg.trackbridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.RemoteInput

/**
 * Handles the reply and mark-as-read actions of message notifications (also those fired by
 * Android Auto). It shows no UI and only forwards to [CarMessaging].
 */
class CarMessageReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val peer = intent.getStringExtra(CarMessaging.EXTRA_PEER) ?: return
        when (intent.action) {
            CarMessaging.ACTION_REPLY -> {
                val text = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(CarMessaging.KEY_REPLY_TEXT)?.toString()
                if (text.isNullOrBlank()) return
                val pending = goAsync()
                CarMessaging.reply(context.applicationContext, peer, text) { pending.finish() }
            }
            CarMessaging.ACTION_MARK_READ -> CarMessaging.markRead(context.applicationContext, peer)
        }
    }
}
