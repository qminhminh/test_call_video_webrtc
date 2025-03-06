import Flutter
import UIKit
import Firebase
import UserNotifications
import WebRTC

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var verboseLogger: RTCFileLogger?
    private var infoLogger: RTCFileLogger?
    private var warningLogger: RTCFileLogger?
    private var errorLogger: RTCFileLogger?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Khởi tạo Firebase
       // FirebaseApp.configure()
        
        // Đặt mức log tối thiểu (chỉ cần một lần)
        RTCSetMinDebugLogLevel(.error)

        // Khởi tạo WebRTC Logging
        setupLogging()

        // Đăng ký thông báo đẩy
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        
        // Đăng ký plugin Flutter
        GeneratedPluginRegistrant.register(with: self)
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func setupLogging() {
        let logDir = FileManager.default.temporaryDirectory

        // Tạo 4 file log cho từng mức độ
        verboseLogger = RTCFileLogger(dirPath: logDir.appendingPathComponent("verbose_logs_call_video").path, maxFileSize: 1024 * 1024)
        infoLogger = RTCFileLogger(dirPath: logDir.appendingPathComponent("info_logs_call_video").path, maxFileSize: 1024 * 1024)
        warningLogger = RTCFileLogger(dirPath: logDir.appendingPathComponent("warning_logs_call_video").path, maxFileSize: 1024 * 1024)
        errorLogger = RTCFileLogger(dirPath: logDir.appendingPathComponent("error_logs_call_video").path, maxFileSize: 1024 * 1024)

        // Chạy tất cả logger
        verboseLogger?.start()
        infoLogger?.start()
        warningLogger?.start()
        errorLogger?.start()

        print("✅ WebRTC logging started in \(logDir.path)")
    }

    func stopLogging() {
        verboseLogger?.stop()
        infoLogger?.stop()
        warningLogger?.stop()
        errorLogger?.stop()

        print("🛑 WebRTC logging stopped.")
    }

    // Xử lý token thông báo đẩy
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs Device Token: \(token)")
    }

    // Xử lý lỗi khi đăng ký thông báo đẩy
    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications with error: \(error.localizedDescription)")
    }
}