package com.agus.movetrack_ai

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Membuat video MP4 (H.264) dari frame RGBA yang digambar Flutter.
 * Semua proses di HP, tanpa internet. Kanal: "tempuh/video".
 *  start(width, height, fps, bitrate) -> path
 *  frame(bytes: RGBA width*height*4)
 *  finish() -> path
 *  cancel()
 */
object VideoEncoderChannel {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var encoder: Mp4Encoder? = null

    fun register(messenger: BinaryMessenger, cacheDir: File) {
        MethodChannel(messenger, "tempuh/video").setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    val value: Any? = when (call.method) {
                        "start" -> {
                            encoder?.release()
                            val dir = File(cacheDir, "replay").apply { mkdirs() }
                            dir.listFiles()?.forEach { it.delete() }
                            val file = File(dir, "tempuh_replay_${System.currentTimeMillis()}.mp4")
                            encoder = Mp4Encoder(
                                file,
                                call.argument<Int>("width")!!,
                                call.argument<Int>("height")!!,
                                call.argument<Int>("fps")!!,
                                call.argument<Int>("bitrate")!!,
                            )
                            file.absolutePath
                        }
                        "frame" -> {
                            val enc = encoder ?: throw IllegalStateException("Encoder belum dimulai")
                            enc.addFrame(call.argument<ByteArray>("bytes")!!)
                            null
                        }
                        "finish" -> {
                            val enc = encoder ?: throw IllegalStateException("Encoder belum dimulai")
                            encoder = null
                            enc.finish()
                            enc.file.absolutePath
                        }
                        "cancel" -> {
                            encoder?.release()
                            encoder?.file?.delete()
                            encoder = null
                            null
                        }
                        else -> {
                            main.post { result.notImplemented() }
                            return@execute
                        }
                    }
                    main.post { result.success(value) }
                } catch (e: Throwable) {
                    encoder?.release()
                    encoder = null
                    main.post { result.error("video", e.message ?: e.toString(), null) }
                }
            }
        }
    }
}

class Mp4Encoder(val file: File, private val width: Int, private val height: Int,
                 private val fps: Int, bitrate: Int) {
    private val codec: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    private val muxer = MediaMuxer(file.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    private val info = MediaCodec.BufferInfo()
    private var track = -1
    private var muxing = false
    private var frameIndex = 0L
    private var released = false

    init {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
    }

    private fun ptsUs(i: Long) = i * 1_000_000L / fps

    fun addFrame(rgba: ByteArray) {
        require(rgba.size >= width * height * 4) { "Ukuran frame salah" }
        var idx = codec.dequeueInputBuffer(10_000)
        while (idx < 0) {
            drain(false)
            idx = codec.dequeueInputBuffer(10_000)
        }
        val image = codec.getInputImage(idx) ?: throw IllegalStateException("Encoder tidak mendukung YUV420")
        val y = image.planes[0]
        val u = image.planes[1]
        val v = image.planes[2]
        val yBuf = y.buffer
        val uBuf = u.buffer
        val vBuf = v.buffer
        val yRow = y.rowStride
        val yPix = y.pixelStride
        val uRow = u.rowStride
        val uPix = u.pixelStride
        val vRow = v.rowStride
        val vPix = v.pixelStride
        var src = 0
        for (row in 0 until height) {
            val yBase = row * yRow
            val evenRow = (row and 1) == 0
            val cRow = row shr 1
            for (col in 0 until width) {
                val r = rgba[src].toInt() and 0xff
                val g = rgba[src + 1].toInt() and 0xff
                val b = rgba[src + 2].toInt() and 0xff
                src += 4
                yBuf.put(yBase + col * yPix, (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte())
                if (evenRow && (col and 1) == 0) {
                    val cCol = col shr 1
                    uBuf.put(cRow * uRow + cCol * uPix, (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).toByte())
                    vBuf.put(cRow * vRow + cCol * vPix, (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).toByte())
                }
            }
        }
        val size = width * height * 3 / 2
        codec.queueInputBuffer(idx, 0, size, ptsUs(frameIndex), 0)
        frameIndex++
        drain(false)
    }

    fun finish() {
        var idx = codec.dequeueInputBuffer(10_000)
        while (idx < 0) {
            drain(false)
            idx = codec.dequeueInputBuffer(10_000)
        }
        codec.queueInputBuffer(idx, 0, 0, ptsUs(frameIndex), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        drain(true)
        release()
    }

    private fun drain(endOfStream: Boolean) {
        var waits = 0
        while (true) {
            val out = codec.dequeueOutputBuffer(info, if (endOfStream) 10_000 else 0)
            when {
                out == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream) return
                    if (++waits > 500) throw IllegalStateException("Encoder tidak selesai")
                }
                out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    muxing = true
                }
                out >= 0 -> {
                    val buf = codec.getOutputBuffer(out)!!
                    if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) info.size = 0
                    if (info.size > 0 && muxing) {
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        muxer.writeSampleData(track, buf, info)
                    }
                    codec.releaseOutputBuffer(out, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return
                }
            }
        }
    }

    fun release() {
        if (released) return
        released = true
        try { codec.stop() } catch (_: Throwable) {}
        codec.release()
        try { if (muxing) muxer.stop() } catch (_: Throwable) {}
        muxer.release()
    }
}
