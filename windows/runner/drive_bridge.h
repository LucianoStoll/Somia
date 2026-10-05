#ifndef SOMIA_DRIVE_BRIDGE_H_
#define SOMIA_DRIVE_BRIDGE_H_
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDriveBridge(flutter::BinaryMessenger* messenger);
#endif
