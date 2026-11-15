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

  /// Checks whether an interface belongs to a virtual machine, emulator, container,
  /// bridge, or VPN adapter (very common on Windows e.g. WSL, Hyper-V, VirtualBox, VMware, Tailscale).
  static bool isVirtualOrVpnInterface(String name) {
    final lower = name.toLowerCase();
    return lower.contains('vethernet') ||
        lower.contains('virtual') ||
        lower.contains('vbox') ||
        lower.contains('vmware') ||
        lower.contains('vmnet') ||
        lower.contains('wsl') ||
        lower.contains('hyper-v') ||
        lower.contains('tap') ||
        lower.contains('tun') ||
        lower.contains('tailscale') ||
        lower.contains('zerotier') ||
        lower.contains('bluetooth') ||
        lower.contains('teredo') ||
        lower.contains('isatap');
  }

  /// Gets the best local IPv4 address for local network communication (Wi-Fi, Ethernet, Hotspot).
  ///
  /// Prioritizes:
  /// 1. Physical Wi-Fi interfaces
  /// 2. Physical Ethernet / Wired LAN / Hotspot interfaces
  /// 3. Any other non-virtual, non-cellular local network interface
  /// 4. Virtual / VPN network interfaces (e.g. Tailscale, ZeroTier) if no physical adapter is active
  /// 5. Generic IPv4 fallback
  static Future<String?> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      // Pass 1: Physical Wi-Fi interfaces (highest priority)
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (isVirtualOrVpnInterface(name) || isCellularInterface(name)) {
          continue;
        }
        if (name.contains('wlan') ||
            name.startsWith('wl') ||
            name.contains('wi-fi') ||
            name.contains('wifi')) {
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

      // Pass 2: Physical Ethernet / Wired LAN / Hotspot interfaces
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (isVirtualOrVpnInterface(name) || isCellularInterface(name)) {
          continue;
        }
        if (name.contains('eth') ||
            name.contains('en') ||
            name.contains('ap') ||
            name.contains('softap') ||
            name.contains('bridge') ||
            name.contains('rndis') ||
            name.contains('swlan') ||
            name.contains('local area connection') ||
            name.contains('ethernet')) {
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

      // Pass 3: Any other valid non-loopback, non-virtual, non-cellular IPv4
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('lo') ||
            name.contains('loopback') ||
            isVirtualOrVpnInterface(name) ||
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

      // Pass 4: Virtual or VPN adapters (e.g., Tailscale, ZeroTier, or WSL if intentional)
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('lo') || name.contains('loopback')) continue;
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

      // Pass 5: Fallback to any non-loopback IPv4 if no other was found
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
