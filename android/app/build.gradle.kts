plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "co.bodit.bodit_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "co.bodit.bodit_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 환경(flavor) 분기.
    //
    // **운영 쪽은 아무것도 바꾸지 않는다** — applicationId 도 앱 이름도
    // 지금 배포된 그대로다. 바꾸면 스토어에 올라간 앱과 다른 앱이 된다.
    //
    // 개발 쪽만 갈라낸다. 배포하지 않고 debug 로만 쓰지만, 그래도 한 기기에
    // 운영과 같이 깔려야 한다 — 하나가 다른 하나를 덮어쓰면 확인할 때마다
    // 재설치를 해야 하고, 그러면 결국 아무도 확인하지 않는다.
    //
    // 주의: applicationId 가 달라지면 **Google 로그인이 막힌다** —
    // GCP 에 `co.bodit.bodit_app.dev` + SHA-1 로 Android 클라이언트를
    // 따로 등록해야 한다(serverClientId 는 웹 클라이언트라 그대로 쓴다).
    // AGP 9 부터 resValue 가 기본으로 꺼져 있다("the feature is disabled").
    // 앱 이름을 flavor 별로 넣으려면 켜야 한다.
    buildFeatures {
        resValues = true
    }

    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            // 런처에 뜨는 이름. AndroidManifest 가 @string/app_name 을 읽는다.
            resValue("string", "app_name", "Bodit_dev")
        }
        create("prod") {
            dimension = "env"
            // 지금까지 AndroidManifest 에 박혀 있던 값 그대로. 바꾸지 않는다.
            resValue("string", "app_name", "bodit_app")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
