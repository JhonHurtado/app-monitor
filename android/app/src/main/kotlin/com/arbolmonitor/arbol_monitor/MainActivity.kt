package com.arbolmonitor.arbol_monitor

import android.hardware.Sensor
import android.hardware.SensorManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal nativo mínimo:
 *  - "sensors": lista real de sensores del dispositivo (SensorManager), para
 *    comprobar disponibilidad antes de medir. sensors_plus no la expone.
 *  - "keepScreenOn": mantiene la pantalla encendida durante una sesión, ya
 *    que la medición se hace con la app abierta (sin servicio en segundo plano).
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arbol_monitor/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sensors" -> {
                        val sm = getSystemService(SENSOR_SERVICE) as SensorManager
                        result.success(sm.getSensorList(Sensor.TYPE_ALL).map { s ->
                            mapOf(
                                "type" to s.type,
                                "name" to s.name,
                                "vendor" to s.vendor,
                                "resolution" to s.resolution.toDouble(),
                                "maxRange" to s.maximumRange.toDouble(),
                                "minDelayUs" to s.minDelay,
                            )
                        })
                    }
                    "keepScreenOn" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
