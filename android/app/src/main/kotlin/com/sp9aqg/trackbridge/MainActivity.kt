package com.sp9aqg.trackbridge

import io.flutter.embedding.android.FlutterActivity

/** Shows the UI of the Flutter engine owned by [TrackBridgeApplication]; closing the activity keeps the engine alive. */
class MainActivity : FlutterActivity() {
    override fun getCachedEngineId(): String? = TrackBridgeApplication.ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false
}
