#include "drive_bridge.h"
#include <windows.h>
#include <wincrypt.h>
#include <shellapi.h>
#include <flutter/standard_method_codec.h>
#include <string>
#include <vector>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDriveBridge(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "somia/windows_drive", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const auto* args = call.arguments();
    if (call.method_name() == "launch") {
      const auto* url = args ? std::get_if<std::string>(args) : nullptr;
      const std::string prefix = "https://accounts.google.com/o/oauth2/v2/auth?";
      if (!url || url->size() > 16384 || url->compare(0, prefix.size(), prefix) != 0) {
        result->Error("url", "Endereço de autorização inválido.");
        return;
      }
      const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
          url->data(), static_cast<int>(url->size()), nullptr, 0);
      if (length <= 0) { result->Error("url", "Endereço inválido."); return; }
      std::wstring wide(static_cast<size_t>(length), L'\0');
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url->data(),
          static_cast<int>(url->size()), wide.data(), length);
      const auto launched = reinterpret_cast<INT_PTR>(
          ShellExecuteW(nullptr, L"open", wide.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
      if (launched <= 32) result->Error("browser", "Não foi possível abrir o navegador.");
      else result->Success();
      return;
    }
    if (call.method_name() != "protect" && call.method_name() != "unprotect") {
      result->NotImplemented(); return;
    }
    const auto* bytes = args ? std::get_if<std::vector<uint8_t>>(args) : nullptr;
    if (!bytes || bytes->empty() || bytes->size() > 131072) {
      result->Error("data", "Credenciais inválidas."); return;
    }
    DATA_BLOB input{static_cast<DWORD>(bytes->size()), const_cast<BYTE*>(bytes->data())};
    DATA_BLOB output{};
    const BOOL success = call.method_name() == "protect"
        ? CryptProtectData(&input, L"Somia Drive", nullptr, nullptr, nullptr,
                           CRYPTPROTECT_UI_FORBIDDEN, &output)
        : CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                             CRYPTPROTECT_UI_FORBIDDEN, &output);
    if (!success) { result->Error("dpapi", "Não foi possível proteger ou ler as credenciais."); return; }
    std::vector<uint8_t> value(output.pbData, output.pbData + output.cbData);
    result->Success(flutter::EncodableValue(value));
    SecureZeroMemory(output.pbData, output.cbData);
    LocalFree(output.pbData);
    SecureZeroMemory(value.data(), value.size());
  });
  return channel;
}
