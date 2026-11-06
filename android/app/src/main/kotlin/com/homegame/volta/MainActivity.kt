package com.homegame.volta

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "volta/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "directory") result.success(filesDir.absolutePath)
                else result.notImplemented()
            }
    }
}
