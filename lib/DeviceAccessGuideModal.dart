// DeviceAccessGuideModal.dart
// Explains clearly to users how to access SpeedShare web portals
// across iOS, Android, macOS, Windows, and Linux, with official app download links.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class DeviceAccessGuideModal extends StatefulWidget {
  final String url;
  final String? pin;
  final String title;
  final String subtitle;
  final IconData icon;

  const DeviceAccessGuideModal({
    super.key,
    required this.url,
    this.pin,
    this.title = 'Web Browser Access',
    this.subtitle = 'Access from any device without installing an app',
    this.icon = Icons.language_rounded,
  });

  static Future<void> show(
    BuildContext context, {
    required String url,
    String? pin,
    String title = 'Web Browser Access',
    String subtitle = 'Access from any device without installing an app',
    IconData icon = Icons.language_rounded,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DeviceAccessGuideModal(
        url: url,
        pin: pin,
        title: title,
        subtitle: subtitle,
        icon: icon,
      ),
    );
  }

  @override
  State<DeviceAccessGuideModal> createState() => _DeviceAccessGuideModalState();
}

class _DeviceAccessGuideModalState extends State<DeviceAccessGuideModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _copiedUrl = false;
  bool _copiedPin = false;

  final List<_OsGuideItem> _osList = const [
    _OsGuideItem(
      os: 'iOS',
      icon: Icons.phone_iphone_rounded,
      label: 'iPhone / iPad',
      browser: 'Safari',
      steps: [
        'Connect your iPhone/iPad to the same Wi-Fi network (or this phone\'s Hotspot).',
        'Open the Safari browser.',
        'Type or paste the URL in the address bar and press Go.',
        'Enter the PIN if requested.',
        'Tap any file to download or stream. Downloaded files are saved to your Files app in the "Downloads" folder.',
      ],
      tip: 'Safari supports background audio and full-screen video streaming natively!',
    ),
    _OsGuideItem(
      os: 'Android',
      icon: Icons.android_rounded,
      label: 'Android Phone',
      browser: 'Chrome / Samsung Internet',
      steps: [
        'Connect to the same Wi-Fi or Mobile Hotspot.',
        'Open Google Chrome or Samsung Internet.',
        'Type or paste the URL in the address bar and hit enter.',
        'Enter the PIN if required.',
        'Tap Download or Play. Downloaded files will appear in your notification bar and Downloads folder.',
      ],
      tip: 'Chrome allows downloading multiple files simultaneously at full Wi-Fi speeds.',
      appDownloadUrl:
          'https://play.google.com/store/apps/details?id=com.navnit.speedshare&hl=en_IN',
      appDownloadLabel: 'Get on Google Play Store',
    ),
    _OsGuideItem(
      os: 'macOS',
      icon: Icons.laptop_mac_rounded,
      label: 'Mac (macOS)',
      browser: 'Safari / Chrome',
      steps: [
        'Ensure your Mac is connected to the same Wi-Fi router.',
        'Open Safari, Google Chrome, or Brave.',
        'Paste the URL into the address bar.',
        'Browse shared files, click Download, or stream music and videos directly.',
      ],
      tip: 'You can also open network streams in VLC Media Player (File -> Open Network).',
      appDownloadUrl:
          'https://github.com/navin280123/SpeedShare/blob/main/installers/Speed%20Share.dmg',
      appDownloadLabel: 'Download macOS App (.dmg)',
    ),
    _OsGuideItem(
      os: 'Windows',
      icon: Icons.desktop_windows_rounded,
      label: 'Windows PC',
      browser: 'Microsoft Edge / Chrome',
      steps: [
        'Connect your PC or laptop to the same Wi-Fi network.',
        'Open Microsoft Edge, Google Chrome, or Firefox.',
        'Enter the URL into the address bar.',
        'Files download straight to your C:\\Users\\...\\Downloads folder.',
      ],
      tip: 'If Windows Firewall asks to allow private network communication on the host device, click "Allow".',
      appDownloadUrl:
          'https://apps.microsoft.com/detail/9pfbqjvlrwng?hl=en-GB&gl=IN',
      appDownloadLabel: 'Get from Microsoft Store',
    ),
    _OsGuideItem(
      os: 'Linux',
      icon: Icons.terminal_rounded,
      label: 'Linux',
      browser: 'Firefox / Chromium / cURL',
      steps: [
        'Connect to the same local network.',
        'Open Firefox, Chromium, or any browser.',
        'Navigate to the URL to access files or stream media.',
        'You can also download directly via terminal using wget or curl!',
      ],
      tip: 'Command-line tip: wget -r --no-parent <URL> to grab shared files.',
      appDownloadUrl:
          'https://github.com/navin280123/SpeedShare/blob/main/installers/speedshare_amd64.deb',
      appDownloadLabel: 'Download Linux Package (.deb)',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _osList.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openExternalUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, bool isPin) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() {
      if (isPin) {
        _copiedPin = true;
      } else {
        _copiedUrl = true;
      }
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isPin ? 'PIN copied to clipboard' : 'URL copied to clipboard'),
        backgroundColor: const Color(0xFF2AB673),
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          if (isPin) {
            _copiedPin = false;
          } else {
            _copiedUrl = false;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFF4E6AF3);
    final accentColor = const Color(0xFF2AB673);
    final cardBg = isDark ? const Color(0xFF1E2235) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131622) : const Color(0xFFF7F9FC),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header with real SpeedShare App Icon
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primaryColor, accentColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.asset(
                          'assets/icon.png',
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Poppins',
                              color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                            ),
                          ),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Scrollable content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(18),
                  children: [
                    // URL Box
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.08),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.link_rounded, size: 16, color: primaryColor),
                              const SizedBox(width: 6),
                              Text(
                                'OPEN THIS URL IN ANY BROWSER',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.35)
                                  : Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    widget.url,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4E6AF3),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _copyToClipboard(widget.url, false),
                                  icon: Icon(
                                    _copiedUrl ? Icons.check_rounded : Icons.copy_rounded,
                                    size: 15,
                                  ),
                                  label: Text(_copiedUrl ? 'Copied' : 'Copy'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // PIN Row if applicable
                          if (widget.pin != null && widget.pin!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.lock_rounded, size: 14, color: accentColor),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Access PIN: ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: accentColor.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Text(
                                        widget.pin!,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2,
                                          fontSize: 13,
                                          color: accentColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: () => _copyToClipboard(widget.pin!, true),
                                  icon: Icon(
                                    _copiedPin ? Icons.check_rounded : Icons.copy_rounded,
                                    size: 13,
                                  ),
                                  label: Text(
                                    _copiedPin ? 'Copied' : 'Copy PIN',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: accentColor,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // OS Tab Bar
                    Text(
                      'HOW TO ACCESS ON YOUR DEVICE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 10),

                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      labelColor: primaryColor,
                      unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
                      indicatorColor: primaryColor,
                      indicatorWeight: 3,
                      tabAlignment: TabAlignment.start,
                      tabs: _osList.map((item) {
                        return Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(item.icon, size: 16),
                              const SizedBox(width: 6),
                              Text(item.os, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 14),

                    // Tab View container
                    SizedBox(
                      height: 290,
                      child: TabBarView(
                        controller: _tabController,
                        children: _osList.map((item) {
                          return _buildOsGuideView(item, isDark, cardBg, primaryColor);
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Official App Download Links Section
                    _buildOfficialAppDownloadsCard(isDark, cardBg, primaryColor),

                    const SizedBox(height: 16),

                    // Important Network Checklist
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.blueGrey.withValues(alpha: 0.12)
                            : Colors.blue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF4E6AF3)),
                              SizedBox(width: 8),
                              Text(
                                'Local Network Checklist',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF4E6AF3),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildBullet(
                            'Both devices must be connected to the same Wi-Fi router or Phone Hotspot.',
                            isDark,
                          ),
                          _buildBullet(
                            'No internet or cellular data is required—transfers stay within your local Wi-Fi.',
                            isDark,
                          ),
                          _buildBullet(
                            'If the link doesn\'t open: turn on Hotspot on one phone, connect the other device to it, and use the new Hotspot IP.',
                            isDark,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOfficialAppDownloadsCard(bool isDark, Color cardBg, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/icon.png',
                  width: 20,
                  height: 20,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'GET OFFICIAL SPEEDSHARE APP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: Color(0xFF4E6AF3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Install the native app on your receiver device for full background sync and top Wi-Fi speeds:',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),

          // Android
          _buildAppDownloadTile(
            title: 'Android',
            subtitle: 'Google Play Store',
            url: 'https://play.google.com/store/apps/details?id=com.navnit.speedshare&hl=en_IN',
            icon: Icons.android_rounded,
            badgeColor: const Color(0xFF3DDC84),
            isDark: isDark,
          ),
          const SizedBox(height: 8),

          // Windows
          _buildAppDownloadTile(
            title: 'Windows',
            subtitle: 'Microsoft Store',
            url: 'https://apps.microsoft.com/detail/9pfbqjvlrwng?hl=en-GB&gl=IN',
            icon: Icons.desktop_windows_rounded,
            badgeColor: const Color(0xFF0078D4),
            isDark: isDark,
          ),
          const SizedBox(height: 8),

          // macOS
          _buildAppDownloadTile(
            title: 'macOS',
            subtitle: 'Direct .dmg Installer',
            url: 'https://github.com/navin280123/SpeedShare/blob/main/installers/Speed%20Share.dmg',
            icon: Icons.laptop_mac_rounded,
            badgeColor: const Color(0xFFA2AAAD),
            isDark: isDark,
          ),
          const SizedBox(height: 8),

          // Linux
          _buildAppDownloadTile(
            title: 'Linux',
            subtitle: 'Debian / Ubuntu .deb package',
            url: 'https://github.com/navin280123/SpeedShare/blob/main/installers/speedshare_amd64.deb',
            icon: Icons.terminal_rounded,
            badgeColor: const Color(0xFFE95420),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildAppDownloadTile({
    required String title,
    required String subtitle,
    required String url,
    required IconData icon,
    required Color badgeColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: badgeColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: 'Copy download link',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$title download link copied to clipboard'),
                  backgroundColor: const Color(0xFF2AB673),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          ElevatedButton(
            onPressed: () => _openExternalUrl(url),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4E6AF3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Get App', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildOsGuideView(_OsGuideItem item, bool isDark, Color cardBg, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, size: 20, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.browser,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: item.steps.length,
              itemBuilder: (context, idx) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.only(top: 2, right: 8),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${idx + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.steps[idx],
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: isDark ? Colors.grey[300] : Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (item.tip.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2AB673).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates_rounded, size: 14, color: Color(0xFF2AB673)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.tip,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF2AB673)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (item.appDownloadUrl != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openExternalUrl(item.appDownloadUrl!),
                icon: const Icon(Icons.download_rounded, size: 15),
                label: Text(
                  item.appDownloadLabel ?? 'Download App',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBullet(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFF4E6AF3), fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OsGuideItem {
  final String os;
  final IconData icon;
  final String label;
  final String browser;
  final List<String> steps;
  final String tip;
  final String? appDownloadUrl;
  final String? appDownloadLabel;

  const _OsGuideItem({
    required this.os,
    required this.icon,
    required this.label,
    required this.browser,
    required this.steps,
    required this.tip,
    this.appDownloadUrl,
    this.appDownloadLabel,
  });
}
