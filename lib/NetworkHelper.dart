import 'dart:io';

class NetworkHelper {
  /// Checks whether an interface name belongs to a cellular/mobile data interface.
  static bool isCellularInterface(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith('rmnet') ||
        lower.startsWith('ccmni') ||
        lower.startsWith('pdp') ||
        lower.startsWith('dummy') ||
        lower.startsWith('seth') ||
        lower.startsWith('wwan') ||
        lower.startsWith('cellular') ||
        lower.startsWith('radio') ||
        lower.startsWith('ipa') ||
        lower.startsWith('v4-rmnet') ||
        lower.startsWith('usb_rmnet');
  }

  /// Gets the best local IPv4 address for local network communication (Wi-Fi, Ethernet, Hotspot).
  ///
  /// Prioritizes physical Wi-Fi, Ethernet, and Hotspot interfaces, while ignoring
  /// loopback, link-local, and cellular (mobile data) interfaces.
  static Future<String?> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      // Pass 1: find physical Wi-Fi / Ethernet / Hotspot interfaces
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.startsWith('wl') ||
            name.contains('wi-fi') ||
            name.contains('wifi') ||
            name.contains('eth') ||
            name.contains('en') ||
            name.contains('ap') ||
            name.contains('softap') ||
            name.contains('bridge') ||
            name.contains('rndis') ||
            name.contains('swlan') ||
            name.contains('local area connection')) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 &&
                !addr.isLoopback &&
                !addr.address.startsWith('127.') &&
                !addr.address.startsWith('169.254.') &&
                !addr.address.startsWith('0.')) {
              return addr.address;
            }
          }
        }
      }

      // Pass 2: any valid non-loopback, non-cellular IPv4
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('lo') ||
            name.contains('loopback') ||
            isCellularInterface(name)) {
          continue;
        }
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('127.') &&
              !addr.address.startsWith('169.254.') &&
              !addr.address.startsWith('0.')) {
            return addr.address;
          }
        }
      }

      // Pass 3: Fallback to any non-loopback IPv4 if no other was found
      for (var interface in interfaces) {
        if (interface.name.toLowerCase().contains('lo')) continue;
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('127.') &&
              !addr.address.startsWith('0.')) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
