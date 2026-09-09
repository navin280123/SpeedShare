// WebPortalHtml.dart
// Provides self-contained, responsive, offline-ready HTML5 web portals
// served by SpeedShare's embedded Dart HTTP servers.
// No external CDNs or internet connection required.

import 'dart:convert';

class WebPortalHtml {
  /// Official SpeedShare download links
  static const String androidUrl =
      'https://play.google.com/store/apps/details?id=com.navnit.speedshare&hl=en_IN';
  static const String windowsUrl =
      'https://apps.microsoft.com/detail/9pfbqjvlrwng?hl=en-GB&gl=IN';
  static const String macosUrl =
      'https://github.com/navin280123/SpeedShare/blob/main/installers/Speed%20Share.dmg';
  static const String linuxUrl =
      'https://github.com/navin280123/SpeedShare/blob/main/installers/speedshare_amd64.deb';

  static String get _appDownloadBannerHtml => '''
    <div class="app-banner">
      <div class="app-banner-info">
        <div style="font-weight: 700; font-size: 14px; color: var(--text);">Official SpeedShare App Available</div>
        <div style="font-size: 11px; color: var(--text-muted);">Transfer up to 10x faster with local sockets & background sync</div>
      </div>
      <div class="app-links">
        <a href="$androidUrl" target="_blank" rel="noopener" class="app-badge-link" title="Get SpeedShare on Google Play">
          Android
        </a>
        <a href="$windowsUrl" target="_blank" rel="noopener" class="app-badge-link" title="Get SpeedShare on Microsoft Store">
          Windows
        </a>
        <a href="$macosUrl" target="_blank" rel="noopener" class="app-badge-link" title="Download SpeedShare for macOS (.dmg)">
          macOS
        </a>
        <a href="$linuxUrl" target="_blank" rel="noopener" class="app-badge-link" title="Download SpeedShare for Linux (.deb)">
          Linux
        </a>
      </div>
    </div>
  ''';

  /// Base CSS shared across all web portals with dark mode, modern typography, and glassmorphism.
  static String get _baseCss => '''
    :root {
      --primary: #4E6AF3;
      --primary-dark: #3b52c4;
      --accent: #2AB673;
      --bg: #0F111A;
      --card-bg: rgba(26, 30, 46, 0.85);
      --card-border: rgba(255, 255, 255, 0.08);
      --text: #F0F3FA;
      --text-muted: #8F9BB3;
      --border-radius: 16px;
      --btn-radius: 12px;
      --font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      -webkit-tap-highlight-color: transparent;
    }
    body {
      font-family: var(--font-family);
      background-color: var(--bg);
      background-image: radial-gradient(circle at 10% 20%, rgba(78, 106, 243, 0.15) 0%, transparent 40%),
                        radial-gradient(circle at 90% 80%, rgba(42, 182, 115, 0.12) 0%, transparent 40%);
      background-attachment: fixed;
      color: var(--text);
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      line-height: 1.5;
    }
    header {
      padding: 20px 24px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid var(--card-border);
      backdrop-filter: blur(12px);
      -webkit-backdrop-filter: blur(12px);
      position: sticky;
      top: 0;
      z-index: 100;
      background: rgba(15, 17, 26, 0.75);
    }
    .logo-container {
      display: flex;
      align-items: center;
      gap: 12px;
      text-decoration: none;
      color: var(--text);
    }
    .logo-icon {
      width: 40px;
      height: 40px;
      background: linear-gradient(135deg, var(--primary), var(--accent));
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 4px 14px rgba(78, 106, 243, 0.35);
    }
    .logo-icon svg {
      width: 22px;
      height: 22px;
      fill: white;
    }
    .logo-title {
      font-size: 20px;
      font-weight: 700;
      letter-spacing: -0.5px;
    }
    .logo-badge {
      font-size: 11px;
      background: rgba(78, 106, 243, 0.2);
      color: #7B93FF;
      border: 1px solid rgba(78, 106, 243, 0.4);
      padding: 2px 8px;
      border-radius: 20px;
      font-weight: 600;
      margin-left: 6px;
    }
    .device-chip {
      display: flex;
      align-items: center;
      gap: 8px;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid var(--card-border);
      padding: 6px 14px;
      border-radius: 20px;
      font-size: 13px;
      color: var(--text-muted);
    }
    .status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--accent);
      box-shadow: 0 0 10px var(--accent);
    }
    main {
      flex: 1;
      max-width: 900px;
      width: 100%;
      margin: 0 auto;
      padding: 24px 16px 40px 16px;
    }
        .app-banner {
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 12px;
      margin-bottom: 20px;
      background: linear-gradient(135deg, rgba(78, 106, 243, 0.12), rgba(42, 182, 115, 0.08));
      border: 1px solid rgba(78, 106, 243, 0.28);
      border-radius: var(--border-radius);
      padding: 12px 18px;
    }
    .app-links {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }
    .app-badge-link {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: rgba(255, 255, 255, 0.07);
      border: 1px solid var(--card-border);
      color: var(--text);
      padding: 6px 12px;
      border-radius: 8px;
      font-size: 12px;
      font-weight: 600;
      text-decoration: none;
      transition: all 0.15s ease;
    }
    .app-badge-link:hover {
      background: var(--primary);
      border-color: var(--primary);
      color: white;
      transform: translateY(-1px);
    }
    .card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: var(--border-radius);
      padding: 24px;
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
      margin-bottom: 20px;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      background: var(--primary);
      color: white;
      border: none;
      padding: 10px 18px;
      border-radius: var(--btn-radius);
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      text-decoration: none;
      transition: all 0.2s ease;
    }
    .btn:hover {
      background: var(--primary-dark);
      transform: translateY(-1px);
      box-shadow: 0 4px 12px rgba(78, 106, 243, 0.4);
    }
    .btn-accent {
      background: var(--accent);
    }
    .btn-accent:hover {
      background: #239c62;
      box-shadow: 0 4px 12px rgba(42, 182, 115, 0.4);
    }
    .btn-outline {
      background: transparent;
      border: 1px solid var(--card-border);
      color: var(--text);
    }
    .btn-outline:hover {
      background: rgba(255, 255, 255, 0.06);
      box-shadow: none;
    }
    .btn-sm {
      padding: 6px 12px;
      font-size: 13px;
      border-radius: 8px;
    }
    .pin-box {
      max-width: 360px;
      margin: 40px auto;
      text-align: center;
    }
    .pin-input {
      width: 100%;
      background: rgba(0, 0, 0, 0.3);
      border: 1px solid var(--card-border);
      color: white;
      padding: 14px;
      border-radius: var(--btn-radius);
      font-size: 22px;
      text-align: center;
      letter-spacing: 6px;
      font-weight: bold;
      margin: 16px 0;
      outline: none;
      transition: border-color 0.2s;
    }
    .pin-input:focus {
      border-color: var(--primary);
      box-shadow: 0 0 16px rgba(78, 106, 243, 0.3);
    }
    .footer {
      text-align: center;
      padding: 20px;
      font-size: 12px;
      color: var(--text-muted);
      border-top: 1px solid var(--card-border);
    }
    @media (max-width: 600px) {
      header { padding: 14px 16px; }
      .card { padding: 16px; }
      .device-chip span.label { display: none; }
    }
  ''';

  /// Real SpeedShare Icon as Base64 PNG
  static const String _iconLogo = '''
    <img src="data:image/png;base64,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" width="38" height="38" style="border-radius: 10px; display: block;" alt="SpeedShare">
  ''';

  static const String _iconDownload = '''
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/></svg>
  ''';

  static const String _iconFolder = '''
    <svg width="20" height="20" viewBox="0 0 24 24" fill="#E5A93C"><path d="M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z"/></svg>
  ''';

  static const String _iconFile = '''
    <svg width="20" height="20" viewBox="0 0 24 24" fill="#4E6AF3"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>
  ''';

  static const String _iconPlay = '''
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
  ''';

  static const String _iconVlc = '''
    <svg width="18" height="18" viewBox="0 0 24 24" fill="#FF8800"><path d="M12 2L9.5 9H14.5L12 2ZM8.8 11L7.3 15H16.7L15.2 11H8.8ZM6.6 17L4.5 22H19.5L17.4 17H6.6Z"/></svg>
  ''';

  static const String _iconCopy = '''
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>
  ''';

  static const String _iconPlaylist = '''
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M4 10h12v2H4zm0-4h12v2H4zm0 8h8v2H4zm10 0v6l5-3z"/></svg>
  ''';

  static const String _iconExternal = '''
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M19 19H5V5h7V3H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2v-7h-2v7zM14 3v2h3.59l-9.83 9.83 1.41 1.41L19 6.41V10h2V3h-7z"/></svg>
  ''';

  // ==========================================
  // 1. FILE SENDER WEB PORTAL (Web Share)
  // ==========================================

  /// Generates the HTML for the Web Share download page.
  static String getWebShareHtml({
    required String hostDeviceName,
    required List<Map<String, dynamic>> files, // {name, size, index}
    String? accessCode,
  }) {
    final filesJson = json.encode(files);
    final hasPin = accessCode != null && accessCode.isNotEmpty;

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SpeedShare · Receive Files</title>
  <style>
    $_baseCss
    .file-table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 16px;
    }
    .file-item {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 14px 16px;
      border-bottom: 1px solid var(--card-border);
      transition: background 0.15s ease;
      border-radius: 10px;
    }
    .file-item:hover {
      background: rgba(255, 255, 255, 0.03);
    }
    .file-info {
      display: flex;
      align-items: center;
      gap: 14px;
      overflow: hidden;
      margin-right: 12px;
    }
    .file-name {
      font-weight: 600;
      font-size: 15px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .file-meta {
      font-size: 12px;
      color: var(--text-muted);
      margin-top: 2px;
    }
    .hero-banner {
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 16px;
      margin-bottom: 24px;
      background: linear-gradient(135deg, rgba(78, 106, 243, 0.15), rgba(42, 182, 115, 0.1));
      border: 1px solid rgba(78, 106, 243, 0.3);
      padding: 20px 24px;
      border-radius: var(--border-radius);
    }
  </style>
</head>
<body>
  <header>
    <a href="#" class="logo-container">
      <div class="logo-icon">$_iconLogo</div>
      <div>
        <span class="logo-title">SpeedShare</span>
        <span class="logo-badge">Web Share</span>
      </div>
    </a>
    <div class="device-chip">
      <div class="status-dot"></div>
      <span class="label">Host: </span>
      <strong>${_escape(hostDeviceName)}</strong>
    </div>
  </header>

  <main>
    $_appDownloadBannerHtml
    ${hasPin ? '''
    <div id="pin-section" class="card pin-box">
      <h3>Security PIN Required</h3>
      <p style="color: var(--text-muted); font-size: 13px; margin-top: 8px;">
        Enter the 4-digit code shown on the sender device
      </p>
      <input type="password" id="pin-input" class="pin-input" maxlength="6" placeholder="PIN" autofocus>
      <button onclick="verifyPin()" class="btn btn-accent" style="width: 100%;">Access Files</button>
      <div id="pin-error" style="color: #ff5252; font-size: 13px; margin-top: 10px; display: none;">Invalid PIN. Please try again.</div>
    </div>
    ''' : ''}

    <div id="content-section" style="${hasPin ? 'display: none;' : ''}">
      <div class="hero-banner">
        <div>
          <h2 style="font-size: 20px; font-weight: 700;">Files Ready to Download</h2>
          <p style="color: var(--text-muted); font-size: 13px; margin-top: 4px;">
            <span id="file-count">${files.length}</span> files shared from <strong>${_escape(hostDeviceName)}</strong>
          </p>
        </div>
        <div>
          <button onclick="downloadAll()" class="btn btn-accent">
            $_iconDownload
            <span>Download All</span>
          </button>
        </div>
      </div>

      <div class="card">
        <div id="files-list"></div>
      </div>
    </div>
  </main>

  <footer class="footer">
    SpeedShare Local Wi-Fi Sharing · High-speed direct device transfer
  </footer>

  <script>
    const files = $filesJson;
    const requiredPin = "${accessCode ?? ''}";

    function formatBytes(bytes) {
      if (!bytes || bytes === 0) return '0 B';
      const k = 1024;
      const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
      const i = Math.floor(Math.log(bytes) / Math.log(k));
      return (bytes / Math.pow(k, i)).toFixed(1) + ' ' + sizes[i];
    }

    function verifyPin() {
      const entered = document.getElementById('pin-input').value.trim();
      if (entered.toUpperCase() === requiredPin.toUpperCase()) {
        document.getElementById('pin-section').style.display = 'none';
        document.getElementById('content-section').style.display = 'block';
        sessionStorage.setItem('speedshare_pin', entered);
      } else {
        document.getElementById('pin-error').style.display = 'block';
      }
    }

    function renderFiles() {
      const container = document.getElementById('files-list');
      if (!files.length) {
        container.innerHTML = '<div style="text-align:center; padding: 30px; color: var(--text-muted);">No files shared</div>';
        return;
      }
      const pin = sessionStorage.getItem('speedshare_pin') || requiredPin;
      const pinParam = pin ? '&code=' + encodeURIComponent(pin) : '';

      container.innerHTML = files.map((f, idx) => `
        <div class="file-item">
          <div class="file-info">
            <div style="flex-shrink: 0;">$_iconFile</div>
            <div>
              <div class="file-name" title="\${f.name}">\${f.name}</div>
              <div class="file-meta">\${formatBytes(f.size)}</div>
            </div>
          </div>
          <a href="/download?index=\${f.index || idx}\${pinParam}" class="btn btn-sm btn-outline" download>
            $_iconDownload
            <span>Download</span>
          </a>
        </div>
      `).join('');
    }

    function downloadAll() {
      const pin = sessionStorage.getItem('speedshare_pin') || requiredPin;
      const pinParam = pin ? '&code=' + encodeURIComponent(pin) : '';
      files.forEach((f, idx) => {
        setTimeout(() => {
          const a = document.createElement('a');
          a.href = '/download?index=' + (f.index || idx) + pinParam;
          a.download = f.name;
          document.body.appendChild(a);
          a.click();
          document.body.removeChild(a);
        }, idx * 600);
      });
    }

    // Auto-login if PIN stored in session
    if (requiredPin && sessionStorage.getItem('speedshare_pin') === requiredPin) {
      const pinSec = document.getElementById('pin-section');
      if (pinSec) pinSec.style.display = 'none';
      document.getElementById('content-section').style.display = 'block';
    }

    renderFiles();
  </script>
</body>
</html>''';
  }

  // ==========================================
  // 2. STORAGE SYNC WEB PORTAL (File Explorer)
  // ==========================================

  /// Generates the HTML for the Web Storage File Explorer.
  static String getSyncWebHtml({
    required String hostDeviceName,
    String? accessCode,
  }) {
    final hasPin = accessCode != null && accessCode.isNotEmpty;

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SpeedShare · Storage Sync</title>
  <style>
    $_baseCss
    .explorer-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 12px;
      margin-bottom: 16px;
    }
    .breadcrumbs {
      display: flex;
      align-items: center;
      gap: 6px;
      flex-wrap: wrap;
      font-size: 13px;
      color: var(--text-muted);
    }
    .breadcrumb-item {
      cursor: pointer;
      color: var(--primary);
      text-decoration: none;
      font-weight: 500;
    }
    .breadcrumb-item:hover {
      text-decoration: underline;
    }
    .search-input {
      background: rgba(0, 0, 0, 0.25);
      border: 1px solid var(--card-border);
      color: white;
      padding: 8px 14px;
      border-radius: var(--btn-radius);
      font-size: 13px;
      outline: none;
      width: 220px;
      transition: all 0.2s;
    }
    .search-input:focus {
      border-color: var(--primary);
      width: 260px;
    }
    .items-grid {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .explorer-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 12px 14px;
      border-radius: 10px;
      cursor: pointer;
      transition: background 0.15s ease;
      border-bottom: 1px solid rgba(255, 255, 255, 0.03);
    }
    .explorer-row:hover {
      background: rgba(255, 255, 255, 0.04);
    }
    .explorer-row-left {
      display: flex;
      align-items: center;
      gap: 12px;
      overflow: hidden;
      flex: 1;
    }
    .explorer-name {
      font-weight: 500;
      font-size: 14px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .explorer-size {
      font-size: 12px;
      color: var(--text-muted);
      margin-left: 8px;
    }
  </style>
</head>
<body>
  <header>
    <a href="#" class="logo-container">
      <div class="logo-icon">$_iconLogo</div>
      <div>
        <span class="logo-title">SpeedShare</span>
        <span class="logo-badge">Storage Sync</span>
      </div>
    </a>
    <div class="device-chip">
      <div class="status-dot"></div>
      <span class="label">Host: </span>
      <strong>${_escape(hostDeviceName)}</strong>
    </div>
  </header>

  <main>
    $_appDownloadBannerHtml
    ${hasPin ? '''
    <div id="pin-section" class="card pin-box">
      <h3>Storage Access PIN</h3>
      <p style="color: var(--text-muted); font-size: 13px; margin-top: 8px;">
        Enter the sync PIN from the host device
      </p>
      <input type="text" id="pin-input" class="pin-input" placeholder="PIN" autofocus>
      <button onclick="unlockStorage()" class="btn btn-accent" style="width: 100%;">Connect to Storage</button>
      <div id="pin-error" style="color: #ff5252; font-size: 13px; margin-top: 10px; display: none;">Invalid PIN. Please try again.</div>
    </div>
    ''' : ''}

    <div id="explorer-section" style="${hasPin ? 'display: none;' : ''}">
      <div class="card">
        <div class="explorer-header">
          <div id="breadcrumbs" class="breadcrumbs">
            <span class="breadcrumb-item" onclick="navigateTo('')">Root</span>
          </div>
          <div>
            <input type="text" id="search-box" class="search-input" placeholder="Filter files..." oninput="filterItems()">
          </div>
        </div>

        <div id="explorer-body">
          <div style="text-align: center; padding: 40px; color: var(--text-muted);">
            Loading folder contents...
          </div>
        </div>
      </div>
    </div>
  </main>

  <footer class="footer">
    SpeedShare Local Wi-Fi Storage Sync · Direct LAN browsing
  </footer>

  <script>
    let currentPath = '';
    let loadedItems = [];
    const expectedPin = "${accessCode ?? ''}";

    function getActivePin() {
      return sessionStorage.getItem('speedshare_sync_pin') || expectedPin;
    }

    function formatBytes(bytes) {
      if (!bytes || bytes === 0) return '';
      const k = 1024;
      const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
      const i = Math.floor(Math.log(bytes) / Math.log(k));
      return (bytes / Math.pow(k, i)).toFixed(1) + ' ' + sizes[i];
    }

    function unlockStorage() {
      const pin = document.getElementById('pin-input').value.trim().toUpperCase();
      sessionStorage.setItem('speedshare_sync_pin', pin);
      loadFolder(currentPath, (success) => {
        if (success) {
          document.getElementById('pin-section').style.display = 'none';
          document.getElementById('explorer-section').style.display = 'block';
        } else {
          document.getElementById('pin-error').style.display = 'block';
        }
      });
    }

    async function loadFolder(path, callback) {
      const pin = getActivePin();
      const url = '/api/files?path=' + encodeURIComponent(path) + (pin ? '&code=' + encodeURIComponent(pin) : '');
      try {
        const resp = await fetch(url);
        if (!resp.ok) {
          if (callback) callback(false);
          return;
        }
        const data = await resp.json();
        currentPath = path;
        loadedItems = data;
        renderItems(data);
        renderBreadcrumbs(path);
        if (callback) callback(true);
      } catch (err) {
        document.getElementById('explorer-body').innerHTML = '<div style="color:#ff5252; text-align:center; padding:30px;">Error loading folder: ' + err.message + '</div>';
        if (callback) callback(false);
      }
    }

    function renderBreadcrumbs(path) {
      const container = document.getElementById('breadcrumbs');
      if (!path) {
        container.innerHTML = '<span class="breadcrumb-item" onclick="navigateTo(\\'\\')">Root</span>';
        return;
      }
      const parts = path.split('/').filter(Boolean);
      let html = '<span class="breadcrumb-item" onclick="navigateTo(\\'\\')">Root</span>';
      let accum = '';
      parts.forEach((p, idx) => {
        accum += '/' + p;
        const thisPath = accum;
        if (idx === parts.length - 1) {
          html += ' / <span>' + p + '</span>';
        } else {
          html += ' / <span class="breadcrumb-item" onclick="navigateTo(\\'' + thisPath + '\\')">' + p + '</span>';
        }
      });
      container.innerHTML = html;
    }

    function renderItems(items) {
      const container = document.getElementById('explorer-body');
      if (!items.length) {
        container.innerHTML = '<div style="text-align:center; padding: 40px; color: var(--text-muted);">Empty folder</div>';
        return;
      }
      const pin = getActivePin();
      const pinParam = pin ? '&code=' + encodeURIComponent(pin) : '';

      container.innerHTML = items.map(item => {
        if (item.isDirectory) {
          return `
            <div class="explorer-row" onclick="navigateTo('\${item.path}')">
              <div class="explorer-row-left">
                $_iconFolder
                <span class="explorer-name">\${item.name}</span>
              </div>
              <span style="font-size: 12px; color: var(--text-muted);">Folder &rarr;</span>
            </div>
          `;
        } else {
          return `
            <div class="explorer-row">
              <div class="explorer-row-left">
                $_iconFile
                <span class="explorer-name">\${item.name}</span>
                <span class="explorer-size">\${formatBytes(item.size)}</span>
              </div>
              <a href="/api/download?path=\${encodeURIComponent(item.path)}\${pinParam}" class="btn btn-sm btn-outline" download>
                $_iconDownload
                <span>Download</span>
              </a>
            </div>
          `;
        }
      }).join('');
    }

    function filterItems() {
      const query = document.getElementById('search-box').value.toLowerCase();
      const filtered = loadedItems.filter(it => it.name.toLowerCase().includes(query));
      renderItems(filtered);
    }

    function navigateTo(path) {
      document.getElementById('search-box').value = '';
      loadFolder(path);
    }

    // Auto-init
    if (expectedPin) {
      if (sessionStorage.getItem('speedshare_sync_pin')) {
        unlockStorage();
      }
    } else {
      loadFolder('');
    }
  </script>
</body>
</html>''';
  }

  // ==========================================
  // 3. MEDIA STREAM WEB PORTAL (Media Player)
  // ==========================================

  /// Generates the HTML for the Live Media Streaming web player with VLC / external player support.
  static String getStreamWebHtml({
    required String hostDeviceName,
    String? accessCode,
  }) {
    final hasPin = accessCode != null && accessCode.isNotEmpty;
    final pinDisplay = hasPin ? 'display: none;' : '';
    final pinSectionHtml = hasPin
        ? '''
    <div id="pin-section" class="card pin-box">
      <h3>Stream Access PIN</h3>
      <p style="color: var(--text-muted); font-size: 13px; margin-top: 8px;">
        Enter the 4-digit PIN shown on the stream host
      </p>
      <input type="text" id="pin-input" class="pin-input" maxlength="6" placeholder="PIN" autofocus>
      <button onclick="unlockStream()" class="btn btn-accent" style="width: 100%;">Connect to Stream</button>
      <div id="pin-error" style="color: #ff5252; font-size: 13px; margin-top: 10px; display: none;">Invalid PIN. Please try again.</div>
    </div>'''
        : '';

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SpeedShare · Stream Player</title>
  <style>
    $_baseCss
    .player-container {
      background: #000;
      border-radius: var(--border-radius);
      overflow: hidden;
      margin-bottom: 24px;
      border: 1px solid var(--card-border);
      box-shadow: 0 12px 36px rgba(0, 0, 0, 0.5);
    }
    video, audio {
      width: 100%;
      outline: none;
      display: block;
    }
    .video-view {
      max-height: 480px;
      background: #000;
    }
    .now-playing-banner {
      padding: 16px 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      background: rgba(255, 255, 255, 0.03);
      border-top: 1px solid var(--card-border);
      flex-wrap: wrap;
    }
    .player-actions {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }
    .btn-vlc {
      background: linear-gradient(135deg, #FF7700 0%, #E65100 100%);
      color: #fff !important;
      border: none;
      font-weight: 600;
      box-shadow: 0 3px 10px rgba(255, 119, 0, 0.35);
    }
    .btn-vlc:hover {
      background: linear-gradient(135deg, #FF8800 0%, #F57C00 100%);
      transform: translateY(-1px);
    }
    .codec-notice {
      background: rgba(255, 119, 0, 0.12);
      border: 1px solid rgba(255, 119, 0, 0.35);
      border-radius: 12px;
      padding: 12px 16px;
      margin: 12px 20px;
      display: none;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      font-size: 13px;
    }
    .media-card {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 14px 16px;
      border-radius: 12px;
      cursor: pointer;
      transition: all 0.2s ease;
      border-bottom: 1px solid rgba(255, 255, 255, 0.03);
    }
    .media-card:hover {
      background: rgba(78, 106, 243, 0.1);
      transform: translateX(4px);
    }
    .media-card.active {
      background: rgba(78, 106, 243, 0.2);
      border-left: 3px solid var(--primary);
    }
    .media-info {
      display: flex;
      align-items: center;
      gap: 14px;
      overflow: hidden;
    }
    .media-icon {
      width: 36px;
      height: 36px;
      border-radius: 8px;
      background: rgba(78, 106, 243, 0.2);
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--primary);
      flex-shrink: 0;
    }
    .media-name {
      font-weight: 600;
      font-size: 14px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .media-meta {
      font-size: 12px;
      color: var(--text-muted);
    }

    /* External Player Modal */
    .modal-backdrop {
      position: fixed;
      top: 0; left: 0; right: 0; bottom: 0;
      background: rgba(0, 0, 0, 0.8);
      backdrop-filter: blur(10px);
      -webkit-backdrop-filter: blur(10px);
      z-index: 10000;
      display: none;
      align-items: center;
      justify-content: center;
      padding: 16px;
    }
    .modal-card {
      background: #141724;
      border: 1px solid var(--card-border);
      border-radius: 18px;
      max-width: 500px;
      width: 100%;
      box-shadow: 0 24px 60px rgba(0, 0, 0, 0.85);
      overflow: hidden;
      animation: modalPop 0.2s cubic-bezier(0.16, 1, 0.3, 1);
    }
    @keyframes modalPop {
      from { opacity: 0; transform: scale(0.94); }
      to { opacity: 1; transform: scale(1); }
    }
    .modal-header {
      padding: 16px 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid var(--card-border);
      background: rgba(255, 255, 255, 0.02);
    }
    .modal-body {
      padding: 20px;
      max-height: 80vh;
      overflow-y: auto;
    }
    .modal-option {
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      padding: 14px;
      margin-bottom: 12px;
      transition: all 0.2s;
    }
    .modal-option:hover {
      border-color: rgba(255, 255, 255, 0.15);
      background: rgba(255, 255, 255, 0.05);
    }
  </style>
</head>
<body>
  <header>
    <a href="#" class="logo-container">
      <div class="logo-icon">$_iconLogo</div>
      <div>
        <span class="logo-title">SpeedShare</span>
        <span class="logo-badge">Live Stream</span>
      </div>
    </a>
    <div class="device-chip">
      <div class="status-dot"></div>
      <span class="label">Host: </span>
      <strong>${_escape(hostDeviceName)}</strong>
    </div>
  </header>

  <main>
    $_appDownloadBannerHtml
    $pinSectionHtml
    <div id="stream-section" style="$pinDisplay">
      <div class="player-container">
        <video id="player-video" class="video-view" controls playsinline></video>

        <!-- Browser Codec Warning Bar (shown if browser cannot decode video format) -->
        <div id="codec-alert" class="codec-notice">
          <div style="display: flex; align-items: center; gap: 8px;">
            $_iconVlc
            <span>Browser cannot decode this video format natively (e.g. MKV/AC3).</span>
          </div>
          <button onclick="openCurrentInExternalModal()" class="btn btn-sm btn-vlc">
            Play in VLC
          </button>
        </div>

        <div class="now-playing-banner">
          <div style="flex: 1; min-width: 0;">
            <div id="current-title" style="font-weight: 600; font-size: 15px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">Select a track to play</div>
            <div id="current-meta" style="font-size: 12px; color: var(--text-muted); margin-top: 2px;">Direct stream from host</div>
          </div>
          <div class="player-actions">
            <button id="btn-play-vlc" class="btn btn-sm btn-vlc" onclick="openCurrentInExternalModal()" style="display: none;" title="Play in VLC Media Player / External Player">
              $_iconVlc
              <span>Play in VLC</span>
            </button>
            <button id="btn-copy-url" class="btn btn-sm btn-outline" onclick="copyCurrentStreamUrl()" style="display: none;" title="Copy direct stream URL for media players">
              $_iconCopy
              <span id="copy-btn-text">Copy URL</span>
            </button>
            <a id="current-m3u" href="#" class="btn btn-sm btn-outline" download style="display: none;" title="Download .m3u playlist file (opens directly in VLC, PotPlayer, IINA)">
              $_iconPlaylist
              <span>M3U</span>
            </a>
            <a id="current-download" href="#" class="btn btn-sm btn-outline" download style="display: none;" title="Save media file directly">
              $_iconDownload
              <span>Save</span>
            </a>
          </div>
        </div>
      </div>

      <div class="card">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; flex-wrap: wrap; gap: 10px;">
          <h3 style="font-size: 16px;">Media Catalog</h3>
          <a id="all-playlist-btn" href="/api/stream/playlist.m3u" class="btn btn-sm btn-outline" download="speedshare_playlist.m3u" style="color: #FF8800; border-color: rgba(255, 136, 0, 0.4);" title="Download full .m3u playlist for VLC">
            $_iconVlc
            <span>VLC Playlist (.m3u)</span>
          </a>
        </div>
        <div id="catalog-list">
          <div style="text-align: center; padding: 30px; color: var(--text-muted);">Loading playlist...</div>
        </div>
      </div>
    </div>
  </main>

  <!-- External Player Modal Dialog -->
  <div id="external-modal" class="modal-backdrop">
    <div class="modal-card">
      <div class="modal-header">
        <div style="display: flex; align-items: center; gap: 10px; overflow: hidden;">
          <div style="background: rgba(255, 136, 0, 0.15); padding: 8px; border-radius: 10px; display: flex; flex-shrink: 0;">
            $_iconVlc
          </div>
          <div style="overflow: hidden;">
            <div style="font-weight: 700; font-size: 15px; color: #fff;">Play in VLC / External Player</div>
            <div id="modal-track-name" style="font-size: 12px; color: var(--text-muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">Track Title</div>
          </div>
        </div>
        <button onclick="closeExternalModal()" style="background: none; border: none; color: var(--text-muted); font-size: 24px; cursor: pointer; line-height: 1; padding: 4px 8px;">&times;</button>
      </div>

      <div class="modal-body">
        <!-- Option 1: Direct App Launch -->
        <div class="modal-option" style="border-color: rgba(255, 136, 0, 0.35); background: rgba(255, 136, 0, 0.06);">
          <div style="font-weight: 600; font-size: 14px; margin-bottom: 4px; color: #FFA040; display: flex; align-items: center; justify-content: space-between;">
            <span>1. Launch in VLC Player</span>
            <span style="font-size: 11px; background: rgba(255, 136, 0, 0.25); color: #FFA040; padding: 2px 8px; border-radius: 6px;">Recommended</span>
          </div>
          <div style="font-size: 12px; color: var(--text-muted); margin-bottom: 12px;">
            Opens the stream in VLC on Android, iOS, Windows, and macOS.
          </div>
          <div style="display: flex; gap: 8px; flex-wrap: wrap;">
            <button onclick="launchVlcProtocol()" class="btn btn-sm btn-vlc">
              $_iconVlc
              <span>Open in VLC</span>
            </button>
            <button id="modal-android-btn" onclick="launchAndroidPlayerIntent()" class="btn btn-sm btn-outline" style="display: none;">
              $_iconExternal
              <span>Android Player Chooser</span>
            </button>
          </div>
        </div>

        <!-- Option 2: Download .m3u Stream File -->
        <div class="modal-option">
          <div style="font-weight: 600; font-size: 14px; margin-bottom: 4px; color: #738AFF;">
            2. Stream File (.m3u)
          </div>
          <div style="font-size: 12px; color: var(--text-muted); margin-bottom: 10px;">
            Double-clicking this file automatically opens VLC, IINA, PotPlayer, or Windows Media Player.
          </div>
          <a id="modal-m3u-link" href="#" class="btn btn-sm btn-outline" download style="display: inline-flex; align-items: center; gap: 6px;">
            $_iconPlaylist
            <span>Download .m3u Stream File</span>
          </a>
        </div>

        <!-- Option 3: Copy Stream URL -->
        <div class="modal-option" style="border-color: rgba(42, 182, 115, 0.3); background: rgba(42, 182, 115, 0.05);">
          <div style="font-weight: 600; font-size: 14px; margin-bottom: 4px; color: #2AB673;">
            3. Network Stream URL
          </div>
          <div style="font-size: 12px; color: var(--text-muted); margin-bottom: 8px;">
            Paste stream URL directly into your favorite media player:
          </div>
          <div style="display: flex; gap: 8px; margin-bottom: 10px;">
            <input id="modal-url-input" type="text" readonly style="flex: 1; background: rgba(0,0,0,0.5); border: 1px solid var(--card-border); border-radius: 8px; padding: 8px 10px; font-size: 12px; color: var(--text); outline: none;">
            <button id="modal-copy-btn" onclick="copyModalUrl()" class="btn btn-sm btn-accent" style="white-space: nowrap;">
              $_iconCopy
              <span id="modal-copy-text">Copy</span>
            </button>
          </div>
          <div style="font-size: 11px; color: var(--text-muted); line-height: 1.6;">
            <strong>Quick Shortcuts:</strong><br>
            • <b>VLC (PC/Mac/Linux):</b> Press <kbd style="background: rgba(255,255,255,0.12); padding: 1px 5px; border-radius: 4px;">Ctrl+N</kbd> / <kbd style="background: rgba(255,255,255,0.12); padding: 1px 5px; border-radius: 4px;">Cmd+N</kbd> ➔ Paste URL.<br>
            • <b>IINA (Mac):</b> Press <kbd style="background: rgba(255,255,255,0.12); padding: 1px 5px; border-radius: 4px;">Cmd+U</kbd> ➔ Paste URL.<br>
            • <b>PotPlayer (Windows):</b> Press <kbd style="background: rgba(255,255,255,0.12); padding: 1px 5px; border-radius: 4px;">Ctrl+U</kbd> ➔ Paste URL.<br>
            • <b>VLC Mobile (Android/iOS):</b> More ➔ New Stream ➔ Paste URL.
          </div>
        </div>
      </div>
    </div>
  </div>

  <footer class="footer">
    SpeedShare Local Wi-Fi Media Stream · Lossless real-time playback
    <div style="margin-top: 8px; font-size: 11px; opacity: 0.8;">
      Get native apps: 
      <a href="$androidUrl" target="_blank" rel="noopener" style="color: #4E6AF3; text-decoration: none; margin: 0 4px;">Android</a> · 
      <a href="$windowsUrl" target="_blank" rel="noopener" style="color: #4E6AF3; text-decoration: none; margin: 0 4px;">Windows</a> · 
      <a href="$macosUrl" target="_blank" rel="noopener" style="color: #4E6AF3; text-decoration: none; margin: 0 4px;">macOS</a> · 
      <a href="$linuxUrl" target="_blank" rel="noopener" style="color: #4E6AF3; text-decoration: none; margin: 0 4px;">Linux</a>
    </div>
  </footer>

  <script>
    let playlist = [];
    let activeIndex = -1;
    let modalItem = null;
    const requiredPin = "${accessCode ?? ''}";

    function getPin() {
      return sessionStorage.getItem("speedshare_stream_pin") || requiredPin;
    }

    function formatBytes(bytes) {
      if (!bytes || bytes === 0) return "";
      const k = 1024;
      const sizes = ["B", "KB", "MB", "GB", "TB"];
      const i = Math.floor(Math.log(bytes) / Math.log(k));
      return (bytes / Math.pow(k, i)).toFixed(1) + " " + sizes[i];
    }

    function getFullStreamUrl(item) {
      const pin = getPin();
      const origin = window.location.origin;
      return origin + "/api/stream/media?id=" + encodeURIComponent(item.id) + (pin ? "&code=" + encodeURIComponent(pin) : "");
    }

    function getM3uUrl(item) {
      const pin = getPin();
      const origin = window.location.origin;
      return origin + "/api/stream/playlist.m3u" + (item ? "?id=" + encodeURIComponent(item.id) : "") + (pin ? (item ? "&code=" : "?code=") + encodeURIComponent(pin) : "");
    }

    function unlockStream() {
      const pin = document.getElementById("pin-input").value.trim();
      sessionStorage.setItem("speedshare_stream_pin", pin);
      loadCatalog((success) => {
        if (success) {
          document.getElementById("pin-section").style.display = "none";
          document.getElementById("stream-section").style.display = "block";
        } else {
          document.getElementById("pin-error").style.display = "block";
        }
      });
    }

    async function loadCatalog(callback) {
      const pin = getPin();
      const url = "/api/stream/catalog" + (pin ? "?code=" + encodeURIComponent(pin) : "");
      try {
        const resp = await fetch(url);
        if (!resp.ok) {
          if (callback) callback(false);
          return;
        }
        const data = await resp.json();
        playlist = data.items || [];
        renderCatalog();

        const allPlaylistBtn = document.getElementById("all-playlist-btn");
        if (allPlaylistBtn) {
          allPlaylistBtn.href = "/api/stream/playlist.m3u" + (pin ? "?code=" + encodeURIComponent(pin) : "");
        }

        if (playlist.length > 0) {
          playMedia(0, false);
        }
        if (callback) callback(true);
      } catch (e) {
        if (callback) callback(false);
      }
    }

    function renderCatalog() {
      const list = document.getElementById("catalog-list");
      if (!playlist.length) {
        list.innerHTML = '<div style="text-align:center; padding: 20px; color: var(--text-muted);">No media items shared</div>';
        return;
      }
      list.innerHTML = playlist.map((item, idx) => `
        <div class="media-card \${idx === activeIndex ? "active" : ""}" onclick="playMedia(\${idx}, true)">
          <div class="media-info">
            <div class="media-icon">$_iconPlay</div>
            <div style="overflow: hidden;">
              <div class="media-name" title="\${item.name}">\${item.name}</div>
              <div class="media-meta">\${item.type || "Media"} · \${formatBytes(item.size)}</div>
            </div>
          </div>
          <div style="display: flex; gap: 6px; align-items: center;" onclick="event.stopPropagation()">
            <button class="btn btn-sm btn-outline" onclick="openItemInExternalModal(\${idx})" title="Play in VLC / External Player" style="border-color: rgba(255, 136, 0, 0.4); color: #FF8800; padding: 6px 10px;">
              $_iconVlc
              <span style="margin-left: 4px; font-size: 12px;">VLC</span>
            </button>
            <button class="btn btn-sm btn-outline" onclick="playMedia(\${idx}, true)" title="Play in Browser">
              $_iconPlay
            </button>
          </div>
        </div>
      `).join("");
    }

    function playMedia(index, autoPlay) {
      if (index < 0 || index >= playlist.length) return;
      activeIndex = index;
      const item = playlist[index];
      const pin = getPin();
      const streamUrl = "/api/stream/media?id=" + encodeURIComponent(item.id) + (pin ? "&code=" + encodeURIComponent(pin) : "");

      const player = document.getElementById("player-video");
      document.getElementById("codec-alert").style.display = "none";
      player.src = streamUrl;
      if (autoPlay) {
        player.play().catch(() => {});
      }

      document.getElementById("current-title").innerText = item.name;
      document.getElementById("current-meta").innerText = (item.type || "Media") + " · " + formatBytes(item.size);

      document.getElementById("btn-play-vlc").style.display = "inline-flex";
      document.getElementById("btn-copy-url").style.display = "inline-flex";

      const m3uBtn = document.getElementById("current-m3u");
      m3uBtn.href = getM3uUrl(item);
      m3uBtn.download = item.name.replace(RegExp("[^\\w\\.\\-]", "g"), "_") + ".m3u";
      m3uBtn.style.display = "inline-flex";

      const dl = document.getElementById("current-download");
      dl.href = streamUrl;
      dl.style.display = "inline-flex";

      renderCatalog();
    }

    document.getElementById("player-video").addEventListener("error", () => {
      document.getElementById("codec-alert").style.display = "flex";
    });

    document.getElementById("player-video").addEventListener("ended", () => {
      if (activeIndex + 1 < playlist.length) {
        playMedia(activeIndex + 1, true);
      }
    });

    function openCurrentInExternalModal() {
      if (activeIndex >= 0 && activeIndex < playlist.length) {
        openItemInExternalModal(activeIndex);
      }
    }

    function openItemInExternalModal(idx) {
      if (idx < 0 || idx >= playlist.length) return;
      modalItem = playlist[idx];
      const fullUrl = getFullStreamUrl(modalItem);
      const m3uUrl = getM3uUrl(modalItem);

      document.getElementById("modal-track-name").innerText = modalItem.name;
      document.getElementById("modal-url-input").value = fullUrl;
      document.getElementById("modal-m3u-link").href = m3uUrl;
      document.getElementById("modal-m3u-link").download = modalItem.name.replace(RegExp("[^\\w\\.\\-]", "g"), "_") + ".m3u";

      const isAndroid = /Android/i.test(navigator.userAgent);
      const androidBtn = document.getElementById("modal-android-btn");
      if (androidBtn) {
        androidBtn.style.display = isAndroid ? "inline-flex" : "none";
      }

      document.getElementById("external-modal").style.display = "flex";
    }

    function closeExternalModal() {
      document.getElementById("external-modal").style.display = "none";
    }

    document.getElementById("external-modal").addEventListener("click", (e) => {
      if (e.target.id === "external-modal") {
        closeExternalModal();
      }
    });

    function launchVlcProtocol() {
      if (!modalItem) return;
      const fullUrl = getFullStreamUrl(modalItem);
      const isAndroid = /Android/i.test(navigator.userAgent);

      if (isAndroid) {
        const cleanUrl = fullUrl.replace(RegExp("^https?://"), "");
        const scheme = fullUrl.startsWith("https") ? "https" : "http";
        const mimeType = (modalItem.type === "audio") ? "audio/*" : "video/*";
        const vlcIntent = "intent://" + cleanUrl + "#Intent;scheme=" + scheme + ";type=" + mimeType + ";package=org.videolan.vlc;end";
        window.location.href = vlcIntent;
        setTimeout(() => {
          window.location.href = "vlc://" + fullUrl;
        }, 1200);
      } else {
        window.location.href = "vlc://" + fullUrl;
      }
    }

    function launchAndroidPlayerIntent() {
      if (!modalItem) return;
      const fullUrl = getFullStreamUrl(modalItem);
      const cleanUrl = fullUrl.replace(RegExp("^https?://"), "");
      const scheme = fullUrl.startsWith("https") ? "https" : "http";
      const mimeType = (modalItem.type === "audio") ? "audio/*" : "video/*";
      const genericIntent = "intent://" + cleanUrl + "#Intent;scheme=" + scheme + ";type=" + mimeType + ";end";
      window.location.href = genericIntent;
    }

    function copyModalUrl() {
      const input = document.getElementById("modal-url-input");
      input.select();
      navigator.clipboard.writeText(input.value).then(() => {
        const textSpan = document.getElementById("modal-copy-text");
        textSpan.innerText = "Copied!";
        setTimeout(() => { textSpan.innerText = "Copy"; }, 2000);
      }).catch(() => {
        document.execCommand("copy");
      });
    }

    function copyCurrentStreamUrl() {
      if (activeIndex < 0 || activeIndex >= playlist.length) return;
      const item = playlist[activeIndex];
      const fullUrl = getFullStreamUrl(item);
      navigator.clipboard.writeText(fullUrl).then(() => {
        const textSpan = document.getElementById("copy-btn-text");
        textSpan.innerText = "Copied!";
        setTimeout(() => { textSpan.innerText = "Copy URL"; }, 2000);
      });
    }

    if (requiredPin) {
      if (sessionStorage.getItem("speedshare_stream_pin")) {
        unlockStream();
      }
    } else {
      loadCatalog();
    }
  </script>
</body>
</html>''';
  }

  static String _escape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

