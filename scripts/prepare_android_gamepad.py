#!/usr/bin/env python3
"""Generate the native Shizuku/uinput bridge in Flutter's generated Android project."""
from pathlib import Path
import re

root = Path("android/app/src/main")
kotlin = root / "kotlin/com/tomastharwat/nintendo_nes"
receiver_kotlin = Path("android/app/src/receiver/kotlin/com/tomastharwat/nintendo_nes")
controller_kotlin = Path("android/app/src/controller/kotlin/com/tomastharwat/nintendo_nes")
aidl_dir = root / "aidl/com/tomastharwat/nintendo_nes"

main = r'''
package com.tomastharwat.nintendo_nes

import android.app.Activity
import android.content.ComponentName
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
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
    ).daemon(false).processNameSuffix("gamepad").debuggable(false).tag("nintendo-nes-gamepad").version(4)

    private val permissionListener = Shizuku.OnRequestPermissionResultListener { code, grant ->
        mainHandler.post {

            if (code == REQUEST_SHIZUKU) {
                if (grant == PackageManager.PERMISSION_GRANTED) {
                    bindReceiver()
                } else {
                    startRequested = false
                    showStatus(statusText("Shizuku permission denied. Grant permission in Shizuku, then press Start."))
                }
            }
        }
    }

    private val connection: ServiceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {

            mainHandler.post {
                bindTimeout?.let { mainHandler.removeCallbacks(it) }
                bindTimeout = null
                binding = false
                bound = true
                service = IGamepadService.Stub.asInterface(binder)

                if (startRequested) startReceiver() else refreshStatus()
            }
        }

        override fun onServiceDisconnected(name: ComponentName) {

            mainHandler.post { markServiceLost("Shizuku service disconnected. Press Start to reconnect.") }
        }

        override fun onBindingDied(name: ComponentName) {

            mainHandler.post { markServiceLost("Shizuku binding died. Restart Shizuku on the TV, then press Start.") }
        }

        override fun onNullBinding(name: ComponentName) {

            mainHandler.post { markServiceLost("Shizuku returned an empty service binding. Check Shizuku and app permissions.") }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)


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

        refreshStatus()
        mainHandler.postDelayed(statusTicker, 1000)

    }

    private fun requestShizuku() {
        if (binding) {

            showStatus(statusText("Already connecting to Shizuku. Waiting for its callback or timeout."))
            return
        }
        if (startInFlight) {

            return
        }
        if (service != null) {

            startRequested = true
            startReceiver()
            return
        }
        if (permissionCheckInFlight) {

            return
        }
        permissionCheckInFlight = true
        showStatus(statusText("Checking Shizuku connection..."))
        ioExecutor.execute {
            try {

                val ping = Shizuku.pingBinder()

                val isOld = if (ping) Shizuku.isPreV11() else false

                val granted = if (ping && !isOld) {
                    Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
                } else false
                val rationale = if (ping && !isOld && !granted) {
                    Shizuku.shouldShowRequestPermissionRationale()
                } else false

                mainHandler.post {
                    permissionCheckInFlight = false
                    when {
                        !ping -> showStatus(statusText("Shizuku is not connected. Start Shizuku on the TV, then press Start."))
                        isOld -> showStatus(statusText("Shizuku is outdated. Update Shizuku on the TV."))
                        granted -> bindReceiver()
                        rationale -> showStatus(statusText("Shizuku permission was denied before. Grant it in Shizuku, then press Start."))
                        else -> {
                            showStatus(statusText("Requesting Shizuku permission..."))
                            try {

                                Shizuku.requestPermission(REQUEST_SHIZUKU)
                            } catch (error: Exception) {

                                showStatus(statusText("Could not request Shizuku permission: " +
                                    (error.message ?: error.javaClass.simpleName)))
                            }
                        }
                    }
                }
            } catch (error: Exception) {

                mainHandler.post {
                    permissionCheckInFlight = false
                    showStatus(statusText("Shizuku check failed: " +
                        (error.message ?: error.javaClass.simpleName)))
                }
            }
        }
    }

    private fun bindReceiver() {
        if (service != null) {

            startReceiver()
            return
        }
        if (binding) {

            return
        }
        binding = true
        bound = true
        startRequested = true
        bindAttemptId += 1
        val thisAttempt = bindAttemptId
        showStatus(statusText("Connecting to Shizuku..."))

        bindTimeout?.let { mainHandler.removeCallbacks(it) }
        val timeout = Runnable {
            if (binding && service == null && bindAttemptId == thisAttempt) {

                binding = false
                startRequested = false
                val shouldUnbind = bound
                bound = false
                showStatus(
                    statusText("Timed out waiting for Shizuku service binding. Check that Shizuku is Started, grant this app permission, and press Start again."))
                if (shouldUnbind) ioExecutor.execute {
                    try {

                        Shizuku.unbindUserService(userServiceArgs, connection, false)

                    } catch (error: Exception) {

                    }
                }
            }
        }
        bindTimeout = timeout
        mainHandler.postDelayed(timeout, BIND_TIMEOUT_MS)

        ioExecutor.execute {
            try {

                Shizuku.bindUserService(userServiceArgs, connection)

            } catch (error: Exception) {

                mainHandler.post {
                    if (thisAttempt != bindAttemptId) return@post
                    bindTimeout?.let { mainHandler.removeCallbacks(it) }
                    bindTimeout = null
                    binding = false
                    bound = false
                    startRequested = false
                    showStatus(statusText("Could not bind Shizuku service: " +
                        (error.message ?: error.javaClass.simpleName)))
                }
                try {
                    Shizuku.unbindUserService(userServiceArgs, connection, false)
                } catch (unbindError: Exception) {

                }
            }
        }
    }

    private fun startReceiver() {
        val current = service
        if (current == null) {

            showStatus(statusText("Shizuku connected without a service binder. Press Start to retry."))
            return
        }
        if (startInFlight) {

            return
        }
        startRequested = false
        startInFlight = true
        startAttemptId += 1
        val thisAttempt = startAttemptId
        showStatus(statusText("Shizuku connected. Starting virtual gamepad..."))

        startTimeout?.let { mainHandler.removeCallbacks(it) }
        val timeout = Runnable {
            if (startInFlight && startAttemptId == thisAttempt) {
                startInFlight = false

                showStatus(
                    statusText("Receiver startup timed out while communicating with Shizuku. Restart Shizuku and try again."))
            }
        }
        startTimeout = timeout
        mainHandler.postDelayed(timeout, START_TIMEOUT_MS)

        ioExecutor.execute {
            try {
                val wasRunning = current.isRunning()

                val started = if (wasRunning) true else current.start(PORT)

                val detail = current.lastError()
                val packets = current.packetsReceived()
                mainHandler.post {
                    if (thisAttempt != startAttemptId) return@post
                    startTimeout?.let { mainHandler.removeCallbacks(it) }
                    startTimeout = null
                    startInFlight = false
                    if (started) {

                        refreshStatus()
                    } else {
                        val reason = if (detail.isNullOrBlank()) "TV could not register the virtual gamepad." else detail

                        showStatus(statusText("Receiver startup failed: " + reason))
                    }
                }
            } catch (error: Exception) {

                mainHandler.post {
                    if (thisAttempt != startAttemptId) return@post
                    startTimeout?.let { mainHandler.removeCallbacks(it) }
                    startTimeout = null
                    startInFlight = false
                    showStatus(statusText("Receiver startup failed: " +
                        (error.message ?: error.javaClass.simpleName)))
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

            showStatus(statusText("Receiver stopped. Press Start to reconnect."))
            return
        }
        showStatus(statusText("Stopping receiver..."))
        ioExecutor.execute {
            try {
                current.stop()
                mainHandler.post {
                    showStatus(statusText("Receiver stopped. Press Start to restart."))
                }
            } catch (error: Exception) {

                mainHandler.post {
                    showStatus(statusText("Could not stop receiver: " +
                        (error.message ?: error.javaClass.simpleName)))
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
                mainHandler.post {
                    statusCheckInFlight = false
                    if (service !== current) return@post
                    if (startInFlight) return@post
                    val detail = when {
                        running -> "Listening for NES controller\nPackets received: " + packets
                        !errorText.isNullOrBlank() -> "Not running. " + errorText
                        else -> "Not running. Press Start to start the receiver."
                    }
                    showStatus(statusText(detail, ip))
                }
            } catch (error: Exception) {

                mainHandler.post {
                    statusCheckInFlight = false
                    if (service === current) markServiceLost("Shizuku service call failed. Restart Shizuku, then press Start.")
                }
            }
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

        showStatus(statusText(message))
    }

    private fun statusText(detail: String, ip: String = localIp()): String =
        "IP: " + ip + "    Port: " + PORT + "\n" + detail



    private fun showStatus(message: String) {
        if (!::statusView.isInitialized) return
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
        } catch (_: Exception) {
            "unknown"
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()


    override fun onResume() {
        super.onResume()

    }

    override fun onPause() {

        super.onPause()
    }

    override fun onDestroy() {

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

                } catch (error: Exception) {

                }
                if (wasBound) {
                    try {
                        Shizuku.unbindUserService(userServiceArgs, connection, true)

                    } catch (error: Exception) {

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


    @Synchronized
    override fun start(port: Int): Boolean {

        if (running.get() && uinputProcess?.isAlive == true && socket?.isClosed == false) {

            return true
        }
        error = ""
        received.set(0)
        stop()
        var process: Process? = null
        var datagramSocket: DatagramSocket? = null
        return try {

            val runningProcess = ProcessBuilder("uinput", "-").redirectErrorStream(true).start()
            process = runningProcess
            uinputProcess = runningProcess

            Thread({
                try {
                    runningProcess.inputStream.bufferedReader().use { reader ->
                        while (reader.readLine() != null) {
                            // Drain child output so its pipe cannot block.
                        }
                    }
                } catch (_: Exception) {
                }
                val exitCode = try { runningProcess.waitFor() } catch (_: Exception) { -1 }
                if (running.get()) {
                    error = "uinput process ended (exit code: " + exitCode + ")"
                    stop()
                }
            }, "nes-uinput-drain").apply { isDaemon = true; start() }


            val device = UinputGamepad(runningProcess.outputStream)
            pad = device
            device.register()

            device.setMask(0)
            if (!runningProcess.isAlive) throw IllegalStateException("uinput exited during registration")

            val activeSocket = DatagramSocket(null)
            datagramSocket = activeSocket
            activeSocket.reuseAddress = true

            activeSocket.bind(InetSocketAddress(port))
            socket = activeSocket
            synchronized(inputLock) {
                peerAddress = null
                peerPort = -1
                lastSequence = -1L
                lastPacketNanos = System.nanoTime()
            }
            running.set(true)

            Thread({ receiveLoop(activeSocket, device) }, "nes-udp-receiver").apply {
                isDaemon = true
                priority = Thread.MAX_PRIORITY
                start()
            }
            Thread({ failsafeLoop(device) }, "nes-input-failsafe").apply {
                isDaemon = true
                start()
            }

            true
        } catch (e: Exception) {
            error = e.javaClass.simpleName + ": " + (e.message ?: "Could not start the NES receiver.")

            running.set(false)
            try { datagramSocket?.close() } catch (_: Exception) { }
            try { pad?.injectNeutral() } catch (_: Exception) { }
            try { process?.outputStream?.close() } catch (_: Exception) { }
            try { process?.destroy() } catch (_: Exception) { }
            socket = null
            uinputProcess = null
            pad = null
            false
        }
    }

    private fun receiveLoop(sock: DatagramSocket, device: UinputGamepad) {

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

            }
            if (!isNewerSequence(sequence, lastSequence)) return@synchronized
            device.setMask(mask)
            lastSequence = sequence
            lastPacketNanos = now
            val total = received.incrementAndGet()
            if (total % 120L == 0L) {

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

                        device.setMask(0)
                        peerAddress = null
                        peerPort = -1
                        lastSequence = -1L
                    }
                }
            } catch (e: Exception) {
                error = e.javaClass.simpleName + ": " + (e.message ?: "NES input failsafe failed.")

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
            device.setMask(cleanMask)
        }
    }

    @Synchronized
    override fun stop() {

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
        }

    }

    override fun isRunning(): Boolean =
        running.get() && uinputProcess?.isAlive == true && socket?.isClosed == false

    override fun lastError(): String = error
    override fun packetsReceived(): Long = received.get()


    override fun destroy() {

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

# Shizuku creates this UserService through reflection, so R8 must preserve its class and constructor.
proguard = Path("android/app/proguard-rules.pro")
keep_rule = "-keep class com.tomastharwat.nintendo_nes.GamepadUserService { *; }"
existing_rules = proguard.read_text(encoding="utf-8") if proguard.is_file() else ""
if keep_rule not in existing_rules:
    proguard.parent.mkdir(parents=True, exist_ok=True)
    prefix = existing_rules.rstrip() + "\n\n" if existing_rules.strip() else ""
    proguard.write_text(
        prefix + "# Shizuku reflectively instantiates this binder service; keep its name and constructor.\n" +
        keep_rule + "\n",
        encoding="utf-8",
    )

# Ensure release builds load the generated keep rule without changing the minification policy.
release_match = re.search(r"(?m)^(?P<indent>[ \t]*)release[ \t]*\{", g)
if not release_match:
    raise SystemExit("Could not find Android release build type for Shizuku keep rules.")
release_open = g.find("{", release_match.start())
depth = 0
release_end = None
for pos in range(release_open, len(g)):
    if g[pos] == "{":
        depth += 1
    elif g[pos] == "}":
        depth -= 1
        if depth == 0:
            release_end = pos
            break
if release_end is None:
    raise SystemExit("Could not parse Android release build type block.")
release_block = g[release_open:release_end + 1]
if "proguard-rules.pro" not in release_block:
    rule_indent = release_match.group("indent") + "    "
    g = g[:release_end] + "\n" + rule_indent + 'proguardFiles("proguard-rules.pro")\n' + g[release_end:]

gradle.write_text(g, encoding="utf-8")
print("Configured Shizuku dependencies, AIDL generation, and BuildConfig.")
manifest = root / "AndroidManifest.xml"
xml = manifest.read_text(encoding="utf-8")
xml = re.sub(r'(?m)^\s*<uses-permission\b[^>]*android.permission.WRITE_EXTERNAL_STORAGE[^>]*/>\s*\n?', '', xml)
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
receiver_logger_file = kotlin / "ReceiverLogger.kt"
if receiver_logger_file.exists():
    receiver_logger_file.unlink()
write(receiver_kotlin / "MainActivity.kt", main)
write(kotlin / "GamepadUserService.kt", user_service)
write(kotlin / "UinputGamepad.kt", uinput)
write(aidl_dir / "IGamepadService.aidl", aidl)
print("Generated Shizuku/uinput system-gamepad bridge.")
