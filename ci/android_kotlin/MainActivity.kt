package com.agus.movetrack_ai

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity wajib untuk plugin health (Health Connect).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        VideoEncoderChannel.register(flutterEngine.dartExecutor.binaryMessenger, cacheDir)
    }
}
