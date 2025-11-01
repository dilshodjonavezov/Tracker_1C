package com.example.example

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.net.Uri
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import android.util.Log

class MainActivity: FlutterActivity() {
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Запрашиваем отключение оптимизации батареи
        requestBatteryOptimizationExemption()
    }
    
    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            val packageName = packageName
            
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent().apply {
                        action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    Log.d("MainActivity", "Requesting battery optimization exemption")
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error requesting battery optimization: ${e.message}")
                }
            } else {
                Log.d("MainActivity", "Already exempt from battery optimization")
            }
        }
    }
    
    override fun onDestroy() {
        Log.d("MainActivity", "Activity destroyed but service should continue")
        super.onDestroy()
    }
}