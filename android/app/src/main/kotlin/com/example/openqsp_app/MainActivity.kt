package com.example.openqsp_app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "app.openqsp/bluetooth_tnc"
    private val permissionRequest = 4201
    private val sppUuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val eventChannelName = "app.openqsp/bluetooth_tnc/bytes"
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null
    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var input: InputStream? = null
    @Volatile private var output: OutputStream? = null
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var connectionGeneration = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(::handleCall)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> requestConnectPermission(result)
            "bondedDevices" -> bondedDevices(result)
            "connect" -> connect(call.argument<String>("address"), result)
            "disconnect" -> { closeSocket(); result.success(null) }
            "write" -> write(call.argument<ByteArray>("bytes"), result)
            else -> result.notImplemented()
        }
    }

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestConnectPermission(result: MethodChannel.Result) {
        if (hasConnectPermission()) { result.success(true); return }
        if (pendingPermission != null) {
            result.error("permission_pending", "A permission request is already active", null)
            return
        }
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), permissionRequest)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequest) {
            pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    private fun adapter(result: MethodChannel.Result): BluetoothAdapter? {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) result.error("unavailable", "Bluetooth is not available", null)
        else if (!adapter.isEnabled) result.error("disabled", "Bluetooth is disabled", null)
        else if (!hasConnectPermission()) result.error("permission_denied", "Bluetooth permission not granted", null)
        else return adapter
        return null
    }

    private fun bondedDevices(result: MethodChannel.Result) {
        val adapter = adapter(result) ?: return
        result.success(adapter.bondedDevices.map { mapOf("id" to it.address, "name" to (it.name ?: "Unknown device")) })
    }

    private fun connect(address: String?, result: MethodChannel.Result) {
        if (address == null) { result.error("not_found", "Missing Bluetooth address", null); return }
        val adapter = adapter(result) ?: return
        val device = adapter.bondedDevices.firstOrNull { it.address == address }
        if (device == null) { result.error("not_found", "The configured device is not paired", null); return }
        executor.execute {
            try {
                closeSocket()
                val candidate = device.createRfcommSocketToServiceRecord(sppUuid)
                socket = candidate
                candidate.connect()
                input = candidate.inputStream
                output = candidate.outputStream
                val generation = connectionGeneration
                startReader(generation, candidate, input!!)
                runOnUiThread { result.success(null) }
            } catch (error: SecurityException) {
                closeSocket()
                runOnUiThread { result.error("permission_denied", error.message, null) }
            } catch (error: IOException) {
                closeSocket()
                runOnUiThread { result.error("connection_failed", error.message, null) }
            }
        }
    }

    private fun startReader(generation: Int, activeSocket: BluetoothSocket, stream: InputStream) {
        executor.execute {
            val buffer = ByteArray(1024)
            try {
                while (generation == connectionGeneration && socket === activeSocket) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    if (count > 0) {
                        val bytes = buffer.copyOf(count)
                        mainHandler.post {
                            if (generation == connectionGeneration && socket === activeSocket) {
                                eventSink?.success(bytes)
                            }
                        }
                    }
                }
            } catch (_: IOException) {
                // Closing the socket is the normal way to stop a blocking read.
            } finally {
                if (generation == connectionGeneration && socket === activeSocket) closeSocket()
            }
        }
    }

    private fun write(bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null) { result.error("write_failed", "Missing bytes", null); return }
        val activeOutput = output
        if (activeOutput == null) { result.error("connection_failed", "TNC is not connected", null); return }
        val generation = connectionGeneration
        executor.execute {
            try {
                activeOutput.write(bytes)
                activeOutput.flush()
                mainHandler.post { result.success(null) }
            } catch (error: IOException) {
                if (generation == connectionGeneration) closeSocket()
                mainHandler.post { result.error("connection_failed", error.message, null) }
            }
        }
    }

    @Synchronized
    private fun closeSocket() {
        connectionGeneration++
        try { input?.close() } catch (_: IOException) { }
        try { output?.close() } catch (_: IOException) { }
        try { socket?.close() } catch (_: IOException) { }
        input = null
        output = null
        socket = null
    }

    override fun onDestroy() {
        closeSocket()
        executor.shutdownNow()
        super.onDestroy()
    }
}
