package com.hy.minipedometer

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Process-wide store for raw step-counter readings and measured walking time.
 *
 * Native code only *captures*; all step accounting (reboots, resets, day
 * attribution) happens in Dart (`step_ledger.dart`) so it can be unit-tested.
 *
 * Readings stay queued until Dart has saved them and acknowledges them.
 * While unacknowledged, consecutive readings from the same boot, session and
 * local day are compacted (only the latest is kept) — lossless for the
 * ledger, which only uses differences between readings. Two readings are
 * never compacted away: the first of a session (it marks when observation
 * resumed) and the first of each local day (it shows how many steps came
 * after midnight — without it, a whole morning would look like one jump
 * from the previous evening). That is at most ~2 queued readings per day.
 *
 * This state is excluded from Android backups (see res/xml): a restored
 * copy would describe another installation's sensor. [installId] lets Dart
 * detect that its own (backed-up) state was restored.
 */
object SampleStore {
    private const val PREFS = "minipedometer_native"
    private const val MAX_QUEUE = 4000
    // Short enough that a killed process loses almost no readings (a lost
    // reading would widen an unobserved gap); readings arrive in batches
    // every few minutes in the background, so writes stay rare.
    private const val PERSIST_DELAY_MS = 2_000L
    private const val NOTIFY_DELAY_MS = 500L

    // Walking time: an interval between two readings counts as walking when
    // the readings are close together and the cadence is walking-like.
    private const val WALK_MAX_GAP_MS = 15_000L
    private const val WALK_MIN_STEPS_PER_SEC = 0.6
    private const val WALK_KEEP_DAYS = 62

    data class Sample(
        val seq: Long,
        val boot: Int,
        val elapsed: Long,
        val wall: Long,
        val steps: Long,
        val shutdown: Boolean,
        val session: Long = -1L,
        val wakeUp: Boolean = false,
        /** Never compacted away: first reading of a session or of a day. */
        val keep: Boolean = false,
    )

    private var prefs: SharedPreferences? = null
    private val queue = ArrayList<Sample>()
    private val walkMs = HashMap<String, Long>()
    private var seq = 0L
    private var last: Sample? = null
    private var installId: String? = null
    private var session = -1L
    private var sessionWakeUp = false
    private var sessionStartPending = false

    private val main = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArraySet<() -> Unit>()
    private var persistScheduled = false
    private var notifyScheduled = false

    @Synchronized
    fun init(context: Context) {
        if (prefs != null) return
        val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs = p
        installId = p.getString("installId", null) ?: java.util.UUID.randomUUID().toString().also {
            p.edit().putString("installId", it).commit()
        }
        try {
            seq = p.getLong("seq", 0L)
            session = p.getLong("session", -1L)
            p.getString("queue", null)?.let { raw ->
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) queue.add(fromJson(arr.getJSONObject(i)))
            }
            p.getString("last", null)?.let { last = fromJson(JSONObject(it)) }
            p.getString("walk", null)?.let { raw ->
                val obj = JSONObject(raw)
                obj.keys().forEach { k -> walkMs[k] = obj.getLong(k) }
            }
        } catch (e: Exception) {
            // Corrupt native state: start over. The Dart ledger detects the
            // discontinuity and marks affected days incomplete.
            queue.clear(); walkMs.clear(); last = null
        }
    }

    /** Identifies this installation; not part of any backup. */
    @Synchronized
    fun installId(): String? = installId

    /**
     * Called when the service starts listening to the sensor: readings from
     * here on belong to a new session (observation may have been
     * interrupted before it).
     */
    @Synchronized
    fun beginSession(wakeUp: Boolean) {
        session += 1
        sessionWakeUp = wakeUp
        sessionStartPending = true
        prefs?.edit()?.putLong("session", session)?.commit()
    }

    /** Records a reading of the cumulative counter. */
    @Synchronized
    fun record(boot: Int, elapsed: Long, wall: Long, steps: Long, shutdown: Boolean = false) {
        val prev = last
        if (prev != null && prev.boot == boot && prev.session == session && !shutdown) {
            val dt = elapsed - prev.elapsed
            val ds = steps - prev.steps
            if (dt in 1..WALK_MAX_GAP_MS && ds > 0 && ds * 1000.0 / dt >= WALK_MIN_STEPS_PER_SEC) {
                val key = dayKey(wall)
                walkMs[key] = (walkMs[key] ?: 0L) + dt
            }
            if (dt < 0) return // older than what we have: ignore
        }
        val start = sessionStartPending
        sessionStartPending = false
        val firstOfDay = prev == null || dayKey(prev.wall) != dayKey(wall)
        val sample = Sample(
            ++seq, boot, elapsed, wall, steps, shutdown, session, sessionWakeUp,
            keep = start || firstOfDay,
        )
        last = sample

        val tail = queue.lastOrNull()
        if (tail != null && tail.boot == boot && tail.session == session &&
            !tail.shutdown && !tail.keep && dayKey(tail.wall) == dayKey(wall)
        ) {
            queue.removeAt(queue.size - 1)
        }
        queue.add(sample)
        while (queue.size > MAX_QUEUE) queue.removeAt(0)

        if (sample.keep) persistNow(sync = false) else schedulePersist()
        scheduleNotify()
    }

    /** Captures the last known value at a clean shutdown. */
    @Synchronized
    fun markShutdown(boot: Int, elapsed: Long, wall: Long) {
        val prev = last ?: return
        if (prev.boot != boot) return
        record(boot, elapsed, wall, prev.steps, shutdown = true)
        persistNow(sync = true)
    }

    @Synchronized
    fun read(): List<Map<String, Any>> = queue.map {
        mapOf(
            "seq" to it.seq, "boot" to it.boot, "elapsed" to it.elapsed,
            "wall" to it.wall, "steps" to it.steps, "shutdown" to it.shutdown,
            "session" to it.session, "wakeUp" to it.wakeUp,
        )
    }

    @Synchronized
    fun ack(upTo: Long) {
        if (queue.removeAll { it.seq <= upTo }) persistNow(sync = false)
    }

    /**
     * Measured walking time for a local day (ms), or null when nothing is
     * known about that day.
     */
    @Synchronized
    fun walkingTime(day: String, trackingActive: Boolean): Long? {
        walkMs[day]?.let { return it }
        val l = last
        return if (trackingActive || (l != null && dayKey(l.wall) == day)) 0L else null
    }

    fun addListener(l: () -> Unit) { listeners.add(l) }
    fun removeListener(l: () -> Unit) { listeners.remove(l) }

    @Synchronized
    fun persistNow(sync: Boolean) {
        val p = prefs ?: return
        persistScheduled = false
        val cutoff = dayKey(System.currentTimeMillis() - WALK_KEEP_DAYS * 86_400_000L)
        walkMs.keys.removeAll { it < cutoff }
        val editor = p.edit()
            .putLong("seq", seq)
            .putLong("session", session)
            .putString("queue", JSONArray(queue.map { toJson(it) }).toString())
            .putString("last", last?.let { toJson(it).toString() })
            .putString("walk", JSONObject(walkMs as Map<*, *>).toString())
        if (sync) editor.commit() else editor.apply()
    }

    private fun schedulePersist() {
        if (persistScheduled) return
        persistScheduled = true
        main.postDelayed({ persistNow(sync = false) }, PERSIST_DELAY_MS)
    }

    private fun scheduleNotify() {
        if (notifyScheduled || listeners.isEmpty()) return
        notifyScheduled = true
        main.postDelayed({
            synchronized(this) { notifyScheduled = false }
            listeners.forEach { it() }
        }, NOTIFY_DELAY_MS)
    }

    fun dayKey(epochMs: Long): String {
        val c = Calendar.getInstance()
        c.timeInMillis = epochMs
        return String.format(
            Locale.US, "%04d-%02d-%02d",
            c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH),
        )
    }

    private fun toJson(s: Sample) = JSONObject()
        .put("seq", s.seq).put("boot", s.boot).put("elapsed", s.elapsed)
        .put("wall", s.wall).put("steps", s.steps).put("shutdown", s.shutdown)
        .put("session", s.session).put("wakeUp", s.wakeUp).put("keep", s.keep)

    private fun fromJson(o: JSONObject) = Sample(
        o.getLong("seq"), o.getInt("boot"), o.getLong("elapsed"),
        o.getLong("wall"), o.getLong("steps"), o.optBoolean("shutdown", false),
        o.optLong("session", -1L), o.optBoolean("wakeUp", false), o.optBoolean("keep", false),
    )
}
