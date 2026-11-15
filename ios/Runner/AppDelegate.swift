import CoreMotion
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pedometerBridge: PedometerBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PedometerBridge") {
      pedometerBridge = PedometerBridge(messenger: registrar.messenger())
    }
  }
}

/// Core Motion bridge for the Dart `IosStepTracker`.
///
/// * Steps: `CMPedometer` — counted continuously by the motion coprocessor,
///   even while the app is closed; queryable for roughly the last 7 days.
/// * Walking time: `CMMotionActivityManager` — the sum of periods the system
///   classified as walking or running (medium/high confidence). This is a
///   measurement by iOS, not an estimate derived from the step count.
///
/// Channel names must match lib/src/tracking/step_tracker.dart.
final class PedometerBridge: NSObject, FlutterStreamHandler {
  private let pedometer = CMPedometer()
  private let activityManager = CMMotionActivityManager()

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    FlutterMethodChannel(name: "com.hy.minipedometer/steps", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        self?.handle(call, result: result)
      }
    FlutterEventChannel(name: "com.hy.minipedometer/steps/live", binaryMessenger: messenger)
      .setStreamHandler(self)
  }

  private func status() -> String {
    guard CMPedometer.isStepCountingAvailable() else { return "unsupported" }
    switch CMPedometer.authorizationStatus() {
    case .authorized: return "authorized"
    case .notDetermined: return "notDetermined"
    // iOS never shows the prompt twice: only Settings can change it.
    case .denied, .restricted: return "permanentlyDenied"
    @unknown default: return "unavailable"
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "status":
      result(status())

    case "requestAccess":
      guard status() == "notDetermined" else {
        result(status())
        return
      }
      // The Motion & Fitness prompt appears on the first Core Motion query.
      let now = Date()
      pedometer.queryPedometerData(from: now.addingTimeInterval(-60), to: now) { [weak self] _, _ in
        DispatchQueue.main.async { result(self?.status() ?? "unavailable") }
      }

    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)

    case "querySteps":
      guard let ranges = args?["ranges"] as? [[NSNumber]] else {
        result(FlutterError(code: "bad_args", message: "ranges required", details: nil))
        return
      }
      querySteps(ranges, result: result)

    case "walkingTime":
      guard let start = (args?["start"] as? NSNumber)?.doubleValue,
            let end = (args?["end"] as? NSNumber)?.doubleValue
      else {
        result(FlutterError(code: "bad_args", message: "start/end required", details: nil))
        return
      }
      walkingTime(from: Date(timeIntervalSince1970: start / 1000),
                  to: Date(timeIntervalSince1970: end / 1000),
                  result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// One pedometer query per [start, end) range. Unknown entries are null.
  private func querySteps(_ ranges: [[NSNumber]], result: @escaping FlutterResult) {
    var values = [Any](repeating: NSNull(), count: ranges.count)
    var notAuthorized = false
    let group = DispatchGroup()
    let lock = NSLock()
    for (i, r) in ranges.enumerated() where r.count == 2 {
      let from = Date(timeIntervalSince1970: r[0].doubleValue / 1000)
      let to = Date(timeIntervalSince1970: r[1].doubleValue / 1000)
      guard to > from else { continue }
      group.enter()
      pedometer.queryPedometerData(from: from, to: to) { data, error in
        lock.lock()
        if let data = data {
          values[i] = data.numberOfSteps.intValue
        } else if let error = error as NSError?,
                  error.domain == CMErrorDomain,
                  error.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
          notAuthorized = true
        }
        lock.unlock()
        group.leave()
      }
    }
    group.notify(queue: .main) {
      if notAuthorized {
        result(FlutterError(code: "denied", message: "Motion & Fitness access denied", details: nil))
      } else {
        result(values)
      }
    }
  }

  private func walkingTime(from start: Date, to end: Date, result: @escaping FlutterResult) {
    guard CMMotionActivityManager.isActivityAvailable(), end > start else {
      result(nil)
      return
    }
    activityManager.queryActivityStarting(from: start, to: end, to: .main) { activities, error in
      guard let activities = activities, error == nil else {
        result(nil)
        return
      }
      var total: TimeInterval = 0
      for (i, activity) in activities.enumerated() {
        guard activity.walking || activity.running, activity.confidence != .low else { continue }
        let next = i + 1 < activities.count ? activities[i + 1].startDate : end
        let s = max(activity.startDate, start)
        let e = min(next, end)
        if e > s { total += e.timeIntervalSince(s) }
      }
      result(total)
    }
  }

  // MARK: Live updates (foreground only)

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard CMPedometer.isStepCountingAvailable() else { return nil }
    let fromMs = ((arguments as? [String: Any])?["from"] as? NSNumber)?.doubleValue
    let from = fromMs.map { Date(timeIntervalSince1970: $0 / 1000) }
      ?? Calendar.current.startOfDay(for: Date())
    pedometer.startUpdates(from: from) { data, _ in
      guard data != nil else { return }
      DispatchQueue.main.async { events(nil) }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    pedometer.stopUpdates()
    return nil
  }
}
