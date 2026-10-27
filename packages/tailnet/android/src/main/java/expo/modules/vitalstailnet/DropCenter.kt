package expo.modules.vitalstailnet

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import dev.vitals.tailnet.DropListener
import dev.vitals.tailnet.Tailnet
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap

class DropFileProvider : FileProvider()

object DropCenter : DropListener {
  private const val CHANNEL = "vitals-drop"
  private const val NOTIFICATION = 7301
  private const val JOB = 7301
  private const val CANCELLED = "Cancelled"

  private class Active(val title: String, val total: Long, val target: Uri?) {
    @Volatile var done = 0L
  }

  private val jobs = ConcurrentHashMap<String, Active>()
  private val partial = ConcurrentHashMap<String, Uri>()
  private lateinit var app: Context
  private var jobService: JobService? = null
  private var jobParams: JobParameters? = null
  private var service: DropService? = null
  private var scheduled = false
  private var notified = 0L

  @Volatile var emit: ((Map<String, Any?>) -> Unit)? = null

  fun authority(context: Context) = "${context.packageName}.vitalsdrop"

  fun upload(context: Context, json: String) {
    app = context.applicationContext
    val config = JSONObject(json)
    val job = config.getString("job")
    check(!jobs.containsKey(job)) { "already running" }
    val fd = context.contentResolver.openFileDescriptor(Uri.parse(config.getString("uri")), "r")?.detachFd() ?: error("Can't open the file")
    start(job, Active(config.getString("title"), config.getLong("size"), null), fd) { Tailnet.dropUpload(job, json, fd.toLong(), this) }
  }

  fun download(context: Context, json: String) {
    app = context.applicationContext
    val config = JSONObject(json)
    val job = config.getString("job")
    check(!jobs.containsKey(job)) { "already running" }
    val resolver = context.contentResolver
    val resumed = partial.remove(job)?.let { uri -> runCatching { uri to resolver.openFileDescriptor(uri, "rw")!!.detachFd() }.getOrNull() }
    val (uri, fd) = resumed ?: create(context, config).let { uri -> uri to (resolver.openFileDescriptor(uri, "rw")?.detachFd() ?: error("Can't save the file")) }
    start(job, Active(config.getString("title"), config.getLong("size"), uri), fd) { Tailnet.dropDownload(job, json, fd.toLong(), this) }
  }

  // Go owns fd once the call runs and closes it on its own errors. A LinkageError (library
  // missing on this ABI) means it never ran, so the fd is still ours to close.
  private fun start(job: String, active: Active, fd: Int, run: () -> Unit) {
    jobs[job] = active
    keepAlive()
    try {
      run()
    } catch (error: Throwable) {
      if (error is LinkageError) runCatching { ParcelFileDescriptor.adoptFd(fd).close() }
      jobs.remove(job)
      active.target?.let { partial[job] = it }
      settle()
      throw error
    }
  }

  private fun create(context: Context, config: JSONObject): Uri {
    val name = config.getString("name").replace('/', '_')
    val path = (if (config.isNull("path")) "" else config.optString("path")).split('/').filter { it.isNotEmpty() && it != "." && it != ".." }.joinToString("/").ifEmpty { null }
    val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
      ?: config.optString("mime").takeIf { !config.isNull("mime") && it.isNotEmpty() }
    val folder = listOfNotNull("Vitals", path).joinToString("/")
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, name)
        put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$folder")
        put(MediaStore.Downloads.IS_PENDING, 1)
        if (mime != null) put(MediaStore.Downloads.MIME_TYPE, mime)
      }
      return context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: error("Can't save to Downloads")
    }
    val dir = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), folder).apply { mkdirs() }
    val stem = name.substringBeforeLast('.', name)
    val ext = name.substringAfterLast('.', "").let { if (it.isEmpty() || it == name) "" else ".$it" }
    val file = generateSequence(1) { it + 1 }.map { File(dir, if (it == 1) name else "$stem ($it)$ext") }.first { it.createNewFile() }
    return FileProvider.getUriForFile(context, authority(context), file)
  }

  override fun onProgress(job: String, done: Long, total: Long, route: String) {
    jobs[job]?.done = done
    emit?.invoke(mapOf("type" to "progress", "job" to job, "done" to done.toDouble(), "total" to total.toDouble(), "route" to route))
    refresh()
  }

  override fun onDone(job: String, sha256: String) {
    val active = jobs.remove(job)
    val uri = active?.target?.also { publish(it) }
    emit?.invoke(mapOf("type" to "done", "job" to job, "sha256" to sha256, "uri" to uri?.toString()))
    settle()
  }

  override fun onError(job: String, message: String, retryable: Boolean) {
    if (!retryable) jobs.remove(job)?.target?.let { if (message == CANCELLED) discard(it) else partial[job] = it }
    emit?.invoke(mapOf("type" to "error", "job" to job, "message" to message, "retryable" to retryable))
    if (!retryable) settle()
  }

  private fun publish(uri: Uri) {
    if (uri.authority == MediaStore.AUTHORITY && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      app.contentResolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
    }
  }

  private fun discard(uri: Uri) {
    runCatching { app.contentResolver.delete(uri, null, null) }
  }

  @Synchronized
  private fun keepAlive() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      if (scheduled) return
      val info = JobInfo.Builder(JOB, ComponentName(app, DropJobService::class.java))
        .setUserInitiated(true)
        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
        .build()
      scheduled = runCatching { app.getSystemService(JobScheduler::class.java).schedule(info) == JobScheduler.RESULT_SUCCESS }.getOrDefault(false)
    } else if (service == null && !scheduled) {
      scheduled = runCatching { ContextCompat.startForegroundService(app, Intent(app, DropService::class.java)) }.isSuccess
    }
  }

  @Synchronized
  private fun settle() {
    if (jobs.isNotEmpty()) return refresh()
    jobService?.let { s -> jobParams?.let { s.jobFinished(it, false) } }
    if (jobService == null && scheduled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      app.getSystemService(JobScheduler::class.java).cancel(JOB)
    }
    service?.finish()
    jobService = null
    jobParams = null
    service = null
    scheduled = false
  }

  @Synchronized
  fun attach(job: JobService, params: JobParameters): Boolean {
    if (jobs.isEmpty()) {
      scheduled = false
      return false
    }
    jobService = job
    jobParams = params
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      job.setNotification(params, NOTIFICATION, notification(job), JobService.JOB_END_NOTIFICATION_POLICY_REMOVE)
    }
    return true
  }

  @Synchronized
  fun detach(job: JobService): Boolean {
    if (jobService === job) {
      jobService = null
      jobParams = null
    }
    scheduled = jobs.isNotEmpty()
    return scheduled
  }

  @Synchronized
  fun attach(foreground: DropService): Boolean {
    if (jobs.isEmpty()) {
      scheduled = false
      return false
    }
    service = foreground
    return true
  }

  @Synchronized
  fun detach(foreground: DropService) {
    if (service === foreground) service = null
    scheduled = false
  }

  @Synchronized
  private fun refresh() {
    val now = SystemClock.elapsedRealtime()
    if (now - notified < 1000) return
    val job = jobService
    val params = jobParams
    if (job == null && service == null) return
    notified = now
    if (job != null && params != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      job.setNotification(params, NOTIFICATION, notification(job), JobService.JOB_END_NOTIFICATION_POLICY_REMOVE)
    } else {
      app.getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(app))
    }
  }

  fun notificationId() = NOTIFICATION

  fun notification(context: Context): Notification {
    val manager = context.getSystemService(NotificationManager::class.java)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(CHANNEL) == null) {
      manager.createNotificationChannel(NotificationChannel(CHANNEL, "File transfers", NotificationManager.IMPORTANCE_LOW))
    }
    val active = jobs.values.toList()
    val total = active.sumOf { it.total }
    val percent = if (total > 0) (active.sumOf { it.done } * 100 / total).toInt() else 0
    val title = when (active.size) {
      0 -> "Finishing transfers"
      1 -> "${active[0].title} · $percent%"
      else -> "${active.size} transfers · $percent%"
    }
    val icon = context.resources.getIdentifier("notification_icon", "drawable", context.packageName).takeIf { it != 0 } ?: android.R.drawable.stat_sys_download_done
    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
    return NotificationCompat.Builder(context, CHANNEL)
      .setSmallIcon(icon)
      .setContentTitle(title)
      .setProgress(100, percent, total == 0L)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setSilent(true)
      .setCategory(NotificationCompat.CATEGORY_PROGRESS)
      .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
      .apply { if (launch != null) setContentIntent(PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)) }
      .build()
  }

  fun canInstallApps(context: Context): Boolean = runCatching {
    @Suppress("DEPRECATION")
    val info = context.packageManager.getPackageInfo(context.packageName, android.content.pm.PackageManager.GET_PERMISSIONS)
    info.requestedPermissions?.contains(android.Manifest.permission.REQUEST_INSTALL_PACKAGES) == true
  }.getOrDefault(false)

  fun viewable(context: Context, uri: String): Uri {
    val parsed = Uri.parse(uri)
    if (parsed.scheme != "file") return parsed
    return FileProvider.getUriForFile(context, authority(context), File(parsed.path ?: error("Bad file uri")))
  }
}
