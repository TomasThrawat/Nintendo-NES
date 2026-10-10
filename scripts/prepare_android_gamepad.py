#!/usr/bin/env python3
"""Generate the native Shizuku/uinput bridge in Flutter's generated Android project."""
from pathlib import Path
import re

root = Path("android/app/src/main")
kotlin = root / "kotlin/com/tomastharwat/nintendo_nes"
aidl_dir = root / "aidl/com/tomastharwat/nintendo_nes"

main = r'''package com.tomastharwat.nintendo_nes
import android.content.ComponentName
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
class MainActivity : FlutterActivity() {
 companion object {
  private const val CHANNEL = "com.tomastharwat.nintendo_nes/gamepad"
  private const val REQUEST = 9001
  private const val PORT = 27191
 }
 private var service: IGamepadService? = null
 private var pending: MethodChannel.Result? = null
 private var binding = false
 private var bindAttempts = 0
 private var activeConnection: ServiceConnection? = null
 private var startupStage = "checking Shizuku"
 private val mainHandler = Handler(Looper.getMainLooper())
 private val startupTimeout = Runnable {
  val callback = pending
  if (callback != null) {
   val stage = startupStage
   pending = null
   binding = false
   mainHandler.removeCallbacks(bindAttemptTimeout)
   callback.error("gamepad_start_timeout", "Timed out while $stage. Confirm Shizuku is running and this app is authorized, then try again.", null)
  }
 }
 private val bindAttemptTimeout = Runnable {
  if (pending != null && binding && service == null) {
   retryBind("No connection callback from Shizuku after ${bindAttempts} bind attempt(s).")
  }
 }
 private val args = Shizuku.UserServiceArgs(ComponentName(BuildConfig.APPLICATION_ID, GamepadUserService::class.java.name))
  .daemon(false).processNameSuffix("gamepad").debuggable(false).version(1)
 private val permissions = Shizuku.OnRequestPermissionResultListener { code, grant ->
  if (code == REQUEST) {
   if (grant == PackageManager.PERMISSION_GRANTED) scheduleBindGamepad()
   else {
    mainHandler.removeCallbacks(startupTimeout)
    pending?.error("shizuku_permission_denied", "Grant this app permission in Shizuku on the TV.", null)
    pending = null
   }
  }
 }
 private fun newConnection(): ServiceConnection = object : ServiceConnection {
  override fun onServiceConnected(name: ComponentName, binder: IBinder) {
   if (activeConnection !== this) return
   mainHandler.removeCallbacks(bindAttemptTimeout)
   binding = false
   service = IGamepadService.Stub.asInterface(binder)
   startBoundService()
  }
  override fun onServiceDisconnected(name: ComponentName) {
   if (activeConnection !== this) return
   mainHandler.removeCallbacks(bindAttemptTimeout)
   binding = false; activeConnection = null; service = null
   mainHandler.removeCallbacks(startupTimeout)
   pending?.error("gamepad_service_disconnected", "Shizuku service disconnected.", null); pending = null
  }
 }
 override fun onCreate(state: Bundle?) { super.onCreate(state); Shizuku.addRequestPermissionResultListener(permissions) }
 override fun configureFlutterEngine(engine: FlutterEngine) {
  super.configureFlutterEngine(engine)
  MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
   when (call.method) {
    "startGamepad" -> startGamepad(result)
    "setButtons" -> setButtons(call.argument<Int>("mask") ?: 0, result)
    "stopGamepad" -> stopGamepad(result)
    else -> result.notImplemented()
   }
  }
 }
 private fun startGamepad(result: MethodChannel.Result) {
  try {
   if (service?.isRunning() == true) { result.success(true); return }
   if (!Shizuku.pingBinder()) { result.error("shizuku_unavailable", "Start Shizuku on TV using Wireless debugging.", null); return }
   if (Shizuku.isPreV11()) { result.error("shizuku_outdated", "Update Shizuku on TV.", null); return }
   pending = result
   bindAttempts = 0
   startupStage = if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) "waiting to bind the Shizuku user service" else "waiting for Shizuku permission"
   mainHandler.removeCallbacks(startupTimeout)
   mainHandler.removeCallbacks(bindAttemptTimeout)
   mainHandler.postDelayed(startupTimeout, 30000)
   if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) scheduleBindGamepad()
   else Shizuku.requestPermission(REQUEST)
  } catch (e: Exception) {
   mainHandler.removeCallbacks(startupTimeout)
   pending = null
   result.error("gamepad_start_failed", e.message, null)
  }
 }
 private fun scheduleBindGamepad() {
  if (pending == null || service != null || binding) return
  startupStage = "waiting briefly before binding the Shizuku user service"
  mainHandler.postDelayed({
   if (pending != null && service == null && !binding) bindGamepad()
  }, 500)
 }
 private fun bindGamepad() {
  if (pending == null) return
  if (service != null) { startBoundService(); return }
  if (binding) return
  bindAttempts += 1
  try {
   if (!Shizuku.pingBinder()) throw IllegalStateException("Shizuku binder is not connected.")
   startupStage = "binding the Shizuku user service (attempt ${bindAttempts} of 3)"
   binding = true
   val attemptConnection = newConnection()
   activeConnection = attemptConnection
   mainHandler.removeCallbacks(bindAttemptTimeout)
   mainHandler.postDelayed(bindAttemptTimeout, 4000)
   Shizuku.bindUserService(args, attemptConnection)
  } catch (e: Exception) {
   retryBind(e.message ?: "Failed to bind the Shizuku user service.")
  }
 }
 private fun retryBind(reason: String) {
  mainHandler.removeCallbacks(bindAttemptTimeout)
  val previousConnection = activeConnection
  activeConnection = null
  binding = false
  if (previousConnection != null) {
   try { Shizuku.unbindUserService(args, previousConnection, false) } catch (_: Exception) { }
  }
  if (pending == null) return
  if (bindAttempts < 3) {
   startupStage = "retrying Shizuku user service binding after attempt ${bindAttempts}"
   mainHandler.postDelayed({
    if (pending != null && service == null && !binding) bindGamepad()
   }, 500)
  } else {
   mainHandler.removeCallbacks(startupTimeout)
   pending?.error("gamepad_bind_failed", "$reason Retried binding 3 times. Confirm Shizuku is running, then stop and start the receiver again.", null)
   pending = null
  }
 }
 private fun startBoundService() {
  val callback = pending ?: return
  try {
   startupStage = "registering the virtual gamepad through uinput"
   val pad = service ?: throw IllegalStateException("Shizuku service did not connect.")
   if (pad.start(PORT)) callback.success(true)
   else callback.error("uinput_registration_failed", pad.lastError().ifBlank { "TV could not register gamepad; check whether its firmware supports uinput." }, null)
  } catch (e: Exception) {
   callback.error("gamepad_start_failed", e.message, null)
  } finally {
   mainHandler.removeCallbacks(startupTimeout)
   mainHandler.removeCallbacks(bindAttemptTimeout)
   pending = null
  }
 }
 private fun setButtons(mask: Int, result: MethodChannel.Result) {
  try {
   val pad = service
   if (pad == null || !pad.isRunning()) { result.error("gamepad_not_running", "Start the TV receiver first.", null); return }
   pad.setButtons(mask and 0xff); result.success(null)
  } catch (e: Exception) { result.error("gamepad_input_failed", e.message, null) }
 }
 private fun stopGamepad(result: MethodChannel.Result) {
  try { service?.stop(); result.success(null) }
  catch (e: Exception) { result.error("gamepad_stop_failed", e.message, null) }
 }
 override fun onDestroy() {
  mainHandler.removeCallbacksAndMessages(null)
  try { service?.stop() } catch (_: Exception) { }
  val connectionToRelease = activeConnection
  activeConnection = null
  if (connectionToRelease != null) {
   try { Shizuku.unbindUserService(args, connectionToRelease, false) } catch (_: Exception) { }
  }
  Shizuku.removeRequestPermissionResultListener(permissions); super.onDestroy()
 }
}
'''
user_service = r'''package com.tomastharwat.nintendo_nes
import android.os.Process as AndroidProcess
class GamepadUserService : IGamepadService.Stub() {
 @Volatile private var process: Process? = null
 @Volatile private var pad: UinputGamepad? = null
 @Volatile private var active = false
 @Volatile private var error = ""
 override fun start(port: Int): Boolean {
  if (active && process?.isAlive == true) return true
  error = ""
  var child: Process? = null
  return try {
   child = ProcessBuilder("uinput", "-").redirectErrorStream(true).start()
   val runningProcess = child; process = runningProcess
   Thread({
    try { runningProcess.inputStream.bufferedReader().forEachLine { line ->
     if (line.contains("error", true)) error = line.take(500)
    } } catch (_: Exception) { }
    val exit = try { runningProcess.waitFor() } catch (_: Exception) { -1 }
    if (active && exit != 0) { error = "uinput exited with code " + exit; active = false }
   }, "gamepad-uinput-drain").apply { isDaemon = true; start() }
   val device = UinputGamepad(runningProcess.outputStream); pad = device; device.register()
   if (!runningProcess.isAlive) throw IllegalStateException("uinput exited during registration.")
   active = true; true
  } catch (e: Exception) {
   error = e.message ?: "Could not register virtual gamepad."
   active = false
   try { child?.outputStream?.close() } catch (_: Exception) { }
   try { child?.destroy() } catch (_: Exception) { }
   process = null; pad = null; false
  }
 }
 override fun setButtons(mask: Int) {
  val device = pad ?: throw IllegalStateException("Virtual gamepad is not registered.")
  if (!active) throw IllegalStateException("Virtual gamepad is not running.")
  try { device.setMask(mask and 0xff) }
  catch (e: Exception) { error = e.message ?: "Input injection failed."; stop(); throw e }
 }
 override fun stop() {
  active = false
  try { pad?.injectNeutral() } catch (_: Exception) { }
  pad = null
  process?.let { try { it.outputStream.close() } catch (_: Exception) { }; try { it.destroy() } catch (_: Exception) { } }
  process = null
 }
 override fun isRunning(): Boolean = active && process?.isAlive == true
 override fun lastError(): String = error
 override fun destroy() { stop(); AndroidProcess.killProcess(AndroidProcess.myPid()) }
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
 private var previous = -1
 fun register() {
  val config = JSONArray().apply {
   put(cfg(SET_EV, listOf(EV_KEY, EV_ABS)))
   put(cfg(SET_KEY, listOf(BTN_A, BTN_B, BTN_SELECT, BTN_START)))
   put(cfg(SET_ABS, listOf(HAT_X, HAT_Y)))
  }
  val axes = JSONArray().apply { put(axis(HAT_X)); put(axis(HAT_Y)) }
  write(JSONObject().apply {
   put("id", ID); put("command", "register"); put("name", "Xbox 360 Controller")
   put("vid", 0x045e); put("pid", 0x028e); put("bus", "usb")
   put("configuration", config); put("abs_info", axes)
  })
  write(JSONObject().apply { put("id", ID); put("command", "delay"); put("duration", 300) })
 }
 @Synchronized fun setMask(mask: Int) {
  val state = mask and 0xff
  if (state == previous) return
  val events = ArrayList<Int>(18)
  fun add(t: Int, c: Int, v: Int) { events.add(t); events.add(c); events.add(v) }
  for ((bit, key) in listOf(1 to BTN_A, 2 to BTN_B, 4 to BTN_SELECT, 8 to BTN_START)) {
   val old = previous >= 0 && (previous and bit) != 0
   val now = (state and bit) != 0
   if (previous < 0 || old != now) add(EV_KEY, key, if (now) 1 else 0)
  }
  val x = (if ((state and 64) != 0) -1 else 0) + (if ((state and 128) != 0) 1 else 0)
  val y = (if ((state and 16) != 0) -1 else 0) + (if ((state and 32) != 0) 1 else 0)
  add(EV_ABS, HAT_X, x.coerceIn(-1, 1)); add(EV_ABS, HAT_Y, y.coerceIn(-1, 1))
  previous = state; inject(events)
 }
 @Synchronized fun injectNeutral() { previous = -1; setMask(0) }
 private fun inject(events: List<Int>) {
  if (events.isEmpty()) return
  line.setLength(0); line.append("""{"id":1,"command":"inject","events":[""")
  for (i in events.indices step 3) {
   if (i > 0) line.append(',')
   line.append(events[i]).append(',').append(events[i + 1]).append(',').append(events[i + 2])
  }
  line.append(",0,0,0]}\n")
  output.write(line.toString().toByteArray(Charsets.UTF_8)); output.flush()
 }
 private fun write(obj: JSONObject) {
  line.setLength(0); line.append(obj.toString()).append('\n')
  output.write(line.toString().toByteArray(Charsets.UTF_8)); output.flush()
 }
 private fun cfg(type: Int, values: List<Int>) = JSONObject().apply { put("type", type); put("data", JSONArray(values)) }
 private fun axis(code: Int) = JSONObject().apply {
  put("code", code); put("info", JSONObject().apply {
   put("value", 0); put("minimum", -1); put("maximum", 1)
   put("fuzz", 0); put("flat", 0); put("resolution", 0)
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
write(kotlin / "MainActivity.kt", main)
write(kotlin / "GamepadUserService.kt", user_service)
write(kotlin / "UinputGamepad.kt", uinput)
write(aidl_dir / "IGamepadService.aidl", aidl)
print("Generated Shizuku/uinput system-gamepad bridge.")
