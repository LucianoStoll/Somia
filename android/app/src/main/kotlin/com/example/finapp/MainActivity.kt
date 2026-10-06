package com.example.finapp

import android.accounts.Account
import android.accounts.AccountManager
import android.app.Activity
import android.content.Intent
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.AccountPicker
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Scope
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val preferences by lazy { getSharedPreferences("somia_drive", MODE_PRIVATE) }
    private val authorization by lazy { Identity.getAuthorizationClient(this) }
    private var pending: MethodChannel.Result? = null
    private var selected: String? = null
    private var interactive = false
    private val scope = "https://www.googleapis.com/auth/drive.appdata"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "somia/drive_auth")
            .setMethodCallHandler { call, result ->
                if (pending != null) {
                    result.error("busy", "Há uma autorização em andamento.", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "account" -> result.success(preferences.getString("email", null))
                    "disconnect" -> {
                        preferences.edit().remove("email").apply()
                        result.success(null)
                    }
                    "clearToken" -> {
                        val token = call.argument<String>("token")
                        if (token == null) result.success(null)
                        else authorization.clearToken(ClearTokenRequest.builder().setToken(token).build())
                            .addOnCompleteListener { result.success(null) }
                    }
                    "connect" -> {
                        pending = result
                        interactive = true
                        try {
                            val options = AccountPicker.AccountChooserOptions.Builder()
                                .setAllowableAccountsTypes(listOf("com.google"))
                                .setAlwaysShowAccountPicker(true).build()
                            startActivityForResult(AccountPicker.newChooseAccountIntent(options), 7101)
                        } catch (error: Exception) { fail(error) }
                    }
                    "authorize" -> {
                        pending = result
                        interactive = false
                        selected = preferences.getString("email", null)
                        if (selected == null) finishError("auth", "Conecte uma conta Google.")
                        else authorize()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun authorize() {
        val email = selected ?: return finishError("auth", "Selecione uma conta Google.")
        val request = AuthorizationRequest.builder().setAccount(Account(email, "com.google"))
            .setRequestedScopes(listOf(Scope(scope))).build()
        authorization.authorize(request).addOnSuccessListener { response ->
            if (response.hasResolution()) {
                if (!interactive) finishError("auth", "Reconecte sua conta para autorizar o Drive.")
                else try {
                    startIntentSenderForResult(response.pendingIntent!!.intentSender, 7102, null, 0, 0, 0)
                } catch (error: Exception) { fail(error) }
            } else complete(response.accessToken)
        }.addOnFailureListener { fail(it) }
    }

    private fun complete(token: String?) {
        if (token.isNullOrEmpty() || selected == null) {
            finishError("auth", "O Google não concedeu acesso ao Drive.")
            return
        }
        preferences.edit().putString("email", selected).apply()
        val result = pending
        pending = null
        result?.success(mapOf("email" to selected, "token" to token))
    }

    private fun fail(error: Exception) {
        val code = (error as? ApiException)?.statusCode
        finishError("auth", if (code == 10) "Confira o pacote e o SHA-1 do cliente OAuth Android."
            else "Não foi possível autorizar. Confira a conexão, o Google Play Services e o consentimento do projeto.")
    }

    private fun finishError(code: String, message: String) {
        val result = pending
        pending = null
        selected = null
        result?.error(code, message, null)
    }

    @Deprecated("Activity result bridge for FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7101 && requestCode != 7102) return
        if (pending == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            finishError("cancelled", "Conexão cancelada.")
            return
        }
        if (requestCode == 7101) {
            selected = data.getStringExtra(AccountManager.KEY_ACCOUNT_NAME)
            if (selected == null || data.getStringExtra(AccountManager.KEY_ACCOUNT_TYPE) != "com.google")
                finishError("auth", "Selecione uma conta Google.")
            else authorize()
        } else try {
            complete(authorization.getAuthorizationResultFromIntent(data).accessToken)
        } catch (error: Exception) { fail(error) }
    }

    override fun onDestroy() {
        if (pending != null) finishError("cancelled", "Conexão interrompida. Tente novamente.")
        super.onDestroy()
    }
}
