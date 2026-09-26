/**
 * Discord Bypass Bot — Android (Termux + Firefox)
 * Command: /bypass
 * 
 * Run: node discord-bot.js
 * 
 * Setup di Termux:
 *   pkg install nodejs-lts -y
 *   npm install discord.js
 */

'use strict';

const {
    Client, GatewayIntentBits, Events, REST, Routes,
    SlashCommandBuilder, EmbedBuilder,
} = require('discord.js');
const { exec } = require('child_process');
const http = require('http');
const os = require('os');

// ============================================================================
// CONFIG
// ============================================================================
const CONFIG = {
    // Discord
    DISCORD_TOKEN: 'MTU1MzAxNjc0MDU5NjY3ODY4Ng.G_tIeE.7GRXtIM9sqp1IBbvpiCMR9NM3R8iR851fEITSc',
    DISCORD_CLIENT_ID: '1553016740596678686',
    DISCORD_GUILD_ID: '1502890220973064312',
    DISCORD_CHANNEL_ID: '1503033238585606164',

    // Firefox Android package name
    FIREFOX_PACKAGE: 'org.mozilla.firefox',
    // Opsi lain:
    //   Firefox Beta: 'org.mozilla.firefox_beta'
    //   Firefox Nightly: 'org.mozilla.fenix'
    //   Kiwi: 'com.kiwibrowser.browser'
    //   Chrome: 'com.android.chrome'

    // Limits
    COOLDOWN_MS: 30_000,
    MAX_CONCURRENT: 3,           // Android lebih terbatas, kecilin
    TAB_TIMEOUT_MS: 120_000,     // 2 menit (Android lebih lambat)

    // Result server
    RESULT_SERVER_PORT: 5556,

    DEBUG: true,
};

function log(...a) {
    if (!CONFIG.DEBUG) return;
    const ts = new Date().toISOString().slice(11, 19);
    console.log(`[${ts}]`, ...a);
}

// ============================================================================
// STATE
// ============================================================================
const activeSessions = new Map();
const cooldowns = new Map();

function normalizeUrl(url) {
    try {
        const u = new URL(url);
        return u.origin + u.pathname + u.search;
    } catch (e) {
        return url;
    }
}

// ============================================================================
// DISCORD CLIENT
// ============================================================================
const client = new Client({ intents: [GatewayIntentBits.Guilds] });

// ============================================================================
// OPEN URL (Android)
// ============================================================================
function openInFirefox(url) {
    log('🌐 open in Firefox:', url.slice(0, 80));

    // Method 1: am start dengan package spesifik (Firefox)
    const cmd = `am start -a android.intent.action.VIEW -d "${url}" -n ${CONFIG.FIREFOX_PACKAGE}/org.mozilla.geckoview.BrowserActivity`;

    // Fallback method kalo -n gagal
    const fallbackCmd = `am start -a android.intent.action.VIEW -d "${url}"`;

    exec(cmd, (err) => {
        if (err) {
            log('⚠️ am start -n err:', err.message);
            log('   fallback: am start (default browser)');
            exec(fallbackCmd, (err2) => {
                if (err2) log('   ✗ fallback err:', err2.message);
                else log('   ✓ opened via default browser');
            });
        } else {
            log('✓ opened in Firefox');
        }
    });
}

// ============================================================================
// TERMUX NOTIFICATION (buat result)
// ============================================================================
function sendNotif(title, content) {
    const cmd = `termux-notification --title "${title.replace(/"/g, '\\"')}" --content "${content.replace(/"/g, '\\"')}"`;
    exec(cmd, (err) => {
        if (err) log('⚠️ notif err:', err.message);
    });
}

// ============================================================================
// RESULT SERVER
// ============================================================================
const resultServer = http.createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        return res.end();
    }

    if (req.method === 'POST' && req.url === '/result') {
        let body = '';
        req.on('data', (chunk) => { body += chunk; });
        req.on('end', async () => {
            let data = {};
            try { data = JSON.parse(body || '{}'); } catch (e) {}

            const { type, code, finalUrl, source, url } = data;
            const eventUrl = url || data.url || '';

            log('📩 result:', type, '|', (eventUrl || '').slice(0, 60));

            const session = findSessionByUrl(eventUrl);

            if (!session) {
                log('   ⚠️ no matching session');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ ok: false, error: 'no session' }));
                return;
            }

            log(`   ✓ matched: ${session.username}`);

            try {
                const embed = new EmbedBuilder()
                    .setColor(0x22c55e)
                    .setTimestamp()
                    .setFooter({ text: `Requested by ${session.username}`, iconURL: session.avatarUrl });

                if (type === 'code' && code) {
                    embed.setTitle('✅ Code Received')
                        .setDescription('Klik icon copy di pojok kanan code block, atau long-press di mobile.')
                        .addFields(
                            { name: '📋 Code (klik buat copy)', value: '```\n' + code + '\n```', inline: false },
                            { name: 'Source', value: String(source || '-').slice(0, 100), inline: true },
                        );
                } else if (type === 'url' && finalUrl) {
                    embed.setTitle('✅ Link Resolved')
                        .addFields(
                            { name: 'Final URL', value: finalUrl.slice(0, 200) },
                            { name: 'Source', value: String(source || '-').slice(0, 100), inline: true },
                        );
                }

                await session.interaction.editReply({
                    content: `<@${session.userId}> ✅ **Selesai!**`,
                    embeds: [embed],
                });
                log('   ✓ discord updated');

                // Android notification
                if (type === 'code' && code) {
                    sendNotif('Bypass selesai', `Code: ${code.slice(0, 50)}`);
                }
            } catch (e) {
                log('   ✗ edit err:', e.message);
            }

            if (session.timeoutHandle) clearTimeout(session.timeoutHandle);
            activeSessions.delete(session.normalizedUrl);

            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true }));
        });
    } else if (req.method === 'GET' && req.url === '/ping') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            ok: true,
            host: os.hostname(),
            activeSessions: activeSessions.size,
        }));
    } else {
        res.writeHead(404);
        res.end();
    }
});

function findSessionByUrl(eventUrl) {
    if (!eventUrl) {
        if (activeSessions.size === 1) return Array.from(activeSessions.values())[0];
        return null;
    }

    const normalized = normalizeUrl(eventUrl);

    if (activeSessions.has(normalized)) {
        return activeSessions.get(normalized);
    }

    for (const [sessUrl, session] of activeSessions.entries()) {
        const sessBase = sessUrl.split('?')[0];
        const eventBase = normalized.split('?')[0];

        if (eventBase.includes(sessBase) || sessBase.includes(eventBase)) {
            return session;
        }

        const sessD = sessUrl.match(/[?&]d=([^&]+)/);
        const eventD = normalized.match(/[?&]d=([^&]+)/);
        if (sessD && eventD && sessD[1] === eventD[1]) {
            return session;
        }
    }

    if (activeSessions.size === 1) {
        return Array.from(activeSessions.values())[0];
    }

    return null;
}

// ============================================================================
// SLASH COMMANDS
// ============================================================================
const commands = [
    new SlashCommandBuilder()
        .setName('bypass')
        .setDescription('Bypass link safelink (platorelay, lootlabs, dll)')
        .addStringOption(opt =>
            opt.setName('url')
                .setDescription('Link yang mau di-bypass')
                .setRequired(true)
        )
        .toJSON(),

    new SlashCommandBuilder()
        .setName('status')
        .setDescription('Cek status bot')
        .toJSON(),

    new SlashCommandBuilder()
        .setName('active')
        .setDescription('Liat tab yang lagi aktif')
        .toJSON(),
];

async function registerCommands() {
    const rest = new REST({ version: '10' }).setToken(CONFIG.DISCORD_TOKEN);
    try {
        await rest.put(
            Routes.applicationGuildCommands(CONFIG.DISCORD_CLIENT_ID, CONFIG.DISCORD_GUILD_ID),
            { body: commands }
        );
        log('✓ registered guild commands to', CONFIG.DISCORD_GUILD_ID);
    } catch (e) {
        log('register err:', e.message);
    }
}

// ============================================================================
// INTERACTION HANDLER
// ============================================================================
client.on(Events.InteractionCreate, async (interaction) => {
    if (!interaction.isChatInputCommand()) return;

    const userId = interaction.user.id;
    const username = interaction.user.username;
    const avatarUrl = interaction.user.displayAvatarURL({ size: 64 });

    // ---- /status ----
    if (interaction.commandName === 'status') {
        return interaction.reply({
            content:
                `**Bot Status**\n` +
                `• Platform: Android (Termux)\n` +
                `• Active: ${activeSessions.size}/${CONFIG.MAX_CONCURRENT}\n` +
                `• Host: \`${os.hostname()}\`\n` +
                `• Uptime: ${Math.floor(process.uptime())}s`,
            ephemeral: true,
        });
    }

    // ---- /active ----
    if (interaction.commandName === 'active') {
        if (activeSessions.size === 0) {
            return interaction.reply({ content: 'Ga ada tab aktif.', ephemeral: true });
        }
        const list = Array.from(activeSessions.values()).map((s, i) => {
            const age = Math.floor((Date.now() - s.startedAt) / 1000);
            return `${i + 1}. **${s.username}** (${age}s) — ${s.url.slice(0, 60)}...`;
        }).join('\n');
        return interaction.reply({ content: `**Active (${activeSessions.size})**\n${list}`, ephemeral: true });
    }

    // ---- /bypass ----
    if (interaction.commandName === 'bypass') {
        if (interaction.channelId !== CONFIG.DISCORD_CHANNEL_ID) {
            return interaction.reply({
                content: `❌ Command ini cuma bisa dipakai di <#${CONFIG.DISCORD_CHANNEL_ID}>.`,
                ephemeral: true,
            });
        }

        const url = interaction.options.getString('url');

        if (!/^https?:\/\//i.test(url)) {
            return interaction.reply({ content: '❌ URL harus mulai dengan http/https.', ephemeral: true });
        }

        const lastUse = cooldowns.get(userId) || 0;
        const now = Date.now();
        if (now - lastUse < CONFIG.COOLDOWN_MS) {
            const wait = Math.ceil((CONFIG.COOLDOWN_MS - (now - lastUse)) / 1000);
            return interaction.reply({ content: `⏳ Cooldown, tunggu ${wait}s lagi.`, ephemeral: true });
        }

        if (activeSessions.size >= CONFIG.MAX_CONCURRENT) {
            return interaction.reply({
                content: `❌ Max concurrent (${CONFIG.MAX_CONCURRENT}) tercapai.`,
                ephemeral: true,
            });
        }

        const normalized = normalizeUrl(url);

        if (activeSessions.has(normalized)) {
            return interaction.reply({
                content: '❌ URL ini lagi diproses user lain.',
                ephemeral: true,
            });
        }

        cooldowns.set(userId, now);

        await interaction.reply({
            content:
                `⏳ <@${userId}> **Processing...**\n` +
                `\`${url.slice(0, 100)}${url.length > 100 ? '...' : ''}\`\n\n` +
                `📱 Tab kebuka di Firefox — tunggu autopilot jalan.`,
        });

        const session = {
            userId,
            username,
            avatarUrl,
            url,
            normalizedUrl: normalized,
            interaction,
            channel: interaction.channel,
            startedAt: now,
            timeoutHandle: null,
        };

        session.timeoutHandle = setTimeout(async () => {
            if (activeSessions.has(normalized)) {
                activeSessions.delete(normalized);
                log(`⏱️ timeout: ${username}`);
                try {
                    await interaction.editReply({
                        content: `<@${userId}> ❌ **Timeout** — coba lagi.`,
                    });
                } catch (e) {}
            }
        }, CONFIG.TAB_TIMEOUT_MS);

        activeSessions.set(normalized, session);

        log(`📥 new session: ${username} (active: ${activeSessions.size})`);

        openInFirefox(url);
    }
});

// ============================================================================
// STARTUP
// ============================================================================
client.once(Events.ClientReady, (c) => {
    log('✓ Discord bot ready:', c.user.tag);
    log('  Platform:', process.platform, process.arch);
    log('  Firefox:', CONFIG.FIREFOX_PACKAGE);
    registerCommands();
});

resultServer.listen(CONFIG.RESULT_SERVER_PORT, '0.0.0.0', () => {
    log(`✓ Result server: http://0.0.0.0:${CONFIG.RESULT_SERVER_PORT}`);
    log(`  (Firefox Android akses via http://localhost:${CONFIG.RESULT_SERVER_PORT}/result)`);
});

console.log('');
console.log('╔══════════════════════════════════════════╗');
console.log('║   Discord Bypass Bot (Android + Firefox) ║');
console.log('╚══════════════════════════════════════════╝');
console.log('');
console.log(`✓ Platform: ${process.platform} ${process.arch}`);
console.log(`✓ Host: ${os.hostname()}`);
console.log(`✓ Firefox: ${CONFIG.FIREFOX_PACKAGE}`);
console.log(`✓ Channel: ${CONFIG.DISCORD_CHANNEL_ID}`);
console.log(`✓ Max concurrent: ${CONFIG.MAX_CONCURRENT}`);
console.log('');

client.login(CONFIG.DISCORD_TOKEN);
