package com.sp9aqg.trackbridge

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Owns the Flutter engine for the whole life of the process.
 *
 * A normal FlutterActivity destroys its engine when the activity goes away (for example when the app
 * is swiped out of the recent apps), which would silently end the Bluetooth connection while a
 * foreground-service notification is still showing. Here the engine is created once, starts running
 * Dart immediately, and is only attached to an activity when one exists (see [MainActivity]).
 */
class TrackBridgeApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        // Message notifications (phone and Android Auto) talk to Dart over this engine, with or without an activity.
        CarMessaging.install(this, engine)
    }

    companion object {
        const val ENGINE_ID = "trackbridge_engine"
    }
}
