#!/usr/bin/env python3
"""Generate the native Shizuku/uinput bridge in Flutter's generated Android project."""
from pathlib import Path
import re

root = Path("android/app/src/main")
kotlin = root / "kotlin/com/tomastharwat/nintendo_nes"
receiver_kotlin = Path("android/app/src/receiver/kotlin/com/tomastharwat/nintendo_nes")
controller_kotlin = Path("android/app/src/controller/kotlin/com/tomastharwat/nintendo_nes")
aidl_dir = root / "aidl/com/tomastharwat/nintendo_nes"

receiver_logger = r'''
package com.tomastharwat.nintendo_nes

import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.BufferedWriter
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object ReceiverLogger {
    private const val TAG = "NintendoNESReceiver"
    private const val FILE_NAME = "receiver.log"
    private const val FOLDER_NAME = "Nintendo NES Receiver"
    private const val MAX_LOG_BYTES = 5L * 1024L * 1024L
    private val lock = Any()
    private val timestampFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS Z", Locale.US)
    @Volatile private var writer: BufferedWriter? = null
    @Volatile private var target = "not initialized"
    private var appContext: Context? = null

    fun initialize(context: Context) {
        synchronized(lock) {
            appContext = context.applicationContext
            if (writer != null) return
            val publicWriter = try { openPublicDownloadsWriter(context.applicationContext) }
            catch (error: Exception) { Log.e(TAG, "Could not open the public Downloads log file", error); null }
            if (publicWriter != null) {
                writer = publicWriter
                target = "Downloads/" + FOLDER_NAME + "/" + FILE_NAME
            } else {
                openInternalWriter(context.applicationContext)
            }
            writeLineLocked("INFO", "Logger initialized; destination=" + target +
                "; sdk=" + Build.VERSION.SDK_INT)
        }
    }

    fun reinitialize(context: Context) {
        synchronized(lock) {
            val app = context.applicationContext
            val internal = File(app.filesDir, FILE_NAME)
            val previous = try { if (internal.isFile) internal.readText(Charsets.UTF_8) else "" }
                catch (_: Exception) { "" }
            try { writer?.flush(); writer?.close() }
            catch (error: Exception) { Log.e(TAG, "Could not close old log writer", error) }
            writer = null
            target = "not initialized"
            appContext = app
            val publicWriter = try { openPublicDownloadsWriter(app) }
                catch (error: Exception) { Log.e(TAG, "Could not switch log destination to Downloads", error); null }
            if (publicWriter != null) {
                writer = publicWriter
                target = "Downloads/" + FOLDER_NAME + "/" + FILE_NAME
                if (previous.isNotBlank()) {
                    try {
                        writer?.write("----- migrated internal diagnostic log -----\n")
                        writer?.write(previous)
                        if (!previous.endsWith("\n")) writer?.newLine()
                        writer?.flush()
                        internal.delete()
                    } catch (error: Exception) {
                        Log.e(TAG, "Could not migrate internal diagnostics into Downloads", error)
                    }
                }
            } else {
                openInternalWriter(app)
            }
            writeLineLocked("INFO", "Log destination refreshed; destination=" + target)
        }
    }

    fun log(level: String, message: String, error: Throwable? = null) {
        synchronized(lock) {
            if (writer == null) {
                val context = appContext
                if (context != null) initialize(context)
            }
            writeLineLocked(level, message, error)
        }
    }

    fun destinationLabel(): String = target

    private fun openPublicDownloadsWriter(context: Context): BufferedWriter? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val relativePath = Environment.DIRECTORY_DOWNLOADS + "/" + FOLDER_NAME + "/"
            val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.SIZE)
            val cursor = resolver.query(
                collection, projection,
                MediaStore.MediaColumns.DISPLAY_NAME + "=? AND " + MediaStore.MediaColumns.RELATIVE_PATH + "=?",
                arrayOf(FILE_NAME, relativePath), null
            )
            var uri: android.net.Uri? = null
            var size = 0L
            cursor?.use {
                if (it.moveToFirst()) {
                    val id = it.getLong(it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                    val sizeColumn = it.getColumnIndex(MediaStore.MediaColumns.SIZE)
                    size = if (sizeColumn >= 0) it.getLong(sizeColumn) else 0L
                    uri = android.content.ContentUris.withAppendedId(collection, id)
                }
            }
            var created = false
            if (uri == null) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, FILE_NAME)
                    put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                uri = resolver.insert(collection, values)
                    ?: throw IllegalStateException("MediaStore could not create Downloads/" + FOLDER_NAME + "/" + FILE_NAME)
                created = true
                size = 0L
            }
            val mode = if (size > MAX_LOG_BYTES) "wt" else "wa"
            val stream = resolver.openOutputStream(uri!!, mode)
                ?: throw IllegalStateException("MediaStore could not open the Receiver log for writing")
            if (created) resolver.update(uri!!, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
            if (size > MAX_LOG_BYTES) {
                stream.write(("----- previous log exceeded " + MAX_LOG_BYTES + " bytes; started a new log -----\n")
                    .toByteArray(StandardCharsets.UTF_8))
            }
            return BufferedWriter(OutputStreamWriter(stream, StandardCharsets.UTF_8))
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            context.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) return null

        @Suppress("DEPRECATION")
        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val directory = File(downloads, FOLDER_NAME)
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw IllegalStateException("Could not create Downloads/" + FOLDER_NAME)
        }
        val file = File(directory, FILE_NAME)
        val append = file.isFile && file.length() <= MAX_LOG_BYTES
        val stream = FileOutputStream(file, append)
        if (!append && file.length() == 0L) {
            stream.write(("----- previous log exceeded " + MAX_LOG_BYTES + " bytes; started a new log -----\n")
                .toByteArray(StandardCharsets.UTF_8))
        }
        return BufferedWriter(OutputStreamWriter(stream, StandardCharsets.UTF_8))
    }

    private fun openInternalWriter(context: Context) {
        val file = File(context.filesDir, FILE_NAME)
        try {
            val append = file.isFile && file.length() <= MAX_LOG_BYTES
            writer = BufferedWriter(OutputStreamWriter(FileOutputStream(file, append), StandardCharsets.UTF_8))
            target = "internal app storage/receiver.log (Downloads is unavailable)"
            writeLineLocked("WARN", "Public Downloads logging unavailable; using " + file.absolutePath)
        } catch (error: Exception) {
            writer = null
            target = "Log file unavailable; see Android Logcat"
            Log.e(TAG, "Could not open internal diagnostic log", error)
        }
    }

    private fun writeLineLocked(level: String, message: String, error: Throwable? = null) {
        val now = timestampFormat.format(Date())
        val entry = now + " [" + level + "] [thread=" + Thread.currentThread().name + "] " + message
        val priority = when (level.uppercase(Locale.US)) {
            "ERROR" -> Log.ERROR
            "WARN", "WARNING" -> Log.WARN
            "DEBUG" -> Log.DEBUG
            else -> Log.INFO
        }
        Log.println(priority, TAG, entry)
        val current = writer ?: return
        try {
            current.write(entry)
            current.newLine()
            if (error != null) {
                val stack = Log.getStackTraceString(error).replace("\r", "")
                current.write(stack)
                if (!stack.endsWith("\n")) current.newLine()
                Log.e(TAG, message, error)
            }
            current.flush()
        } catch (writeError: Exception) {
            Log.e(TAG, "Writing diagnostic log failed; destination=" + target, writeError)
            try { current.close() } catch (_: Exception) { }
            writer = null
            val context = appContext
            if (context != null) {
                openInternalWriter(context)
                val fallback = writer
                try {
                    fallback?.write(entry)
                    fallback?.newLine()
                    if (error != null) fallback?.write(Log.getStackTraceString(error) + "\n")
                    fallback?.flush()
                } catch (fallbackError: Exception) {
                    Log.e(TAG, "Fallback diagnostic log write failed", fallbackError)
                }
            }
        }
    }
}
'''

main = r'''
package com.tomastharwat.nintendo_nes

import android.app.Activity
import android.content.ComponentName
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import rikka.shizuku.Shizuku
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.Executors

class MainActivity : Activity() {
    companion object {
        private const val REQUEST_SHIZUKU = 9001
        private const val REQUEST_DOWNLOADS_PERMISSION = 9002
        private const val PORT = 27191
        private const val BIND_TIMEOUT_MS = 20000L
        private const val START_TIMEOUT_MS = 25000L
    }

    @Volatile private var service: IGamepadService? = null
    private var bound = false
    private var binding = false
    private var startRequested = false
    private var startInFlight = false
    private var statusCheckInFlight = false
    private var permissionCheckInFlight = false
    private var bindAttemptId = 0
    private var startAttemptId = 0
    private var bindTimeout: Runnable? = null
    private var startTimeout: Runnable? = null
    private var lastUiStatus = ""
    private var lastIpError = ""
    private lateinit var statusView: TextView
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newCachedThreadPool { task ->
        Thread(task, "nes-shizuku-io").apply { isDaemon = true }
    }

    private val statusTicker = object : Runnable {
        override fun run() {
            refreshStatus()
            mainHandler.postDelayed(this, 1000)
        }
    }

    private val userServiceArgs = Shizuku.UserServiceArgs(
        ComponentName(BuildConfig.APPLICATION_ID, GamepadUserService::class.java.name)
    ).daemon(false).processNameSuffix("gamepad").debuggable(false).version(3)

    private val permissionListener = Shizuku.OnRequestPermissionResultListener { code, grant ->
        mainHandler.post {
            ReceiverLogger.log(
                if (grant == PackageManager.PERMISSION_GRANTED) "INFO" else "ERROR",
                "Shizuku permission callback: requestCode=" + code + " grantResult=" + grant
            )
            if (code == REQUEST_SHIZUKU) {
                if (grant == PackageManager.PERMISSION_GRANTED) {
                    bindReceiver()
                } else {
                    startRequested = false
                    showStatus(statusText("Shizuku permission denied. Grant permission in Shizuku, then press Start."),
                        "ERROR")
                }
            }
        }
    }

    private val connection: ServiceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            ReceiverLogger.log(
                "INFO",
                "ServiceConnection.onServiceConnected component=" + name +
                    " binderAlive=" + binder.isBinderAlive + " binderPing=" + binder.pingBinder()
            )
            mainHandler.post {
                bindTimeout?.let { mainHandler.removeCallbacks(it) }
                bindTimeout = null
                binding = false
                bound = true
                service = IGamepadService.Stub.asInterface(binder)
                ReceiverLogger.log("INFO", "AIDL IGamepadService proxy created; startRequested=" + startRequested)
                if (startRequested) startReceiver() else refreshStatus()
            }
        }

        override fun onServiceDisconnected(name: ComponentName) {
            ReceiverLogger.log("ERROR", "ServiceConnection.onServiceDisconnected component=" + name)
            mainHandler.post { markServiceLost("Shizuku service disconnected. Press Start to reconnect.") }
        }

        override fun onBindingDied(name: ComponentName) {
            ReceiverLogger.log("ERROR", "ServiceConnection.onBindingDied component=" + name)
            mainHandler.post { markServiceLost("Shizuku binding died. Restart Shizuku on the TV, then press Start.") }
        }

        override fun onNullBinding(name: ComponentName) {
            ReceiverLogger.log("ERROR", "ServiceConnection.onNullBinding component=" + name)
            mainHandler.post { markServiceLost("Shizuku returned an empty service binding. Check Shizuku and app permissions.") }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ReceiverLogger.initialize(this)
        ReceiverLogger.log(
            "INFO",
            "Activity onCreate; package=" + packageName + " versionCode=" + BuildConfig.VERSION_CODE +
                " sdk=" + Build.VERSION.SDK_INT + " manufacturer=" + Build.MANUFACTURER +
                " model=" + Build.MODEL + " release=" + Build.VERSION.RELEASE +
                " process=" + android.os.Process.myPid()
        )

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.BLACK)
            setPadding(dp(28), dp(18), dp(28), dp(22))
            isFocusableInTouchMode = true
        }
        val title = TextView(this).apply {
            text = "Nintendo NES Receiver"
            textSize = 28f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        statusView = TextView(this).apply {
            textSize = 18f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }
        val startButton: Button = Button(this).apply {
            text = "Start"
            isAllCaps = false
            textSize = 20f
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(Color.rgb(45, 45, 45))
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(0, dp(64), 1f).apply { marginEnd = dp(8) }
            setOnClickListener {
                ReceiverLogger.log("INFO", "Start button clicked")
                requestShizuku()
            }
        }
        val stopButton: Button = Button(this).apply {
            text = "Stop"
            isAllCaps = false
            textSize = 20f
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(Color.rgb(75, 25, 25))
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(0, dp(64), 1f).apply { marginStart = dp(8) }
            setOnClickListener {
                ReceiverLogger.log("INFO", "Stop button clicked")
                stopReceiver()
            }
        }
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            addView(startButton)
            addView(stopButton)
        }
        root.addView(title, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(72)))
        root.addView(statusView, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(actions, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(72)))
        setContentView(root)
        startButton.requestFocus()

        Shizuku.addRequestPermissionResultListener(permissionListener)
        ReceiverLogger.log("INFO", "Registered Shizuku permission result listener; process started")
        refreshStatus()
        mainHandler.postDelayed(statusTicker, 1000)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) {
            ReceiverLogger.log("WARN", "Legacy Android requires WRITE_EXTERNAL_STORAGE to save logs in public Downloads; requesting it.")
            requestPermissions(
                arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQUEST_DOWNLOADS_PERMISSION
            )
        }
    }

    private fun requestShizuku() {
        if (binding) {
            ReceiverLogger.log("WARN", "Start tapped while a Shizuku bind is already pending; duplicate request ignored")
            showStatus(statusText("Already connecting to Shizuku. Waiting for its callback or timeout."))
            return
        }
        if (startInFlight) {
            ReceiverLogger.log("WARN", "Start tapped while receiver startup is already running; duplicate request ignored")
            return
        }
        if (service != null) {
            ReceiverLogger.log("INFO", "A service proxy already exists; verifying/starting receiver off the UI thread")
            startRequested = true
            startReceiver()
            return
        }
        if (permissionCheckInFlight) {
            ReceiverLogger.log("WARN", "Shizuku state check already in progress; duplicate request ignored")
            return
        }
        permissionCheckInFlight = true
        showStatus(statusText("Checking Shizuku connection..."))
        ioExecutor.execute {
            try {
                ReceiverLogger.log("INFO", "Checking Shizuku binder")
                val ping = Shizuku.pingBinder()
                ReceiverLogger.log("INFO", "Shizuku.pingBinder()=" + ping)
                val isOld = if (ping) Shizuku.isPreV11() else false
                ReceiverLogger.log("INFO", "Shizuku.isPreV11()=" + isOld)
                val granted = if (ping && !isOld) {
                    Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
                } else false
                val rationale = if (ping && !isOld && !granted) {
                    Shizuku.shouldShowRequestPermissionRationale()
                } else false
                ReceiverLogger.log(
                    "INFO",
                    "Shizuku check completed: binder=" + ping + " oldVersion=" + isOld +
                        " permissionGranted=" + granted + " shouldShowRationale=" + rationale
                )
                mainHandler.post {
                    permissionCheckInFlight = false
                    when {
                        !ping -> showStatus(statusText("Shizuku is not connected. Start Shizuku on the TV, then press Start."), "ERROR")
                        isOld -> showStatus(statusText("Shizuku is outdated. Update Shizuku on the TV."), "ERROR")
                        granted -> bindReceiver()
                        rationale -> showStatus(statusText("Shizuku permission was denied before. Grant it in Shizuku, then press Start."), "WARN")
                        else -> {
                            showStatus(statusText("Requesting Shizuku permission..."))
                            try {
                                ReceiverLogger.log("INFO", "Calling Shizuku.requestPermission(requestCode=" + REQUEST_SHIZUKU + ")")
                                Shizuku.requestPermission(REQUEST_SHIZUKU)
                            } catch (error: Exception) {
                                ReceiverLogger.log("ERROR", "Shizuku.requestPermission threw", error)
                                showStatus(statusText("Could not request Shizuku permission: " +
                                    (error.message ?: error.javaClass.simpleName)), "ERROR")
                            }
                        }
                    }
                }
            } catch (error: Exception) {
                ReceiverLogger.log("ERROR", "Exception while checking Shizuku binder/permission state", error)
                mainHandler.post {
                    permissionCheckInFlight = false
                    showStatus(statusText("Shizuku check failed: " +
                        (error.message ?: error.javaClass.simpleName)), "ERROR")
                }
            }
        }
    }

    private fun bindReceiver() {
        if (service != null) {
            ReceiverLogger.log("INFO", "bindReceiver skipped because service proxy already exists")
            startReceiver()
            return
        }
        if (binding) {
            ReceiverLogger.log("WARN", "bindReceiver ignored because binding is already true")
            return
        }
        binding = true
        bound = true
        startRequested = true
        bindAttemptId += 1
        val thisAttempt = bindAttemptId
        showStatus(statusText("Connecting to Shizuku..."))
        ReceiverLogger.log(
            "INFO",
            "Starting Shizuku bind attempt=" + thisAttempt + " timeoutMs=" + BIND_TIMEOUT_MS +
                " component=" + BuildConfig.APPLICATION_ID + "/" + GamepadUserService::class.java.name
        )
        bindTimeout?.let { mainHandler.removeCallbacks(it) }
        val timeout = Runnable {
            if (binding && service == null && bindAttemptId == thisAttempt) {
                ReceiverLogger.log("ERROR", "Shizuku bind timed out after " + BIND_TIMEOUT_MS +
                    " ms; no onServiceConnected callback received")
                binding = false
                startRequested = false
                val shouldUnbind = bound
                bound = false
                showStatus(
                    statusText("Timed out waiting for Shizuku service binding. Check that Shizuku is Started, grant this app permission, and press Start again."),
                    "ERROR"
                )
                if (shouldUnbind) ioExecutor.execute {
                    try {
                        ReceiverLogger.log("INFO", "Unbinding timed-out Shizuku attempt=" + thisAttempt)
                        Shizuku.unbindUserService(userServiceArgs, connection, false)
                        ReceiverLogger.log("INFO", "Timed-out Shizuku binding unbind request returned")
                    } catch (error: Exception) {
                        ReceiverLogger.log("ERROR", "Unbind after Shizuku bind timeout failed", error)
                    }
                }
            }
        }
        bindTimeout = timeout
        mainHandler.postDelayed(timeout, BIND_TIMEOUT_MS)

        ioExecutor.execute {
            try {
                ReceiverLogger.log("INFO", "Calling Shizuku.bindUserService on background thread")
                Shizuku.bindUserService(userServiceArgs, connection)
                ReceiverLogger.log("INFO", "Shizuku.bindUserService returned normally; waiting for onServiceConnected")
            } catch (error: Exception) {
                ReceiverLogger.log("ERROR", "Shizuku.bindUserService threw", error)
                mainHandler.post {
                    if (thisAttempt != bindAttemptId) return@post
                    bindTimeout?.let { mainHandler.removeCallbacks(it) }
                    bindTimeout = null
                    binding = false
                    bound = false
                    startRequested = false
                    showStatus(statusText("Could not bind Shizuku service: " +
                        (error.message ?: error.javaClass.simpleName)), "ERROR")
                }
                try {
                    Shizuku.unbindUserService(userServiceArgs, connection, false)
                } catch (unbindError: Exception) {
                    ReceiverLogger.log("WARN", "Cleanup after bind exception also failed", unbindError)
                }
            }
        }
    }

    private fun startReceiver() {
        val current = service
        if (current == null) {
            ReceiverLogger.log("ERROR", "startReceiver called with no service binder")
            showStatus(statusText("Shizuku connected without a service binder. Press Start to retry."), "ERROR")
            return
        }
        if (startInFlight) {
            ReceiverLogger.log("WARN", "startReceiver ignored because a start attempt is already in progress")
            return
        }
        startRequested = false
        startInFlight = true
        startAttemptId += 1
        val thisAttempt = startAttemptId
        showStatus(statusText("Shizuku connected. Starting virtual gamepad..."))
        ReceiverLogger.log("INFO", "Receiver start attempt=" + thisAttempt + " beginning on background thread; port=" + PORT)
        startTimeout?.let { mainHandler.removeCallbacks(it) }
        val timeout = Runnable {
            if (startInFlight && startAttemptId == thisAttempt) {
                startInFlight = false
                ReceiverLogger.log("ERROR", "Receiver startup Binder call exceeded " + START_TIMEOUT_MS + " ms")
                showStatus(
                    statusText("Receiver startup timed out while communicating with Shizuku. Check the log file and restart Shizuku."),
                    "ERROR"
                )
            }
        }
        startTimeout = timeout
        mainHandler.postDelayed(timeout, START_TIMEOUT_MS)

        ioExecutor.execute {
            try {
                val wasRunning = current.isRunning()
                ReceiverLogger.log("INFO", "Remote service isRunning()=" + wasRunning)
                val started = if (wasRunning) true else current.start(PORT)
                ReceiverLogger.log("INFO", "Remote service start(" + PORT + ") returned=" + started)
                val detail = current.lastError()
                val packets = current.packetsReceived()
                val remoteLog = current.drainLogs()
                mainHandler.post {
                    if (thisAttempt != startAttemptId) return@post
                    startTimeout?.let { mainHandler.removeCallbacks(it) }
                    startTimeout = null
                    startInFlight = false
                    appendServiceLog(remoteLog)
                    if (started) {
                        ReceiverLogger.log("INFO", "Receiver start completed; packetsReceived=" + packets)
                        refreshStatus()
                    } else {
                        val reason = if (detail.isNullOrBlank()) "TV could not register the virtual gamepad." else detail
                        ReceiverLogger.log("ERROR", "Receiver start failed: " + reason)
                        showStatus(statusText("Receiver startup failed: " + reason), "ERROR")
                    }
                }
            } catch (error: Exception) {
                ReceiverLogger.log("ERROR", "Remote call failed during receiver startup", error)
                mainHandler.post {
                    if (thisAttempt != startAttemptId) return@post
                    startTimeout?.let { mainHandler.removeCallbacks(it) }
                    startTimeout = null
                    startInFlight = false
                    showStatus(statusText("Receiver startup failed: " +
                        (error.message ?: error.javaClass.simpleName)), "ERROR")
                }
            }
        }
    }

    private fun stopReceiver() {
        startRequested = false
        startTimeout?.let { mainHandler.removeCallbacks(it) }
        startTimeout = null
        val current = service
        if (current == null) {
            ReceiverLogger.log("INFO", "Stop requested while no Shizuku service was bound")
            showStatus(statusText("Receiver stopped. Press Start to reconnect."))
            return
        }
        showStatus(statusText("Stopping receiver..."))
        ioExecutor.execute {
            try {
                current.stop()
                ReceiverLogger.log("INFO", "Remote receiver stop() completed")
                val remoteLog = current.drainLogs()
                mainHandler.post {
                    appendServiceLog(remoteLog)
                    showStatus(statusText("Receiver stopped. Press Start to restart."))
                }
            } catch (error: Exception) {
                ReceiverLogger.log("ERROR", "Remote receiver stop() failed", error)
                mainHandler.post {
                    showStatus(statusText("Could not stop receiver: " +
                        (error.message ?: error.javaClass.simpleName)), "ERROR")
                }
            }
        }
    }

    private fun refreshStatus() {
        if (!::statusView.isInitialized) return
        val ip = localIp()
        val current = service
        if (current == null) {
            val detail = when {
                binding -> "Connecting to Shizuku..."
                permissionCheckInFlight -> "Checking Shizuku connection..."
                startInFlight -> "Starting virtual gamepad..."
                else -> "Ready. Press Start."
            }
            showStatus(statusText(detail, ip))
            return
        }
        if (statusCheckInFlight || startInFlight) return
        statusCheckInFlight = true
        ioExecutor.execute {
            try {
                val running = current.isRunning()
                val packets = current.packetsReceived()
                val errorText = current.lastError()
                val remoteLog = current.drainLogs()
                mainHandler.post {
                    statusCheckInFlight = false
                    if (service !== current) {
                        appendServiceLog(remoteLog)
                        return@post
                    }
                    appendServiceLog(remoteLog)
                    if (startInFlight) return@post
                    val detail = when {
                        running -> "Listening for NES controller\nPackets received: " + packets
                        !errorText.isNullOrBlank() -> "Not running. " + errorText
                        else -> "Not running. Press Start to start the receiver."
                    }
                    showStatus(statusText(detail, ip), if (running) "INFO" else "WARN")
                }
            } catch (error: Exception) {
                ReceiverLogger.log("ERROR", "Periodic Shizuku/service status query failed", error)
                mainHandler.post {
                    statusCheckInFlight = false
                    if (service === current) markServiceLost("Shizuku service call failed. Restart Shizuku, then press Start.")
                }
            }
        }
    }

    private fun appendServiceLog(contents: String) {
        if (contents.isBlank()) return
        contents.lineSequence().filter { it.isNotBlank() }.forEach {
            ReceiverLogger.log("SERVICE", it)
        }
    }

    private fun markServiceLost(message: String) {
        bindTimeout?.let { mainHandler.removeCallbacks(it) }
        bindTimeout = null
        startTimeout?.let { mainHandler.removeCallbacks(it) }
        startTimeout = null
        binding = false
        bound = false
        startRequested = false
        startInFlight = false
        service = null
        ReceiverLogger.log("ERROR", message)
        showStatus(statusText(message), "ERROR")
    }

    private fun statusText(detail: String, ip: String = localIp()): String =
        "IP: " + ip + "    Port: " + PORT + "\n" + detail +
            "\nLogs: " + ReceiverLogger.destinationLabel()

    private fun showStatus(message: String, level: String = "INFO") {
        if (!::statusView.isInitialized) return
        if (lastUiStatus != message) {
            ReceiverLogger.log(level, "UI status changed: " + message.replace("\n", " | "))
            lastUiStatus = message
        }
        statusView.text = message
    }

    private fun localIp(): String {
        return try {
            val candidates = ArrayList<Pair<Int, String>>()
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return "unknown"
            while (interfaces.hasMoreElements()) {
                val networkInterface = interfaces.nextElement()
                if (!networkInterface.isUp || networkInterface.isLoopback) continue
                val addresses = networkInterface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()
                    if (address !is Inet4Address || address.isLoopbackAddress ||
                        address.isLinkLocalAddress || !address.isSiteLocalAddress
                    ) continue
                    val name = networkInterface.name.lowercase()
                    val rank = when {
                        name.contains("wlan") || name.contains("wifi") -> 0
                        name.startsWith("eth") -> 1
                        else -> 2
                    }
                    val host = address.hostAddress
                    if (host != null) candidates.add(rank to host)
                }
            }
            candidates.sortedBy { it.first }.firstOrNull()?.second ?: "unknown"
        } catch (error: Exception) {
            val description = error.javaClass.simpleName + ": " + (error.message ?: "")
            if (description != lastIpError) {
                lastIpError = description
                ReceiverLogger.log("ERROR", "Could not discover a local IPv4 address", error)
            }
            "unknown"
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_DOWNLOADS_PERMISSION) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            ReceiverLogger.log(if (granted) "INFO" else "WARN", "Legacy Downloads permission result granted=" + granted)
            if (granted) ReceiverLogger.reinitialize(this)
            refreshStatus()
        }
    }

    override fun onResume() {
        super.onResume()
        ReceiverLogger.log("INFO", "Activity onResume")
    }

    override fun onPause() {
        ReceiverLogger.log("INFO", "Activity onPause")
        super.onPause()
    }

    override fun onDestroy() {
        ReceiverLogger.log("INFO", "Activity onDestroy; cleaning up service binding")
        mainHandler.removeCallbacksAndMessages(null)
        Shizuku.removeRequestPermissionResultListener(permissionListener)
        val current = service
        val wasBound = bound
        service = null
        bound = false
        binding = false
        if (current != null || wasBound) {
            ioExecutor.execute {
                try {
                    current?.stop()
                    ReceiverLogger.log("INFO", "onDestroy service stop completed")
                } catch (error: Exception) {
                    ReceiverLogger.log("ERROR", "onDestroy service stop failed", error)
                }
                if (wasBound) {
                    try {
                        Shizuku.unbindUserService(userServiceArgs, connection, true)
                        ReceiverLogger.log("INFO", "onDestroy unbind completed")
                    } catch (error: Exception) {
                        ReceiverLogger.log("WARN", "onDestroy unbind failed", error)
                    }
                }
            }
        }
        super.onDestroy()
    }
}
'''


controller_activity = r'''package com.tomastharwat.nintendo_nes

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
'''

user_service = r'''package com.tomastharwat.nintendo_nes

import android.os.Process as AndroidProcess
import android.util.Log
import java.util.ArrayDeque
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class GamepadUserService : IGamepadService.Stub() {
    companion object {
        private const val MAGIC = 0x4e
        private const val VERSION = 2
        private const val INPUT = 0
        private const val ACK = 1
        private const val PACKET_SIZE = 8
        private const val FAILSAFE_TIMEOUT_NANOS = 750_000_000L
        private const val UINT32_MOD = 0x1_0000_0000L
        private const val UINT32_HALF = 0x8000_0000L
    }

    @Volatile private var socket: DatagramSocket? = null
    @Volatile private var uinputProcess: Process? = null
    @Volatile private var pad: UinputGamepad? = null
    private val running = AtomicBoolean(false)
    private val received = AtomicLong(0)
    private val inputLock = Any()
    @Volatile private var error = ""
    private var peerAddress: InetAddress? = null
    private var peerPort = -1
    private var lastSequence = -1L
    @Volatile private var lastPacketNanos = 0L
    private var lastLoggedMask = -1
    private val diagnosticLock = Any()
    private val diagnosticLines = ArrayDeque<String>()

    private fun diagnostic(level: String, message: String, error: Throwable? = null) {
        val stack = error?.let { Log.getStackTraceString(it).replace("\r", "") }
        val line = System.currentTimeMillis().toString() + " [" + level + "] [thread=" +
            Thread.currentThread().name + "] " + message + if (stack.isNullOrBlank()) "" else " | " + stack
        val priority = when (level) {
            "ERROR" -> Log.ERROR
            "WARN" -> Log.WARN
            "DEBUG" -> Log.DEBUG
            else -> Log.INFO
        }
        Log.println(priority, "NESGamepadUserService", line)
        synchronized(diagnosticLock) {
            while (diagnosticLines.size >= 256) diagnosticLines.removeFirst()
            diagnosticLines.addLast(line.take(3000))
        }
    }

    @Synchronized
    override fun start(port: Int): Boolean {
        diagnostic("INFO", "start(port=" + port + ") called running=" + running.get())
        if (running.get() && uinputProcess?.isAlive == true && socket?.isClosed == false) {
            diagnostic("INFO", "start ignored: receiver is already running")
            return true
        }
        error = ""
        received.set(0)
        stop()
        var process: Process? = null
        var datagramSocket: DatagramSocket? = null
        return try {
            diagnostic("INFO", "Launching shell uinput process")
            val runningProcess = ProcessBuilder("uinput", "-").redirectErrorStream(true).start()
            process = runningProcess
            uinputProcess = runningProcess
            diagnostic("INFO", "uinput process started; alive=" + runningProcess.isAlive)
            Thread({
                try {
                    runningProcess.inputStream.bufferedReader().forEachLine { line ->
                        diagnostic(if (line.contains("error", true) || line.contains("fail", true)) "WARN" else "DEBUG",
                            "uinput output: " + line)
                        if (line.contains("error", true)) error = line.take(300)
                    }
                } catch (readError: Exception) {
                    diagnostic("WARN", "Reading uinput output stream failed", readError)
                }
                val exitCode = try { runningProcess.waitFor() } catch (waitError: Exception) {
                    diagnostic("ERROR", "Waiting for uinput exit code failed", waitError)
                    -1
                }
                diagnostic("WARN", "uinput output stream closed; exitCode=" + exitCode + " running=" + running.get())
                if (running.get()) {
                    error = "uinput process ended (exit code: " + exitCode + ")"
                    diagnostic("ERROR", error)
                    stop()
                }
            }, "nes-uinput-drain").apply { isDaemon = true; start() }

            diagnostic("INFO", "Creating virtual gamepad uinput configuration")
            val device = UinputGamepad(runningProcess.outputStream)
            pad = device
            device.register()
            diagnostic("INFO", "Virtual gamepad registration commands written; processAlive=" + runningProcess.isAlive)
            device.setMask(0)
            lastLoggedMask = 0
            if (!runningProcess.isAlive) throw IllegalStateException("uinput exited during registration")

            val activeSocket = DatagramSocket(null)
            datagramSocket = activeSocket
            activeSocket.reuseAddress = true
            diagnostic("INFO", "Binding UDP receiver socket on port=" + port)
            activeSocket.bind(InetSocketAddress(port))
            socket = activeSocket
            synchronized(inputLock) {
                peerAddress = null
                peerPort = -1
                lastSequence = -1L
                lastPacketNanos = System.nanoTime()
            }
            running.set(true)
            diagnostic("INFO", "UDP socket bound; starting packet receiver and failsafe threads")
            Thread({ receiveLoop(activeSocket, device) }, "nes-udp-receiver").apply {
                isDaemon = true
                priority = Thread.MAX_PRIORITY
                start()
            }
            Thread({ failsafeLoop(device) }, "nes-input-failsafe").apply {
                isDaemon = true
                start()
            }
            diagnostic("INFO", "Receiver started successfully on UDP port=" + port)
            true
        } catch (e: Exception) {
            error = e.javaClass.simpleName + ": " + (e.message ?: "Could not start the NES receiver.")
            diagnostic("ERROR", "Receiver startup failed: " + error, e)
            running.set(false)
            try { datagramSocket?.close() } catch (closeError: Exception) { diagnostic("WARN", "Closing failed startup socket threw", closeError) }
            try { pad?.injectNeutral() } catch (neutralError: Exception) { diagnostic("WARN", "Neutralizing failed startup gamepad threw", neutralError) }
            try { process?.outputStream?.close() } catch (closeError: Exception) { diagnostic("WARN", "Closing failed startup uinput stream threw", closeError) }
            try { process?.destroy() } catch (destroyError: Exception) { diagnostic("WARN", "Destroying failed startup uinput process threw", destroyError) }
            socket = null
            uinputProcess = null
            pad = null
            false
        }
    }

    private fun receiveLoop(sock: DatagramSocket, device: UinputGamepad) {
        diagnostic("INFO", "UDP receive loop started localPort=" + sock.localPort)
        val buffer = ByteArray(64)
        val packet = DatagramPacket(buffer, buffer.size)
        while (running.get()) {
            try {
                packet.length = buffer.size
                sock.receive(packet)
                handlePacket(sock, packet, device)
            } catch (e: Exception) {
                if (running.get()) {
                    error = e.javaClass.simpleName + ": " + (e.message ?: "NES UDP receiver failed.")
                    diagnostic("ERROR", "UDP receive loop failed", e)
                    stop()
                }
            }
        }
    }

    private fun handlePacket(sock: DatagramSocket, packet: DatagramPacket, device: UinputGamepad) {
        if (packet.length != PACKET_SIZE) return
        val data = packet.data
        if ((data[0].toInt() and 0xff) != MAGIC ||
            (data[1].toInt() and 0xff) != VERSION ||
            (data[2].toInt() and 0xff) != INPUT
        ) return

        val sequence = (data[3].toLong() and 0xffL) or
            ((data[4].toLong() and 0xffL) shl 8) or
            ((data[5].toLong() and 0xffL) shl 16) or
            ((data[6].toLong() and 0xffL) shl 24)
        val mask = data[7].toInt() and 0xff
        val sender = packet.address
        val senderPort = packet.port
        var accepted = false

        synchronized(inputLock) {
            if (!running.get()) return@synchronized
            val now = System.nanoTime()
            val samePeer = peerAddress?.hostAddress == sender.hostAddress && peerPort == senderPort
            if (peerAddress != null && !samePeer) {
                if (now - lastPacketNanos <= FAILSAFE_TIMEOUT_NANOS) return@synchronized
                device.setMask(0)
                peerAddress = null
                peerPort = -1
                lastSequence = -1L
            }
            if (peerAddress == null) {
                peerAddress = sender
                peerPort = senderPort
                lastSequence = -1L
                diagnostic("INFO", "Accepted first controller peer " + sender.hostAddress + ":" + senderPort)
            }
            if (!isNewerSequence(sequence, lastSequence)) return@synchronized
            device.setMask(mask)
            if (mask != lastLoggedMask) {
                diagnostic("INFO", "Input mask changed from=0x" + lastLoggedMask.toString(16) +
                    " to=0x" + mask.toString(16) + " peer=" + sender.hostAddress + ":" + senderPort +
                    " sequence=" + sequence)
                lastLoggedMask = mask
            }
            lastSequence = sequence
            lastPacketNanos = now
            val total = received.incrementAndGet()
            if (total % 120L == 0L) {
                diagnostic("DEBUG", "Accepted UDP packets=" + total + " sequence=" + sequence +
                    " mask=0x" + mask.toString(16) + " peer=" + sender.hostAddress + ":" + senderPort)
            }
            accepted = true
        }

        if (!accepted) return
        val acknowledgement = byteArrayOf(
            MAGIC.toByte(), VERSION.toByte(), ACK.toByte(),
            (sequence and 0xffL).toByte(),
            ((sequence shr 8) and 0xffL).toByte(),
            ((sequence shr 16) and 0xffL).toByte(),
            ((sequence shr 24) and 0xffL).toByte(),
            1.toByte()
        )
        try {
            sock.send(DatagramPacket(acknowledgement, acknowledgement.size, sender, senderPort))
        } catch (e: Exception) {
            if (running.get()) error = e.message ?: "Could not send controller acknowledgement."
        }
    }

    private fun isNewerSequence(incoming: Long, previous: Long): Boolean {
        if (previous < 0L) return true
        val difference = (incoming - previous + UINT32_MOD) % UINT32_MOD
        return difference != 0L && difference < UINT32_HALF
    }

    private fun failsafeLoop(device: UinputGamepad) {
        while (running.get()) {
            try { Thread.sleep(100) } catch (_: InterruptedException) { return }
            if (!running.get()) return
            try {
                synchronized(inputLock) {
                    if (running.get() && peerAddress != null &&
                        System.nanoTime() - lastPacketNanos > FAILSAFE_TIMEOUT_NANOS
                    ) {
                        diagnostic("WARN", "Controller peer timed out; releasing buttons for " +
                            (peerAddress?.hostAddress ?: "unknown") + ":" + peerPort)
                        device.setMask(0)
                        lastLoggedMask = 0
                        peerAddress = null
                        peerPort = -1
                        lastSequence = -1L
                    }
                }
            } catch (e: Exception) {
                error = e.javaClass.simpleName + ": " + (e.message ?: "NES input failsafe failed.")
                diagnostic("ERROR", "Input failsafe failed", e)
                stop()
                return
            }
        }
    }

    override fun setButtons(mask: Int) {
        synchronized(inputLock) {
            val device = pad ?: throw IllegalStateException("Virtual gamepad is not registered.")
            if (!running.get()) throw IllegalStateException("NES receiver is not running.")
            val cleanMask = mask and 0xff
            if (cleanMask != lastLoggedMask) diagnostic("INFO", "Local setButtons mask=0x" + cleanMask.toString(16))
            device.setMask(cleanMask)
            lastLoggedMask = cleanMask
        }
    }

    @Synchronized
    override fun stop() {
        diagnostic("INFO", "stop() called running=" + running.get() + " packetsReceived=" + received.get())
        running.set(false)
        synchronized(inputLock) {
            peerAddress = null
            peerPort = -1
            lastSequence = -1L
            try { pad?.injectNeutral() } catch (_: Exception) { }
            val currentSocket = socket
            socket = null
            try { currentSocket?.close() } catch (_: Exception) { }
            val currentProcess = uinputProcess
            uinputProcess = null
            try { currentProcess?.outputStream?.close() } catch (_: Exception) { }
            try { currentProcess?.destroy() } catch (_: Exception) { }
            pad = null
            lastLoggedMask = 0
        }
        diagnostic("INFO", "stop() completed; uinput/socket references cleared")
    }

    override fun isRunning(): Boolean =
        running.get() && uinputProcess?.isAlive == true && socket?.isClosed == false

    override fun lastError(): String = error
    override fun packetsReceived(): Long = received.get()

    override fun drainLogs(): String = synchronized(diagnosticLock) {
        val output = StringBuilder()
        var count = 0
        while (diagnosticLines.isNotEmpty() && count < 80 && output.length < 200_000) {
            output.append(diagnosticLines.removeFirst()).append('\n')
            count++
        }
        output.toString()
    }

    override fun destroy() {
        diagnostic("INFO", "Shizuku user service destroy() invoked")
        stop()
        AndroidProcess.killProcess(AndroidProcess.myPid())
    }
}
'''

uinput = r'''package com.tomastharwat.nintendo_nes

import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStream

class UinputGamepad(private val output: OutputStream) {
    companion object {
        private const val ID = 1
        private const val SET_EV = 100
        private const val SET_KEY = 101
        private const val EV_KEY = 1
        private const val BTN_A = 304
        private const val BTN_B = 305
        private const val BTN_SELECT = 314
        private const val BTN_START = 315
        private const val BTN_DPAD_UP = 0x220
        private const val BTN_DPAD_DOWN = 0x221
        private const val BTN_DPAD_LEFT = 0x222
        private const val BTN_DPAD_RIGHT = 0x223
    }

    private val line = StringBuilder(256)
    private var previousMask = -1
    private val buttonKeyMap = listOf(
        1 to BTN_A,
        2 to BTN_B,
        4 to BTN_SELECT,
        8 to BTN_START,
        16 to BTN_DPAD_UP,
        32 to BTN_DPAD_DOWN,
        64 to BTN_DPAD_LEFT,
        128 to BTN_DPAD_RIGHT,
    )

    fun register() {
        val configuration = JSONArray().apply {
            put(cfg(SET_EV, listOf(EV_KEY)))
            put(cfg(SET_KEY, buttonKeyMap.map { it.second }))
        }
        write(JSONObject().apply {
            put("id", ID)
            put("command", "register")
            put("name", "Nintendo Switch Pro Controller")
            put("vid", 0x057e)
            put("pid", 0x2009)
            put("bus", "usb")
            put("configuration", configuration)
        })
        write(JSONObject().apply {
            put("id", ID)
            put("command", "delay")
            put("duration", 300)
        })
    }

    @Synchronized
    fun setMask(mask: Int) {
        var state = mask and 0xff
        if ((state and 0xc0) == 0xc0) state = state and 0x3f
        if ((state and 0x30) == 0x30) state = state and 0xcf
        if (state == previousMask) return

        val events = ArrayList<Int>(24)
        fun add(type: Int, code: Int, value: Int) {
            events.add(type)
            events.add(code)
            events.add(value)
        }
        for ((bit, key) in buttonKeyMap) {
            val wasPressed = previousMask >= 0 && (previousMask and bit) != 0
            val isPressed = (state and bit) != 0
            if (previousMask < 0 || wasPressed != isPressed) {
                add(EV_KEY, key, if (isPressed) 1 else 0)
            }
        }
        previousMask = state
        inject(events)
    }

    @Synchronized
    fun injectNeutral() {
        previousMask = -1
        setMask(0)
    }

    private fun inject(events: List<Int>) {
        if (events.isEmpty()) return
        line.setLength(0)
        line.append("""{"id":1,"command":"inject","events":[""")
        for (i in events.indices step 3) {
            if (i > 0) line.append(',')
            line.append(events[i]).append(',')
                .append(events[i + 1]).append(',')
                .append(events[i + 2])
        }
        line.append(",0,0,0]}\n")
        output.write(line.toString().toByteArray(Charsets.UTF_8))
        output.flush()
    }

    private fun write(obj: JSONObject) {
        line.setLength(0)
        line.append(obj.toString()).append('\n')
        output.write(line.toString().toByteArray(Charsets.UTF_8))
        output.flush()
    }

    private fun cfg(type: Int, values: List<Int>) = JSONObject().apply {
        put("type", type)
        put("data", JSONArray(values))
    }
}
'''

aidl = r'''package com.tomastharwat.nintendo_nes;
interface IGamepadService {
    boolean start(int port);
    void setButtons(int mask);
    void stop();
    boolean isRunning();
    String lastError();
    long packetsReceived();
    String drainLogs();
    void destroy();
}
'''
def write(path, content):
 path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
 if not path.exists() or path.read_text(encoding="utf-8") != content:
  path.write_text(content, encoding="utf-8")

gradle = Path("android/app/build.gradle.kts")
if not gradle.is_file():
    raise SystemExit("Generated Android Gradle file is missing.")
g = gradle.read_text(encoding="utf-8")

# Flutter/AGP templates can omit the app-level dependencies block.
dependencies = (
    'implementation("dev.rikka.shizuku:api:13.1.5")',
    'implementation("dev.rikka.shizuku:provider:13.1.5")',
)
missing = [dependency for dependency in dependencies if dependency not in g]
if missing:
    match = re.search(r'dependencies\s*\{', g)
    lines = "".join("    " + dependency + "\n" for dependency in missing)
    if match:
        g = g[:match.end()] + "\n" + lines + g[match.end():]
    else:
        g = g.rstrip() + "\n\ndependencies {\n" + lines + "}\n"

# AIDL generates IGamepadService.Stub; BuildConfig.APPLICATION_ID is referenced
# in MainActivity. Modern Android Gradle Plugin templates may disable both.
features = ("aidl", "buildConfig")
match = re.search(r'buildFeatures\s*\{[^}]*\}', g, re.S)
if match:
    block = match.group(0)
    replacement = block[:-1]
    for feature in features:
        if re.search(r'^\s*' + re.escape(feature) + r'\s*=\s*true\s*$', block, re.M) is None:
            replacement += "\n        " + feature + " = true"
    replacement += "\n    }"
    g = g[:match.start()] + replacement + g[match.end():]
else:
    android = re.search(r'android\s*\{', g)
    if not android:
        raise SystemExit("Could not find the Android Gradle configuration block.")
    block = "\n    buildFeatures {\n        aidl = true\n        buildConfig = true\n    }\n"
    g = g[:android.end()] + block + g[android.end():]

for dependency in dependencies:
    if dependency not in g:
        raise SystemExit("Required Shizuku dependency is missing: " + dependency)
for feature in features:
    if re.search(r'^\s*' + re.escape(feature) + r'\s*=\s*true\s*$', g, re.M) is None:
        raise SystemExit("Required Android build feature is disabled: " + feature)

gradle.write_text(g, encoding="utf-8")
print("Configured Shizuku dependencies, AIDL generation, and BuildConfig.")
manifest = root / "AndroidManifest.xml"
xml = manifest.read_text(encoding="utf-8")
legacy_log_permission = '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />'
if "android.permission.WRITE_EXTERNAL_STORAGE" not in xml:
 xml = re.sub(r'(<manifest\b[^>]*>)', r'\1\n    ' + legacy_log_permission, xml, count=1)
if "moe.shizuku.privileged.api" not in xml:
 xml = re.sub(r'(<application\b)', '<queries>\n        <package android:name="moe.shizuku.privileged.api" />\n    </queries>\n\n    \\1', xml, count=1)
provider = '''        <provider
            android:name="rikka.shizuku.ShizukuProvider"
            android:authorities="'''+ "$" + '''{applicationId}.shizuku"
            android:multiprocess="false"
            android:enabled="true"
            android:exported="true"
            android:permission="android.permission.INTERACT_ACROSS_USERS_FULL" />'''
if "rikka.shizuku.ShizukuProvider" not in xml:
 xml = xml.replace("</application>", provider + "\n    </application>")
manifest.write_text(xml, encoding="utf-8")
default_main_activity = kotlin / "MainActivity.kt"
if default_main_activity.exists():
    default_main_activity.unlink()
write(controller_kotlin / "MainActivity.kt", controller_activity)
write(kotlin / "ReceiverLogger.kt", receiver_logger)
write(receiver_kotlin / "MainActivity.kt", main)
write(kotlin / "GamepadUserService.kt", user_service)
write(kotlin / "UinputGamepad.kt", uinput)
write(aidl_dir / "IGamepadService.aidl", aidl)
print("Generated Shizuku/uinput system-gamepad bridge.")
