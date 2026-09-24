/**
 * Telegram → Browser Launcher (Firefox + Chromium, cross-platform)
 * Buka link di browser user → Tampermonkey autopilot → code ke Telegram
 * 
 * Install: npm install grammy
 * Run: node browser-launcher.js
 */

'use strict';

const { Bot } = require('grammy');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

// ============================================================================
// CONFIG
// ============================================================================
const CONFIG = {
    TG_BOT_TOKEN: '8242245230:AAGVCrXRAoluppyxExrlS5U226H_a1hsDCs',
    TG_CHAT_ID: '6105537437',

    // Set manual kalo auto-detect gagal:
    //   Windows Store FF: 'C:/Users/ASUS/AppData/Local/Microsoft/WindowsApps/firefox.exe'
    //   Linux Mint FF:    '/usr/bin/firefox'
    //   Linux Mint Chrom: '/usr/bin/chromium'
    //   Snap Chrom:       '/snap/bin/chromium'
    BROWSER_PATH: '',

    // Auto-detect browser: 'firefox' | 'chromium' | 'auto'
    BROWSER_TYPE: 'auto',

    // true = reuse window yang jalan, false = window baru
    USE_EXISTING_BROWSER: true,

    DEBUG: true,
};

// ============================================================================
// LOGGER
// ============================================================================
function log(...a) {
    if (!CONFIG.DEBUG) return;
    const ts = new Date().toISOString().slice(11, 19);
    console.log(`[${ts}]`, ...a);
}

// ============================================================================
// BROWSER DETECTION
// ============================================================================
function findBrowser() {
    const isWin = process.platform === 'win32';
    const isMac = process.platform === 'darwin';
    const isLinux = !isWin && !isMac;

    const localAppData = process.env.LOCALAPPDATA || '';

    // Kandidat path per OS
    const firefoxCandidates = isWin ? [
        localAppData ? path.join(localAppData, 'Microsoft', 'WindowsApps', 'firefox.exe') : '',
        'C:/Program Files/Mozilla Firefox/firefox.exe',
        'C:/Program Files (x86)/Mozilla Firefox/firefox.exe',
    ] : isMac ? [
        '/Applications/Firefox.app/Contents/MacOS/firefox',
    ] : [
        '/usr/bin/firefox',
        '/usr/lib/firefox/firefox',
        '/snap/bin/firefox',
        '/usr/local/bin/firefox',
    ];

    const chromiumCandidates = isWin ? [
        localAppData ? path.join(localAppData, 'Google', 'Chrome', 'Application', 'chrome.exe') : '',
        'C:/Program Files/Google/Chrome/Application/chrome.exe',
        'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    ] : isMac ? [
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        '/Applications/Chromium.app/Contents/MacOS/Chromium',
    ] : [
        '/usr/bin/chromium',
        '/usr/bin/chromium-browser',
        '/usr/bin/google-chrome',
        '/usr/bin/google-chrome-stable',
        '/snap/bin/chromium',
        '/var/lib/flatpak/exports/bin/org.chromium.Chromium',
        '/var/lib/flatpak/exports/bin/com.google.Chrome',
    ];

    const check = (p) => {
        if (!p) return false;
        if (fs.existsSync(p)) return true;
        // Windows: fallback readdir buat reparse point
        if (isWin) {
            try {
                const dir = path.dirname(p);
                const base = path.basename(p);
                return fs.readdirSync(dir).includes(base);
            } catch (e) { return false; }
        }
        return false;
    };

    console.log('[debug] cek browser path:');

    if (CONFIG.BROWSER_PATH) {
        console.log(`  ~ ${CONFIG.BROWSER_PATH} (dari CONFIG)`);
        return { path: CONFIG.BROWSER_PATH, type: CONFIG.BROWSER_TYPE === 'auto' ? 'firefox' : CONFIG.BROWSER_TYPE };
    }

    // Cek sesuai BROWSER_TYPE
    if (CONFIG.BROWSER_TYPE === 'firefox' || CONFIG.BROWSER_TYPE === 'auto') {
        for (const p of firefoxCandidates) {
            if (check(p)) {
                console.log(`  ✓ ${p} (Firefox)`);
                return { path: p, type: 'firefox' };
            }
        }
    }
    if (CONFIG.BROWSER_TYPE === 'chromium' || CONFIG.BROWSER_TYPE === 'auto') {
        for (const p of chromiumCandidates) {
            if (check(p)) {
                console.log(`  ✓ ${p} (Chromium)`);
                return { path: p, type: 'chromium' };
            }
        }
    }

    console.log('  ✗ Tidak ada browser yang ketemu');
    return null;
}

const BROWSER = findBrowser();
const BROWSER_PATH = BROWSER ? BROWSER.path : null;
const BROWSER_TYPE = BROWSER ? BROWSER.type : 'firefox';

// ============================================================================
// TELEGRAM
// ============================================================================
const bot = new Bot(CONFIG.TG_BOT_TOKEN);

function send(text, replyMarkup) {
    const opts = {
        parse_mode: 'HTML',
        link_preview_options: { is_disabled: true },
    };
    if (replyMarkup) opts.reply_markup = replyMarkup;

    return bot.api.sendMessage(CONFIG.TG_CHAT_ID, text, opts)
        .catch(err => log('send err:', err.message));
}

function esc(s) {
    return String(s || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .slice(0, 800);
}

// ============================================================================
// BROWSER LAUNCHER
// ============================================================================
function buildArgs(url) {
    if (BROWSER_TYPE === 'chromium') {
        // Chromium: URL aja = new tab di window yang jalan
        // --new-window = window baru
        return CONFIG.USE_EXISTING_BROWSER
            ? [url]
            : ['--new-window', url];
    }
    // Firefox
    return CONFIG.USE_EXISTING_BROWSER
        ? ['--new-tab', url]
        : ['-new-window', url];
}

function openInBrowser(url) {
    if (!BROWSER_PATH) {
        throw new Error('Browser path tidak ketemu. Set CONFIG.BROWSER_PATH manual.');
    }

    log(`🌐 opening in ${BROWSER_TYPE}:`, url.slice(0, 100));

    const args = buildArgs(url);
    log('   args:', args.join(' '));

    const child = spawn(BROWSER_PATH, args, {
        detached: true,
        stdio: 'ignore',
        windowsHide: true,
    });

    child.on('error', (err) => {
        log('⚠️ spawn err:', err.message);
    });

    child.unref();
    log('✓ spawn OK, PID:', child.pid);
    return true;
}

// ============================================================================
// MESSAGE HANDLER
// ============================================================================
bot.on('message:text', async (ctx) => {
    const msg = ctx.message;
    if (String(msg.chat.id) !== String(CONFIG.TG_CHAT_ID)) return;

    const text = msg.text || '';
    log('📥 msg:', text.slice(0, 100));

    if (text === '/start') {
        return send(
            `<b>🌐 Bypass Launcher</b>\n\n` +
            `Kirim link, gue buka di browser lu.\n` +
            `Tampermonkey autopilot → code masuk ke sini.\n\n` +
            `<b>Browser:</b> ${BROWSER_TYPE}\n` +
            `<b>Path:</b>\n<code>${esc(BROWSER_PATH || 'NOT FOUND')}</code>\n` +
            `<b>Host:</b> ${esc(os.hostname())}\n` +
            `<b>OS:</b> ${esc(process.platform)}`
        );
    }

    if (text === '/status') {
        return send(
            `<b>📊 Status</b>\n` +
            `Browser: ${BROWSER_TYPE}\n` +
            `Path: <code>${esc(BROWSER_PATH || 'NOT FOUND')}</code>\n` +
            `Mode: ${CONFIG.USE_EXISTING_BROWSER ? 'reuse window' : 'new window'}\n` +
            `Host: ${esc(os.hostname())}\n` +
            `OS: ${esc(process.platform)} ${esc(os.release())}`
        );
    }

    const urlMatch = text.match(/https?:\/\/[^\s]+/);
    if (!urlMatch) return send('⚠️ Kirim link yang valid.');

    const url = urlMatch[0];

    try {
        openInBrowser(url);
        await send(
            `✅ <b>Dibuka di ${BROWSER_TYPE}</b>\n` +
            `<code>${esc(url.slice(0, 120))}...</code>\n\n` +
            `⏳ Tunggu code...`
        );
    } catch (e) {
        log('launch err:', e.message);
        await send(`❌ <b>Gagal</b>\n<code>${esc(e.message)}</code>`);
    }
});

// ============================================================================
// STARTUP
// ============================================================================
console.log('');
console.log('╔══════════════════════════════════════════╗');
console.log('║   Universal Bypass Launcher              ║');
console.log('╚══════════════════════════════════════════╝');
console.log('');

if (!BROWSER_PATH) {
    console.error('⚠️  Browser path TIDAK KETEMU.');
    console.error('    Set manual di CONFIG.BROWSER_PATH.');
    console.error('    Contoh Linux Mint:');
    console.error('      Firefox:  /usr/bin/firefox');
    console.error('      Chromium: /usr/bin/chromium');
    console.error('      Snap:     /snap/bin/chromium');
    console.error('');
} else {
    console.log(`✓ Browser: ${BROWSER_TYPE} → ${BROWSER_PATH}`);
    console.log('');
}

bot.start({
    onStart: (info) => {
        log('Bot started as @' + info.username);
        log('Chat ID:', CONFIG.TG_CHAT_ID);
        log('Waiting for links...');
        console.log('');
    },
});

process.on('SIGINT', async () => {
    log('shutting down...');
    try { await bot.stop(); } catch (e) {}
    process.exit(0);
});

process.on('unhandledRejection', (e) => {
    log('unhandled:', e.message || e);
});
