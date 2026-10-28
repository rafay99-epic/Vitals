package expo.modules.vitalsshare

import android.os.Build
import android.system.Os
import android.system.OsConstants
import android.util.Base64
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.Executors

/** Folder listings and file reads for other devices browsing this phone, off the JS thread. */
object Files {
  /** Shared storage is a FUSE mount where every stat is a round trip, so a big folder is stat-ed on a few threads at once. */
  private val pool = Executors.newFixedThreadPool(STAT_THREADS)

  /** Every visible entry of `path` in one call, as parallel arrays. Throws with "permission" in the message when Android keeps Vitals out. */
  fun list(path: String): Map<String, Any> {
    val dir = File(path)
    if (!dir.isDirectory) throw IllegalArgumentException("There's no folder at $path")
    val names = ((if (dir.canRead()) dir.list() else null) ?: throw SecurityException("Missing 'READ' permission for $path")).filter { !it.startsWith(".") }
    val dirs = BooleanArray(names.size)
    val sizes = DoubleArray(names.size)
    val times = DoubleArray(names.size)
    val stat = { index: Int ->
      runCatching { Os.stat("$path/${names[index]}") }.getOrNull()?.let { info ->
        dirs[index] = OsConstants.S_ISDIR(info.st_mode)
        sizes[index] = if (dirs[index]) 0.0 else info.st_size.toDouble()
        times[index] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) info.st_mtim.tv_sec * 1000.0 + info.st_mtim.tv_nsec / 1_000_000 else info.st_mtime * 1000.0
      }
    }
    val slices = (0 until STAT_THREADS).map { slice -> pool.submit { for (index in slice until names.size step STAT_THREADS) stat(index) } }
    slices.forEach { it.get() }
    return mapOf("names" to names, "dirs" to dirs.toList(), "sizes" to sizes, "times" to times)
  }

  private const val STAT_THREADS = 4

  /** Up to `length` bytes of `path` from `offset`, as base64, with how many were read and the file's size. */
  fun readChunk(path: String, offset: Double, length: Int): Map<String, Any> =
    RandomAccessFile(path, "r").use { file ->
      val total = file.length()
      val start = offset.toLong().coerceIn(0, total)
      val buffer = ByteArray(minOf(length.toLong(), total - start).toInt())
      file.seek(start)
      var read = 0
      while (read < buffer.size) {
        val count = file.read(buffer, read, buffer.size - read)
        if (count < 0) break
        read += count
      }
      mapOf("data" to Base64.encodeToString(buffer, 0, read, Base64.NO_WRAP), "read" to read, "total" to total.toDouble())
    }
}
