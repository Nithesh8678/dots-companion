import Foundation
import CoreGraphics

/// ScreenCaptureKit/model pixels have a top-left origin; AppKit global points have a bottom-left origin.
public struct CoordinateTransform: Equatable, Codable, Sendable {
    public let captureFrame: CGRect
    public let pixelSize: CGSize
    public init(captureFrame: CGRect, pixelSize: CGSize) {
        self.captureFrame = captureFrame; self.pixelSize = pixelSize
    }
    public var isValid: Bool {
        [captureFrame.minX, captureFrame.minY, captureFrame.width, captureFrame.height,
         pixelSize.width, pixelSize.height].allSatisfy(\.isFinite)
        && captureFrame.width > 0 && captureFrame.height > 0 && pixelSize.width > 0 && pixelSize.height > 0
    }
    public func appKitPoint(fromImage point: CGPoint) -> CGPoint? {
        guard isValid, point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.x <= pixelSize.width, point.y >= 0, point.y <= pixelSize.height else { return nil }
        return CGPoint(x: captureFrame.minX + point.x / pixelSize.width * captureFrame.width,
                       y: captureFrame.maxY - point.y / pixelSize.height * captureFrame.height)
    }
    public func imagePoint(fromAppKit point: CGPoint) -> CGPoint? {
        guard isValid, point.x.isFinite, point.y.isFinite,
              point.x >= captureFrame.minX, point.x <= captureFrame.maxX,
              point.y >= captureFrame.minY, point.y <= captureFrame.maxY else { return nil }
        return CGPoint(x: (point.x - captureFrame.minX) / captureFrame.width * pixelSize.width,
                       y: (captureFrame.maxY - point.y) / captureFrame.height * pixelSize.height)
    }
    public func appKitRect(fromImage rect: CGRect) -> CGRect? {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
              let topLeft = appKitPoint(fromImage: rect.origin),
              let bottomRight = appKitPoint(fromImage: CGPoint(x: rect.maxX, y: rect.maxY)) else { return nil }
        return CGRect(x: topLeft.x, y: bottomRight.y, width: bottomRight.x - topLeft.x,
                      height: topLeft.y - bottomRight.y)
    }
    public func appKitPoint(fromNormalized point: CGPoint) -> CGPoint? {
        appKitPoint(fromImage: CGPoint(x: point.x * pixelSize.width, y: point.y * pixelSize.height))
    }
}

public struct ContextSnapshot: Codable, Equatable, Sendable {
    public let id: ContextID
    public let processID: Int32
    public let windowID: String
    public let displayID: UInt32
    public let capturedAt: Date
    public let revision: UInt64
    public let transform: CoordinateTransform
    public init(id: ContextID = ContextID(), processID: Int32, windowID: String, displayID: UInt32,
                capturedAt: Date = Date(), revision: UInt64, transform: CoordinateTransform) {
        self.id = id; self.processID = processID; self.windowID = windowID; self.displayID = displayID
        self.capturedAt = capturedAt; self.revision = revision; self.transform = transform
    }
    /// A navigation, scroll, window move or resize must advance the owner's revision.
    public func isFresh(now: Date, maxAge: TimeInterval, currentRevision: UInt64,
                        processID: Int32, windowID: String) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        return maxAge >= 0 && age >= 0 && age <= maxAge && revision == currentRevision
            && self.processID == processID && self.windowID == windowID && transform.isValid
    }
}

public enum AnnotationKind: String, Codable, Sendable, CaseIterable {
    case highlight, circle, arrow, underline, dimOutsideRegion, numberedStep, label
}
public struct AnnotationCommand: Codable, Sendable {
    public let contextID: ContextID
    public let displayID: UInt32
    public let kind: AnnotationKind
    public let imageRect: CGRect
    public let label: String?
    public let duration: TimeInterval
    public init(contextID: ContextID, displayID: UInt32, kind: AnnotationKind, imageRect: CGRect,
                label: String? = nil, duration: TimeInterval = 4) {
        self.contextID = contextID; self.displayID = displayID; self.kind = kind
        self.imageRect = imageRect; self.label = label.map { String($0.prefix(160)) }
        self.duration = duration.isFinite ? min(max(duration, 0.1), 30) : 4
    }
    public func resolvedRect(in snapshot: ContextSnapshot) -> CGRect? {
        guard contextID == snapshot.id, displayID == snapshot.displayID else { return nil }
        return snapshot.transform.appKitRect(fromImage: imageRect)
    }
}
