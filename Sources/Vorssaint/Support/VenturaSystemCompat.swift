// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

// NSRunningApplication and activation options.
import AppKit
// Camera discovery types.
import AVFoundation
// CMSampleBuffer, the frame container a capture stream delivers.
import CoreMedia
// Calendar authorization status.
import EventKit
// Screen and window capture.
import ScreenCaptureKit
// Turns a captured pixel buffer into a CGImage.
import VideoToolbox

// MARK: - App activation

extension NSRunningApplication {
    /// `activate(from: .current, options:)` on macOS 14+, the cooperative activation
    /// that hands focus over from this app. macOS 13 has no cooperative activation,
    /// so there the app is activated directly, ignoring other apps, which is how
    /// activation worked before Sonoma. Returns whether activation was requested.
    @discardableResult
    func activateFromCurrentCompat(options: NSApplication.ActivationOptions) -> Bool {
        // Sonoma and later: hand activation over from this app.
        if #available(macOS 14.0, *) {
            return activate(from: NSRunningApplication.current, options: options)
        }
        // Ventura: take focus directly; without ignoringOtherApps a background
        // menu bar app cannot bring another app to the front.
        return activate(options: options.union(.activateIgnoringOtherApps))
    }
}

// MARK: - Calendar access

extension EKAuthorizationStatus {
    /// Whether events can be read: `.fullAccess` on macOS 14+, `.authorized` on 13
    /// (macOS 13 has a single access level, which includes reading).
    var hasFullAccessCompat: Bool {
        // Sonoma and later: only full access allows reading events.
        if #available(macOS 14.0, *) { return self == .fullAccess }
        // Ventura: authorized means full access.
        return self == .authorized
    }

    /// Whether only adding events is allowed (`.writeOnly`, macOS 14+). macOS 13
    /// has no write-only level, so it is never the case there.
    var isWriteOnlyCompat: Bool {
        // Sonoma and later: compare with the write-only level.
        if #available(macOS 14.0, *) { return self == .writeOnly }
        // Ventura: the level does not exist.
        return false
    }
}

extension EKEventStore {
    /// `requestFullAccessToEvents` on macOS 14+, `requestAccess(to: .event)` on 13.
    func requestFullEventAccessCompat(completion: @escaping (Bool, Error?) -> Void) {
        // Sonoma and later: ask for full (read and write) access.
        if #available(macOS 14.0, *) {
            requestFullAccessToEvents(completion: completion)
        } else {
            // Ventura: the single access level, which already includes reading.
            requestAccess(to: .event, completion: completion)
        }
    }
}

// MARK: - Camera discovery

enum CameraDeviceTypesCompat {
    /// Camera kinds to discover. macOS 14 renamed external cameras to `.external`
    /// and added `.continuityCamera`; macOS 13 calls them `.externalUnknown` and
    /// lists an iPhone used as a Continuity Camera among them.
    static var video: [AVCaptureDevice.DeviceType] {
        // Sonoma and later: built-in, external and Continuity cameras.
        if #available(macOS 14.0, *) {
            return [.builtInWideAngleCamera, .external, .continuityCamera]
        }
        // Ventura: built-in and external (which includes Continuity Camera there).
        return [.builtInWideAngleCamera, .externalUnknown]
    }
}

// MARK: - Single-frame screen capture

enum ScreenCaptureCompat {
    /// Error used when no usable frame arrives in time on macOS 13.
    struct NoFrame: Error {}

    /// `SCScreenshotManager.captureImage(contentFilter:configuration:)` on macOS 14+.
    /// macOS 13 has no screenshot API in ScreenCaptureKit, but it has streams, so
    /// there a stream is started with the same filter and configuration, the first
    /// complete frame is kept, and the stream is stopped. The filter's rules (for
    /// example leaving Vorssaint's own windows out) therefore still apply.
    static func captureImage(contentFilter: SCContentFilter,
                             configuration: SCStreamConfiguration) async throws -> CGImage {
        // Sonoma and later: the purpose-built screenshot call.
        if #available(macOS 14.0, *) {
            return try await SCScreenshotManager.captureImage(contentFilter: contentFilter,
                                                              configuration: configuration)
        }
        // Ventura: one frame from a short-lived stream.
        return try await SingleFrameGrabber().grab(filter: contentFilter, configuration: configuration)
    }
}

/// Starts a capture stream, returns its first complete frame and stops it.
/// Used only on macOS 13, where SCScreenshotManager does not exist.
private final class SingleFrameGrabber: NSObject, SCStreamOutput, @unchecked Sendable {
    /// Longest wait for a frame before giving up (a stream normally delivers within a few frames).
    private static let timeout: TimeInterval = 2
    /// Serial queue the stream delivers frames on.
    private let queue = DispatchQueue(label: "com.vorssaint.utils.single-frame-capture")
    /// Guards `continuation` and `stream`, which frames, errors and the timeout all touch.
    private let lock = NSLock()
    /// The suspended caller, resumed exactly once.
    private var continuation: CheckedContinuation<CGImage, Error>?
    /// The running stream, kept alive until it is stopped.
    private var stream: SCStream?

    /// Captures one frame for `filter` with `configuration`.
    func grab(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            // Store the caller so a frame, an error or the timeout can resume it.
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            // A stream with the caller's own filter and configuration.
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            // Keep it until finish() stops it.
            lock.lock()
            self.stream = stream
            lock.unlock()
            do {
                // Ask for screen frames on our queue.
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            } catch {
                // Could not attach: report it to the caller.
                finish(.failure(error))
                return
            }
            // Start the stream; a start error is reported to the caller.
            stream.startCapture { [weak self] error in
                // Only failures matter here; frames arrive through the output.
                if let error { self?.finish(.failure(error)) }
            }
            // Give up if no complete frame arrives in time (e.g. permission revoked).
            queue.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
                // finish() ignores this if a frame already resumed the caller.
                self?.finish(.failure(ScreenCaptureCompat.NoFrame()))
            }
        }
    }

    /// SCStreamOutput: called for every frame the stream produces.
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        // Only screen frames, and only intact ones.
        guard type == .screen, sampleBuffer.isValid else { return }
        // The frame's attachments say whether it carries new content.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              // Its status, stored as a raw integer.
              let rawStatus = attachments.first?[.status] as? Int,
              // Skip idle/blank/started frames: only a complete frame has an image.
              SCFrameStatus(rawValue: rawStatus) == .complete,
              // The pixels themselves.
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        // Convert the pixel buffer into a CGImage.
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        // A failed conversion waits for the next frame.
        guard let image else { return }
        // Hand the frame to the caller and stop.
        finish(.success(image))
    }

    /// Resumes the caller once and stops the stream; later calls do nothing.
    private func finish(_ result: Result<CGImage, Error>) {
        // Take the continuation and stream out under the lock so only one caller wins.
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let stream = self.stream
        self.stream = nil
        lock.unlock()
        // Already finished by a frame, an error or the timeout.
        guard let continuation else { return }
        // Stop capturing; the result does not depend on how stopping goes.
        stream?.stopCapture { _ in }
        // Wake the caller with the frame or the error.
        continuation.resume(with: result)
    }
}
