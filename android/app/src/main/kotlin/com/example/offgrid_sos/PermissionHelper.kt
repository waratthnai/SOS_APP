package com.example.offgrid_sos

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class PermissionHelper {
    companion object {
        private const val NEARBY_WIFI_PERMISSION_CODE = 1001
        
        fun hasNearbyWifiDevicesPermission(activity: Activity): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ContextCompat.checkSelfPermission(
                    activity,
                    Manifest.permission.NEARBY_WIFI_DEVICES
                ) == PackageManager.PERMISSION_GRANTED
            } else {
                true // Permission not needed for older versions
            }
        }
        
        fun requestNearbyWifiDevicesPermission(activity: Activity) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES),
                    NEARBY_WIFI_PERMISSION_CODE
                )
            }
        }
    }
}