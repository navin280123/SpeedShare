// WebPortalHtml.dart
// Provides self-contained, responsive, offline-ready HTML5 web portals
// served by SpeedShare's embedded Dart HTTP servers.
// No external CDNs or internet connection required.

import 'dart:convert';

class WebPortalHtml {
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

  /// SVG Icons
  static const String _iconLogo = '''
    <svg viewBox="0 0 24 24"><path d="M12 2L4.5 20.29l.71.71L12 18l6.79 3 .71-.71z"/></svg>
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

  /// Generates the HTML for the Web Media Player.
  static String getStreamWebHtml({
    required String hostDeviceName,
    String? accessCode,
  }) {
    final hasPin = accessCode != null && accessCode.isNotEmpty;

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
      background: rgba(255, 255, 255, 0.03);
      border-top: 1px solid var(--card-border);
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
    ${hasPin ? '''
    <div id="pin-section" class="card pin-box">
      <h3>Stream Access PIN</h3>
      <p style="color: var(--text-muted); font-size: 13px; margin-top: 8px;">
        Enter the 4-digit PIN shown on the stream host
      </p>
      <input type="text" id="pin-input" class="pin-input" maxlength="6" placeholder="PIN" autofocus>
      <button onclick="unlockStream()" class="btn btn-accent" style="width: 100%;">Connect to Stream</button>
      <div id="pin-error" style="color: #ff5252; font-size: 13px; margin-top: 10px; display: none;">Invalid PIN. Please try again.</div>
    </div>
    ''' : ''}

    <div id="stream-section" style="${hasPin ? 'display: none;' : ''}">
      <div class="player-container">
        <video id="player-video" class="video-view" controls playsinline></video>
        <div class="now-playing-banner">
          <div>
            <div id="current-title" style="font-weight: 600; font-size: 15px;">Select a track to play</div>
            <div id="current-meta" style="font-size: 12px; color: var(--text-muted); margin-top: 2px;">Direct stream from host</div>
          </div>
          <a id="current-download" href="#" class="btn btn-sm btn-outline" download style="display: none;">
            $_iconDownload
            <span>Save</span>
          </a>
        </div>
      </div>

      <div class="card">
        <h3 style="font-size: 16px; margin-bottom: 14px;">Media Catalog</h3>
        <div id="catalog-list">
          <div style="text-align: center; padding: 30px; color: var(--text-muted);">Loading playlist...</div>
        </div>
      </div>
    </div>
  </main>

  <footer class="footer">
    SpeedShare Local Wi-Fi Media Stream · Lossless real-time playback
  </footer>

  <script>
    let playlist = [];
    let activeIndex = -1;
    const requiredPin = "${accessCode ?? ''}";

    function getPin() {
      return sessionStorage.getItem('speedshare_stream_pin') || requiredPin;
    }

    function formatBytes(bytes) {
      if (!bytes || bytes === 0) return '';
      const k = 1024;
      const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
      const i = Math.floor(Math.log(bytes) / Math.log(k));
      return (bytes / Math.pow(k, i)).toFixed(1) + ' ' + sizes[i];
    }

    function unlockStream() {
      const pin = document.getElementById('pin-input').value.trim();
      sessionStorage.setItem('speedshare_stream_pin', pin);
      loadCatalog((success) => {
        if (success) {
          document.getElementById('pin-section').style.display = 'none';
          document.getElementById('stream-section').style.display = 'block';
        } else {
          document.getElementById('pin-error').style.display = 'block';
        }
      });
    }

    async function loadCatalog(callback) {
      const pin = getPin();
      const url = '/api/stream/catalog' + (pin ? '?code=' + encodeURIComponent(pin) : '');
      try {
        const resp = await fetch(url);
        if (!resp.ok) {
          if (callback) callback(false);
          return;
        }
        const data = await resp.json();
        playlist = data.items || [];
        renderCatalog();
        if (playlist.length > 0) {
          playMedia(0, false);
        }
        if (callback) callback(true);
      } catch (e) {
        if (callback) callback(false);
      }
    }

    function renderCatalog() {
      const list = document.getElementById('catalog-list');
      if (!playlist.length) {
        list.innerHTML = '<div style="text-align:center; padding: 20px; color: var(--text-muted);">No media items shared</div>';
        return;
      }
      list.innerHTML = playlist.map((item, idx) => `
        <div class="media-card \${idx === activeIndex ? 'active' : ''}" onclick="playMedia(\${idx}, true)">
          <div class="media-info">
            <div class="media-icon">$_iconPlay</div>
            <div>
              <div class="media-name">\${item.name}</div>
              <div class="media-meta">\${item.type || 'Media'} · \${formatBytes(item.size)}</div>
            </div>
          </div>
          <button class="btn btn-sm btn-outline" style="border: none;">
            $_iconPlay
          </button>
        </div>
      `).join('');
    }

    function playMedia(index, autoPlay) {
      if (index < 0 || index >= playlist.length) return;
      activeIndex = index;
      const item = playlist[index];
      const pin = getPin();
      const streamUrl = '/api/stream/media?id=' + encodeURIComponent(item.id) + (pin ? '&code=' + encodeURIComponent(pin) : '');

      const player = document.getElementById('player-video');
      player.src = streamUrl;
      if (autoPlay) {
        player.play().catch(() => {});
      }

      document.getElementById('current-title').innerText = item.name;
      document.getElementById('current-meta').innerText = (item.type || 'Media') + ' · ' + formatBytes(item.size);

      const dl = document.getElementById('current-download');
      dl.href = streamUrl;
      dl.style.display = 'inline-flex';

      renderCatalog();
    }

    // Auto-advance to next track when finished
    document.getElementById('player-video').addEventListener('ended', () => {
      if (activeIndex + 1 < playlist.length) {
        playMedia(activeIndex + 1, true);
      }
    });

    // Auto-init
    if (requiredPin) {
      if (sessionStorage.getItem('speedshare_stream_pin')) {
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
