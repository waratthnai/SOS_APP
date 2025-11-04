import org.gradle.api.tasks.Copy

// ====== ตั้งค่า path ปลายทางให้ตรงกับที่ Flutter มองหา ======
val flutterApkDir = File(rootDir.parentFile, "build/app/outputs/flutter-apk")

// ====== งานคัดลอกไฟล์ Debug ======
tasks.register<Copy>("copyApkDebug") {
    val srcApk = File(rootDir, "app/build/outputs/apk/debug/app-debug.apk")
    from(srcApk)
    into(flutterApkDir)
    doFirst { flutterApkDir.mkdirs() }
}

// ====== งานคัดลอกไฟล์ Release ======
tasks.register<Copy>("copyApkRelease") {
    // ถ้าคุณมี productFlavors จะกลายเป็นชื่อไฟล์เช่น app-release.apk หรือ app-prod-release.apk
    // ปรับ pattern ให้ครอบคลุมทุกกรณีด้วย glob
    from(File(rootDir, "app/build/outputs/apk/release")) {
        include("*.apk")
    }
    into(flutterApkDir)
    doFirst { flutterApkDir.mkdirs() }
}

// ====== ผูกงานคัดลอกให้รันต่อจาก assemble ของโมดูล :app ======
project(":app") {
    // หลัง build debug เสร็จ ให้คัดลอกไปยัง flutter-apk
    tasks.matching { it.name == "assembleDebug" }.configureEach {
        finalizedBy(":copyApkDebug")
    }
    // หลัง build release เสร็จ ให้คัดลอกไปยัง flutter-apk
    tasks.matching { it.name == "assembleRelease" }.configureEach {
        finalizedBy(":copyApkRelease")
    }
}
