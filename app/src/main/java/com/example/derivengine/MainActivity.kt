package com.example.derivengine

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        webView = WebView(this)
        setContentView(webView)

        val settings: WebSettings = webView.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.allowFileAccess = true
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW

        webView.webChromeClient = WebChromeClient()
        webView.webViewClient = WebViewClient()

        // Load complete dashboard with tab navigation
        webView.loadDataWithBaseURL("http://10.0.2.2:8000", getEmbeddedDashboardHtml(), "text/html", "UTF-8", null)
    }

    private fun getEmbeddedDashboardHtml(): String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <title>Deriv Engine</title>
            <style>
                :root {
                    --bg: #0f172a;
                    --card: #1e293b;
                    --text: #f8fafc;
                    --accent: #38bdf8;
                    --green: #22c55e;
                    --red: #ef4444;
                    --muted: #64748b;
                }
                * { box-sizing: border-box; }
                body {
                    font-family: system-ui, -apple-system, sans-serif;
                    background: var(--bg);
                    color: var(--text);
                    margin: 0;
                    padding: 0 0 65px 0;
                }
                .app-header {
                    background: #090d16;
                    padding: 16px;
                    border-bottom: 1px solid rgba(255,255,255,0.08);
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    position: sticky;
                    top: 0;
                    z-index: 100;
                }
                .brand { font-size: 18px; font-weight: 800; color: var(--accent); }
                .tab-content { display: none; padding: 16px; }
                .tab-content.active { display: block; }

                /* Dashboard */
                .status-card {
                    background: var(--card);
                    padding: 14px;
                    border-radius: 12px;
                    margin-bottom: 14px;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                }
                .btn {
                    padding: 10px 18px;
                    border-radius: 8px;
                    border: none;
                    font-weight: bold;
                    color: white;
                    background: var(--green);
                    cursor: pointer;
                }
                .btn.stop { background: var(--red); }
                .grid {
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    gap: 10px;
                    margin-bottom: 14px;
                }
                .card {
                    background: var(--card);
                    padding: 12px;
                    border-radius: 12px;
                    border: 1px solid rgba(255,255,255,0.05);
                }
                .card-title { font-size: 10px; color: #94a3b8; font-weight: bold; text-transform: uppercase; }
                .card-val { font-size: 18px; font-weight: bold; margin-top: 4px; color: var(--accent); }
                .card-sub { font-size: 10px; color: var(--muted); margin-top: 2px; }

                .tick-box {
                    background: var(--card);
                    padding: 14px;
                    border-radius: 12px;
                    margin-bottom: 14px;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                }
                .digit-circle {
                    width: 44px;
                    height: 44px;
                    border-radius: 50%;
                    background: var(--accent);
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-size: 20px;
                    font-weight: bold;
                    color: black;
                }
                .terminal {
                    background: #020617;
                    padding: 10px;
                    border-radius: 10px;
                    font-family: monospace;
                    font-size: 11px;
                    height: 160px;
                    overflow-y: auto;
                    border: 1px solid rgba(255,255,255,0.08);
                }
                .log-item { margin-bottom: 4px; }
                .log-time { color: var(--muted); }
                .log-info { color: #f8fafc; }
                .log-success { color: var(--green); }
                .log-error { color: var(--red); }

                /* Form Controls */
                .form-group { margin-bottom: 12px; }
                label { display: block; font-size: 12px; color: #94a3b8; margin-bottom: 4px; font-weight: 600; }
                input, select {
                    width: 100%;
                    padding: 10px;
                    border-radius: 8px;
                    border: 1px solid rgba(255,255,255,0.1);
                    background: var(--card);
                    color: white;
                    font-size: 14px;
                }

                /* Navigation Bar */
                .nav-bar {
                    position: fixed;
                    bottom: 0;
                    left: 0;
                    right: 0;
                    height: 60px;
                    background: #090d16;
                    border-top: 1px solid rgba(255,255,255,0.08);
                    display: flex;
                    justify-content: space-around;
                    align-items: center;
                    z-index: 100;
                }
                .nav-item {
                    color: var(--muted);
                    text-decoration: none;
                    font-size: 11px;
                    font-weight: bold;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    cursor: pointer;
                }
                .nav-item.active { color: var(--accent); }
                .nav-icon { font-size: 18px; margin-bottom: 2px; }
            </style>
        </head>
        <body>
            <div class="app-header">
                <div class="brand">Deriv Engine</div>
                <div id="status-badge" style="font-size:12px; font-weight:bold; color:var(--muted)">IDLE</div>
            </div>

            <!-- TAB 1: DASHBOARD -->
            <div id="tab-dashboard" class="tab-content active">
                <div class="status-card">
                    <div>
                        <div style="font-size:14px; font-weight:bold;">Bot Controller</div>
                        <small id="status-desc" style="color:var(--muted)">Strategy Engine</small>
                    </div>
                    <button id="toggle-btn" class="btn" onclick="toggleBot()">Start Bot</button>
                </div>

                <div class="tick-box">
                    <div>
                        <div class="card-title">Live Tick Quote</div>
                        <div id="tick-quote" class="card-val" style="font-size:22px;">---.--</div>
                    </div>
                    <div class="digit-circle" id="last-digit">-</div>
                </div>

                <div class="grid">
                    <div class="card">
                        <div class="card-title">Total Profit</div>
                        <div class="card-val" id="total-profit">${'$'}0.00</div>
                        <div class="card-sub" id="profit-target">Target: ${'$'}500.00</div>
                    </div>
                    <div class="card">
                        <div class="card-title">Win Rate</div>
                        <div class="card-val" id="win-rate">0.0%</div>
                        <div class="card-sub" id="runs-count">Wins: 0 / Runs: 0</div>
                    </div>
                    <div class="card">
                        <div class="card-title">Current Stake</div>
                        <div class="card-val" id="current-stake">${'$'}30.00</div>
                        <div class="card-sub">Base: ${'$'}30.00</div>
                    </div>
                    <div class="card">
                        <div class="card-title">Loss Streak</div>
                        <div class="card-val" id="loss-streak" style="color:var(--red);">0 / 4</div>
                        <div class="card-sub">Max Threshold</div>
                    </div>
                </div>

                <div style="font-size:11px; font-weight:bold; margin-bottom:6px; color:#94a3b8;">EXECUTION LOGS</div>
                <div class="terminal" id="logs-container">
                    <div class="log-item"><span class="log-time">[System]</span> Mobile Dashboard Ready.</div>
                </div>
            </div>

            <!-- TAB 2: SETTINGS -->
            <div id="tab-settings" class="tab-content">
                <h3 style="margin-top:0;">Strategy Settings</h3>
                <div class="form-group">
                    <label>Deriv API Token</label>
                    <input type="password" id="cfg-token" value="pat_63d70ebd7948f94b89f50cb0fced0450e011f4361213ae11838f190bebb618ab">
                </div>
                <div class="form-group">
                    <label>Base Stake ($)</label>
                    <input type="number" id="cfg-base" value="30">
                </div>
                <div class="form-group">
                    <label>Max Stake ($)</label>
                    <input type="number" id="cfg-max" value="1000">
                </div>
                <div class="form-group">
                    <label>Martingale Multiplier</label>
                    <input type="number" step="0.1" id="cfg-mart" value="2.0">
                </div>
                <div class="form-group">
                    <label>Take Profit ($)</label>
                    <input type="number" id="cfg-tp" value="500">
                </div>
                <div class="form-group">
                    <label>Stop Loss ($)</label>
                    <input type="number" id="cfg-sl" value="500">
                </div>
                <button class="btn" style="width:100%; margin-top:10px;" onclick="saveConfig()">Save Settings</button>
            </div>

            <!-- TAB 3: TRANSACTIONS -->
            <div id="tab-history" class="tab-content">
                <h3 style="margin-top:0;">Transactions</h3>
                <div id="tx-list" style="font-size:12px; color:var(--muted);">
                    Loading statement history from Deriv account...
                </div>
            </div>

            <!-- TAB 4: MANUAL TRADE -->
            <div id="tab-manual" class="tab-content">
                <h3 style="margin-top:0;">Manual Trade Execution</h3>
                <div class="form-group">
                    <label>Market Symbol</label>
                    <select id="m-symbol">
                        <option value="R_100">Volatility 100 Index (R_100)</option>
                        <option value="R_75">Volatility 75 Index (R_75)</option>
                        <option value="R_50">Volatility 50 Index (R_50)</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>Contract Type</label>
                    <select id="m-type">
                        <option value="DIGITUNDER">DIGIT UNDER</option>
                        <option value="DIGITOVER">DIGIT OVER</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>Stake ($)</label>
                    <input type="number" id="m-amount" value="10">
                </div>
                <button class="btn" style="width:100%; margin-top:10px; background:var(--accent); color:black;" onclick="executeManual()">Place Contract</button>
                <div id="manual-res" style="margin-top:10px; font-size:12px; color:var(--green);"></div>
            </div>

            <!-- BOTTOM NAVIGATION BAR -->
            <div class="nav-bar">
                <div class="nav-item active" onclick="switchTab('dashboard', this)">
                    <span class="nav-icon">📊</span>
                    <span>Dashboard</span>
                </div>
                <div class="nav-item" onclick="switchTab('settings', this)">
                    <span class="nav-icon">⚙️</span>
                    <span>Settings</span>
                </div>
                <div class="nav-item" onclick="switchTab('history', this)">
                    <span class="nav-icon">📜</span>
                    <span>History</span>
                </div>
                <div class="nav-item" onclick="switchTab('manual', this)">
                    <span class="nav-icon">⚡</span>
                    <span>Manual</span>
                </div>
            </div>

            <script>
                const HOST = "10.0.2.2:8000";
                let isRunning = false;
                let ws;

                function switchTab(tabId, el) {
                    document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
                    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
                    document.getElementById('tab-' + tabId).classList.add('active');
                    el.classList.add('active');
                    if (tabId === 'history') loadHistory();
                }

                function connectWS() {
                    ws = new WebSocket("ws://" + HOST + "/ws/live");
                    ws.onopen = () => {
                        addLog("info", "Connected to Deriv Engine Backend.");
                        fetchStatus();
                    };
                    ws.onmessage = (evt) => {
                        const msg = JSON.parse(evt.data);
                        if (msg.type === "init") {
                            updateStatus(msg.data.status);
                            if (msg.data.logs) {
                                msg.data.logs.forEach(l => addLog(l.level, l.message, l.timestamp));
                            }
                        } else if (msg.type === "status") {
                            updateStatus(msg.data);
                        } else if (msg.type === "tick") {
                            document.getElementById("tick-quote").innerText = msg.data.quote.toFixed(2);
                            document.getElementById("last-digit").innerText = msg.data.last_digit;
                        } else if (msg.type === "log") {
                            addLog(msg.data.level, msg.data.message, msg.data.timestamp);
                        }
                    };
                    ws.onclose = () => {
                        document.getElementById("status-badge").innerText = "DISCONNECTED";
                        setTimeout(connectWS, 3000);
                    };
                }

                function fetchStatus() {
                    fetch("http://" + HOST + "/api/bot/status")
                        .then(r => r.json())
                        .then(data => updateStatus(data))
                        .catch(err => console.error(err));
                }

                function updateStatus(status) {
                    isRunning = status.is_running;
                    document.getElementById("status-badge").innerText = isRunning ? "BOT ACTIVE" : "IDLE";
                    document.getElementById("status-badge").style.color = isRunning ? "#22c55e" : "#64748b";
                    
                    const btn = document.getElementById("toggle-btn");
                    btn.innerText = isRunning ? "Stop Bot" : "Start Bot";
                    btn.className = isRunning ? "btn stop" : "btn";

                    document.getElementById("total-profit").innerText = "${'$'}" + status.total_profit.toFixed(2);
                    document.getElementById("total-profit").style.color = status.total_profit >= 0 ? "#22c55e" : "#ef4444";
                    document.getElementById("win-rate").innerText = status.win_rate.toFixed(1) + "%";
                    document.getElementById("runs-count").innerText = "Wins: " + status.total_wins + " / Runs: " + status.runs;
                    document.getElementById("current-stake").innerText = "${'$'}" + status.current_stake.toFixed(2);
                    document.getElementById("loss-streak").innerText = status.loss_streak + " / " + status.config.max_loss_streak;
                    if (status.last_digit !== null) {
                        document.getElementById("last-digit").innerText = status.last_digit;
                    }
                    if (status.last_tick_quote !== null) {
                        document.getElementById("tick-quote").innerText = status.last_tick_quote.toFixed(2);
                    }
                }

                function toggleBot() {
                    const endpoint = isRunning ? "/api/bot/stop" : "/api/bot/start";
                    fetch("http://" + HOST + endpoint, { method: "POST" })
                        .then(r => r.json())
                        .then(() => fetchStatus())
                        .catch(err => addLog("error", "Failed: " + err));
                }

                function saveConfig() {
                    const body = {
                        api_token: document.getElementById("cfg-token").value,
                        base_stake: parseFloat(document.getElementById("cfg-base").value),
                        max_stake: parseFloat(document.getElementById("cfg-max").value),
                        martingale: parseFloat(document.getElementById("cfg-mart").value),
                        take_profit: parseFloat(document.getElementById("cfg-tp").value),
                        stop_loss: parseFloat(document.getElementById("cfg-sl").value)
                    };
                    fetch("http://" + HOST + "/api/config", {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify(body)
                    })
                    .then(r => r.json())
                    .then(() => alert("Settings saved!"))
                    .catch(err => alert("Error: " + err));
                }

                function loadHistory() {
                    fetch("http://" + HOST + "/api/history/statement")
                        .then(r => r.json())
                        .then(data => {
                            if (data.transactions && data.transactions.length > 0) {
                                let html = "";
                                data.transactions.forEach(t => {
                                    html += `<div style="padding:8px 0; border-bottom:1px solid rgba(255,255,255,0.05);">
                                        <strong>${'$'}{t.action || 'Trade'}</strong> - Profit: <span style="color:${'$'}{(t.profit||0)>=0?'#22c55e':'#ef4444'}">${'$'}${'$'}${'$'}{(t.profit||0).toFixed(2)}</span>
                                    </div>`;
                                });
                                document.getElementById("tx-list").innerHTML = html;
                            } else {
                                document.getElementById("tx-list").innerText = "No past transactions found.";
                            }
                        })
                        .catch(err => document.getElementById("tx-list").innerText = "Error loading history: " + err);
                }

                function executeManual() {
                    const body = {
                        symbol: document.getElementById("m-symbol").value,
                        contract_type: document.getElementById("m-type").value,
                        amount: parseFloat(document.getElementById("m-amount").value),
                        duration: 1,
                        duration_unit: "t"
                    };
                    fetch("http://" + HOST + "/api/trade/place", {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify(body)
                    })
                    .then(r => r.json())
                    .then(d => document.getElementById("manual-res").innerText = "Executed: " + JSON.stringify(d))
                    .catch(e => document.getElementById("manual-res").innerText = "Error: " + e);
                }

                function addLog(level, msg, time) {
                    const container = document.getElementById("logs-container");
                    const div = document.createElement("div");
                    div.className = "log-item";
                    const timestamp = time || new Date().toLocaleTimeString();
                    div.innerHTML = `<span class="log-time">[${'$'}{timestamp}]</span> <span class="log-${'$'}{level}">${'$'}{msg}</span>`;
                    container.appendChild(div);
                    container.scrollTop = container.scrollHeight;
                }

                connectWS();
            </script>
        </body>
        </html>
        """.trimIndent()
    }
}
