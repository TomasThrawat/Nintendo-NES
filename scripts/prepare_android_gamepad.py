#!/usr/bin/env python3
"""Generate the native Shizuku/uinput bridge in Flutter's generated Android project."""
from pathlib import Path
import re

root = Path("android/app/src/main")
kotlin = root / "kotlin/com/tomastharwat/nintendo_nes"
receiver_kotlin = Path("android/app/src/receiver/kotlin/com/tomastharwat/nintendo_nes")
controller_kotlin = Path("android/app/src/controller/kotlin/com/tomastharwat/nintendo_nes")
aidl_dir = root / "aidl/com/tomastharwat/nintendo_nes"

main = r'''package com.tomastharwat.nintendo_nes

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

class MainActivity : Activity() {
    companion object {
        private const val REQUEST = 9001
        private const val PORT = 27191
    }

    private var service: IGamepadService? = null
    private var bound = false
    private var binding = false
    private var startRequested = false
    private lateinit var statusView: TextView
    private val mainHandler = Handler(Looper.getMainLooper())

    private val bindTimeout = Runnable {
        if (binding && service == null) {
            binding = false
            startRequested = false
            statusView.text = "No response from Shizuku. Check Shizuku and permission, then press Start again."
            if (bound) {
                try { Shizuku.unbindUserService(userServiceArgs, connection, false) } catch (_: Exception) { }
                bound = false
            }
        }
    }

    private val statusTicker = object : Runnable {
        override fun run() {
            refreshStatus()
            mainHandler.postDelayed(this, 1000)
        }
    }

    private val userServiceArgs = Shizuku.UserServiceArgs(
        ComponentName(BuildConfig.APPLICATION_ID, GamepadUserService::class.java.name)
    ).daemon(false).processNameSuffix("gamepad").debuggable(false).version(2)

    private val permissionListener = Shizuku.OnRequestPermissionResultListener { code, grant ->
        if (code == REQUEST) {
            if (grant == PackageManager.PERMISSION_GRANTED) bindReceiver()
            else {
                startRequested = false
                statusView.text = "Shizuku permission was denied. Grant permission and press Start again."
            }
        }
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            mainHandler.removeCallbacks(bindTimeout)
            binding = false
            service = IGamepadService.Stub.asInterface(binder)
            if (startRequested) startReceiver() else refreshStatus()
        }

        override fun onServiceDisconnected(name: ComponentName) {
            mainHandler.removeCallbacks(bindTimeout)
            binding = false
            service = null
            statusView.text = "Shizuku service disconnected. Press Start to reconnect."
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
            textSize = 20f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(20), dp(20), dp(20))
        }
        val startButton = Button(this).apply {
            text = "Start"
            isAllCaps = false
            textSize = 20f
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(Color.rgb(45, 45, 45))
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(0, dp(64), 1f).apply {
                marginEnd = dp(8)
            }
            setOnClickListener { requestShizuku() }
        }
        val stopButton = Button(this).apply {
            text = "Stop"
            isAllCaps = false
            textSize = 20f
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(Color.rgb(75, 25, 25))
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(0, dp(64), 1f).apply {
                marginStart = dp(8)
            }
            setOnClickListener { stopReceiver() }
        }
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            addView(startButton)
            addView(stopButton)
        }
        root.addView(title, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(72)
        ))
        root.addView(statusView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
        ))
        root.addView(actions, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(72)
        ))
        setContentView(root)
        startButton.requestFocus()

        Shizuku.addRequestPermissionResultListener(permissionListener)
        refreshStatus()
        mainHandler.postDelayed(statusTicker, 1000)
    }

    private fun requestShizuku() {
        if (service?.isRunning() == true) {
            refreshStatus()
            return
        }
        if (!Shizuku.pingBinder()) {
            statusView.text = "Shizuku is not connected. Start Shizuku on the TV, then try again."
            return
        }
        if (Shizuku.isPreV11()) {
            statusView.text = "Shizuku is outdated. Update Shizuku on the TV."
            return
        }
        when {
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED -> bindReceiver()
            Shizuku.shouldShowRequestPermissionRationale() ->
                statusView.text = "Shizuku permission was denied before. Grant it in Shizuku, then press Start."
            else -> Shizuku.requestPermission(REQUEST)
        }
    }

    private fun bindReceiver() {
        if (service != null) {
            startReceiver()
            return
        }
        if (binding) return
        binding = true
        bound = true
        startRequested = true
        statusView.text = "Connecting to Shizuku..."
        mainHandler.removeCallbacks(bindTimeout)
        mainHandler.postDelayed(bindTimeout, 12000)
        try {
            Shizuku.bindUserService(userServiceArgs, connection)
        } catch (e: Exception) {
            mainHandler.removeCallbacks(bindTimeout)
            binding = false
            bound = false
            startRequested = false
            statusView.text = "Could not bind Shizuku service: " + (e.message ?: "unknown error")
        }
    }

    private fun startReceiver() {
        mainHandler.removeCallbacks(bindTimeout)
        binding = false
        startRequested = false
        val current = service
        if (current == null) {
            statusView.text = "Shizuku connected without a service binder. Press Start to retry."
            return
        }
        try {
            if (!current.isRunning() && !current.start(PORT)) {
                val detail = current.lastError()
                statusView.text = "Receiver startup failed: " +
                    if (detail.isNullOrBlank()) "TV could not register the virtual gamepad." else detail
            } else {
                refreshStatus()
            }
        } catch (e: Exception) {
            statusView.text = "Receiver startup failed: " + (e.message ?: e.javaClass.simpleName)
        }
    }

    private fun stopReceiver() {
        startRequested = false
        mainHandler.removeCallbacks(bindTimeout)
        try {
            service?.stop()
        } catch (e: Exception) {
            statusView.text = "Could not stop receiver: " + (e.message ?: "unknown error")
            return
        }
        refreshStatus()
    }

    private fun refreshStatus() {
        if (!::statusView.isInitialized) return
        val ip = localIp()
        val current = service
        statusView.text = try {
            when {
                binding && current == null ->
                    "IP: " + ip + "    Port: " + PORT + "\nConnecting to Shizuku..."
                current != null && current.isRunning() ->
                    "IP: " + ip + "    Port: " + PORT + "\nListening for NES controller\nPackets received: " + current.packetsReceived()
                current == null ->
                    "IP: " + ip + "    Port: " + PORT + "\nReady. Press Start."
                else -> {
                    val detail = current.lastError()
                    "IP: " + ip + "    Port: " + PORT + "\nNot running. " +
                        if (detail.isNullOrBlank()) "Press Start to start the receiver." else detail
                }
            }
        } catch (e: Exception) {
            service = null
            "Shizuku service disconnected. Press Start to reconnect.\n" + (e.message ?: "")
        }
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

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        Shizuku.removeRequestPermissionResultListener(permissionListener)
        try { service?.stop() } catch (_: Exception) { }
        if (bound) {
            try { Shizuku.unbindUserService(userServiceArgs, connection, true) } catch (_: Exception) { }
            bound = false
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
        if (running.get() && uinputProcess?.isAlive == true && socket?.isClosed == false) return true
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
                    runningProcess.inputStream.bufferedReader().forEachLine { line ->
                        if (line.contains("error", true)) error = line.take(300)
                    }
                } catch (_: Exception) { }
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
            error = e.message ?: "Could not start the NES receiver."
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
                    error = e.message ?: "NES UDP receiver failed."
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
            received.incrementAndGet()
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
                error = e.message ?: "NES input failsafe failed."
                stop()
                return
            }
        }
    }

    override fun setButtons(mask: Int) {
        synchronized(inputLock) {
            val device = pad ?: throw IllegalStateException("Virtual gamepad is not registered.")
            if (!running.get()) throw IllegalStateException("NES receiver is not running.")
            device.setMask(mask and 0xff)
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
        private const val SET_ABS = 103
        private const val EV_KEY = 1
        private const val EV_ABS = 3
        private const val BTN_A = 304
        private const val BTN_B = 305
        private const val BTN_SELECT = 314
        private const val BTN_START = 315
        private const val HAT_X = 16
        private const val HAT_Y = 17
    }

    private val line = StringBuilder(256)
    private var previousMask = -1

    fun register() {
        val configuration = JSONArray().apply {
            put(cfg(SET_EV, listOf(EV_KEY, EV_ABS)))
            put(cfg(SET_KEY, listOf(BTN_A, BTN_B, BTN_SELECT, BTN_START)))
            put(cfg(SET_ABS, listOf(HAT_X, HAT_Y)))
        }
        val axes = JSONArray().apply {
            put(axis(HAT_X))
            put(axis(HAT_Y))
        }
        write(JSONObject().apply {
            put("id", ID)
            put("command", "register")
            put("name", "Nintendo NES Controller")
            put("vid", 0x045e)
            put("pid", 0x028e)
            put("bus", "usb")
            put("configuration", configuration)
            put("abs_info", axes)
        })
        write(JSONObject().apply {
            put("id", ID)
            put("command", "delay")
            put("duration", 300)
        })
    }

    @Synchronized
    fun setMask(mask: Int) {
        val state = mask and 0xff
        if (state == previousMask) return
        val events = ArrayList<Int>(18)
        fun add(type: Int, code: Int, value: Int) {
            events.add(type)
            events.add(code)
            events.add(value)
        }
        for ((bit, key) in listOf(1 to BTN_A, 2 to BTN_B, 4 to BTN_SELECT, 8 to BTN_START)) {
            val old = previousMask >= 0 && (previousMask and bit) != 0
            val now = (state and bit) != 0
            if (previousMask < 0 || old != now) add(EV_KEY, key, if (now) 1 else 0)
        }
        val x = (if ((state and 64) != 0) 1 else 0) + (if ((state and 128) != 0) -1 else 0)
        val y = (if ((state and (1 shl 4)) != 0) -1 else 0) +
            (if ((state and (1 shl 5)) != 0) 1 else 0)
        add(EV_ABS, HAT_X, x.coerceIn(-1, 1))
        add(EV_ABS, HAT_Y, y.coerceIn(-1, 1))
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

    private fun axis(code: Int) = JSONObject().apply {
        put("code", code)
        put("info", JSONObject().apply {
            put("value", 0)
            put("minimum", -1)
            put("maximum", 1)
            put("fuzz", 0)
            put("flat", 0)
            put("resolution", 0)
        })
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

gradle.write_text(g, encoding="utf-8")
print("Configured Shizuku dependencies, AIDL generation, and BuildConfig.")
manifest = root / "AndroidManifest.xml"
xml = manifest.read_text(encoding="utf-8")
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
write(receiver_kotlin / "MainActivity.kt", main)
write(kotlin / "GamepadUserService.kt", user_service)
write(kotlin / "UinputGamepad.kt", uinput)
write(aidl_dir / "IGamepadService.aidl", aidl)
print("Generated Shizuku/uinput system-gamepad bridge.")
