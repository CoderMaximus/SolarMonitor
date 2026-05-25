#[macro_use]
extern crate lazy_static;

use axum::{routing::get, extract::Path, Router};          // FIX: added extract::Path
use chrono::{Local, Timelike};
use futures_util::SinkExt;
use hidapi::{HidApi, HidDevice};
use serde::{Serialize, Deserialize};
use std::collections::HashMap;
use std::fs;
use std::sync::{Arc, RwLock};
use std::thread;
use std::time::{Duration, Instant};
use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::protocol::Message;
use tower_http::cors::{CorsLayer, Any};

const DATA_DIR: &str = "./history";

#[derive(Serialize, Clone, Default, Debug)]
struct InverterState {
    label: String,
    serial: String,
    raw_data: Vec<String>,
    qed: String,
    qld: String,
    qbd: String,
    last_update: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct HistoryPoint {
    x: u32,
    pv: f32,
    load: f32,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct HistoryResponse {
    data: Vec<HistoryPoint>,
    qed: HashMap<String, f64>,
    qld: HashMap<String, f64>,
    qbd: HashMap<String, f64>,
}

type SharedState = Arc<RwLock<HashMap<u8, InverterState>>>;

lazy_static! {
    static ref HISTORY: Arc<RwLock<Vec<HistoryPoint>>> = Arc::new(RwLock::new(Vec::with_capacity(2880)));
}

fn save_history_to_file(state: &SharedState) {
    let date = Local::now().format("%Y-%m-%d").to_string();
    let path = format!("{}/{}.json", DATA_DIR, date);

    let snapshot = {
        let h = HISTORY.read().unwrap();
        let lock = state.read().unwrap();
        let mut qed_map = HashMap::new();
        let mut qld_map = HashMap::new();
        let mut qbd_map = HashMap::new();
        for inv in lock.values() {
            if !inv.serial.is_empty() {
                qed_map.insert(inv.serial.clone(), inv.qed.parse::<f64>().unwrap_or(0.0));
                qld_map.insert(inv.serial.clone(), inv.qld.parse::<f64>().unwrap_or(0.0));
                qbd_map.insert(inv.serial.clone(), inv.qbd.parse::<f64>().unwrap_or(0.0));
            }
        }
        HistoryResponse {
            data: h.clone(),
            qed: qed_map,
            qld: qld_map,
            qbd: qbd_map,
        }
    };

    let _ = fs::create_dir_all(DATA_DIR);
    if let Ok(json) = serde_json::to_string(&snapshot) {
        let _ = fs::write(&path, json);
    }
}

fn load_history_from_file() -> Option<HashMap<String, (f64, f64, f64)>> {
    let date = Local::now().format("%Y-%m-%d").to_string();
    let path = format!("{}/{}.json", DATA_DIR, date);

    let contents = fs::read_to_string(&path).ok()?;
    let response: HistoryResponse = serde_json::from_str(&contents).ok()?;

    let count = response.data.len();
    {
        let mut h_lock = HISTORY.write().unwrap();
        h_lock.clear();
        h_lock.extend(response.data);
    }

    let mut energy_cache: HashMap<String, (f64, f64, f64)> = HashMap::new();
    for serial in response.qed.keys() {
        let qed = response.qed.get(serial).copied().unwrap_or(0.0);
        let qld = response.qld.get(serial).copied().unwrap_or(0.0);
        let qbd = response.qbd.get(serial).copied().unwrap_or(0.0);
        energy_cache.insert(serial.clone(), (qed, qld, qbd));
    }

    println!("📂 Loaded {} history points from {}", count, path);
    Some(energy_cache)
}

#[tokio::main]
async fn main() {
    let state: SharedState = Arc::new(RwLock::new(HashMap::new()));
    let ws_state = Arc::clone(&state);
    let api_state = Arc::clone(&state);

    println!("🚀 PI30MAX Server Online | Logging every 30s | Ports: 3000/3001");

    let cached_energy = load_history_from_file();

    let master_s = Arc::clone(&state);
    let master_energy = cached_energy.as_ref().and_then(|m| m.get("92932207101268").cloned());
    thread::spawn(move || hardware_worker(master_s, "/dev/inverter_master", "Master", 1, master_energy));

    let slave_s = Arc::clone(&state);
    let slave_energy = cached_energy.as_ref().and_then(|m| m.get("92932207101267").cloned());
    thread::spawn(move || hardware_worker(slave_s, "/dev/inverter_slave", "Slave", 2, slave_energy));

    let history_state = Arc::clone(&state);
    thread::spawn(move || {
        let mut last_block = -1;
        loop {
            let now = Local::now();
            let total_seconds = (now.hour() * 3600 + now.minute() * 60 + now.second()) as i32;
            let current_block = total_seconds / 30;

            if current_block != last_block {
                let mut total_pv = 0.0;
                let mut total_load = 0.0;

                {
                    let lock = history_state.read().unwrap();
                    for inv in lock.values() {
                        let fields = &inv.raw_data;
                        if fields.len() >= 29 {
                            let v1 = fields[14].parse::<f32>().unwrap_or(0.0);
                            let a1 = fields[25].parse::<f32>().unwrap_or(0.0);
                            let v2 = fields[27].parse::<f32>().unwrap_or(0.0);
                            let a2 = fields[28].parse::<f32>().unwrap_or(0.0);
                            total_pv += (v1 * a1) + (v2 * a2);
                            total_load += fields[9].parse::<f32>().unwrap_or(0.0);
                        }
                    }
                }

                let mut h_lock = HISTORY.write().unwrap();

                if current_block == 0 && last_block != 0 {
                    h_lock.clear();
                    println!("🌙 History reset for the new day.");
                }

                h_lock.push(HistoryPoint {
                    x: (total_seconds as f32 / 60.0 * 10.0).round() as u32 / 10,
                    pv: total_pv,
                    load: total_load,
                });
                drop(h_lock);

                save_history_to_file(&history_state);

                last_block = current_block;
            }
            thread::sleep(Duration::from_secs(5));
        }
    });

    tokio::spawn(async move {
        let listener = TcpListener::bind("0.0.0.0:3001").await.unwrap();
        while let Ok((stream, _)) = listener.accept().await {
            let state_ref = Arc::clone(&ws_state);
            tokio::spawn(async move {
                if let Ok(mut ws_stream) = accept_async(stream).await {
                    loop {
                        let json = {
                            let lock = state_ref.read().unwrap();
                            serde_json::to_string(&*lock).unwrap()
                        };
                        if ws_stream.send(Message::Text(json.into())).await.is_err() { break; }
                        tokio::time::sleep(Duration::from_millis(1000)).await;
                    }
                }
            });
        }
    });

    // ═══════════════════════════════════════════════════
    // 4. REST API  — CHANGED: added /history/{date} route
    // ═══════════════════════════════════════════════════

    // Helper: build a HistoryResponse from the live in-memory state (for /history — today)
    let api_state_today = Arc::clone(&api_state);
    let today_handler = move || {
        let state_for_request = Arc::clone(&api_state_today);
        async move {
            let (data, qed_map, qld_map, qbd_map) = {
                let h = HISTORY.read().unwrap().clone();
                let lock = state_for_request.read().unwrap();
                let mut qed_map = HashMap::new();
                let mut qld_map = HashMap::new();
                let mut qbd_map = HashMap::new();
                for inv in lock.values() {
                    if !inv.serial.is_empty() {
                        qed_map.insert(inv.serial.clone(), inv.qed.parse::<f64>().unwrap_or(0.0));
                        qld_map.insert(inv.serial.clone(), inv.qld.parse::<f64>().unwrap_or(0.0));
                        qbd_map.insert(inv.serial.clone(), inv.qbd.parse::<f64>().unwrap_or(0.0));
                    }
                }
                (h, qed_map, qld_map, qbd_map)
            };
            axum::Json(HistoryResponse { data, qed: qed_map, qld: qld_map, qbd: qbd_map })
        }
    };

    // FIX: new handler — reads a historical JSON file by date
    let date_handler = |Path(date): Path<String>| async move {
        // Validate: must be exactly 10 chars and YYYY-MM-DD format
        let is_valid = date.len() == 10
            && date.chars().nth(4) == Some('-')
            && date.chars().nth(7) == Some('-')
            && date.chars().all(|c| c.is_ascii_digit() || c == '-');

        if !is_valid {
            return axum::response::Json(serde_json::json!({"error": "Invalid date format. Use YYYY-MM-DD"}));
        }

        let path = format!("{}/{}.json", DATA_DIR, date);
        match fs::read_to_string(&path) {
            Ok(contents) => {
                // File already stored as HistoryResponse JSON — return directly
                match serde_json::from_str::<serde_json::Value>(&contents) {
                    Ok(val) => axum::response::Json(val),
                    Err(_) => axum::response::Json(serde_json::json!({"error": "Corrupt history file"})),
                }
            }
            Err(_) => axum::response::Json(serde_json::json!({"error": "No history for this date", "data": [], "qed": {}, "qld": {}, "qbd": {}})),
        }
    };

    let earliest_handler = || async move {
        let _ = fs::create_dir_all(DATA_DIR);
        let mut earliest: Option<String> = None;
        if let Ok(entries) = fs::read_dir(DATA_DIR) {
            for entry in entries.flatten() {
                if let Some(name) = entry.file_name().to_str() {
                    if name.ends_with(".json") {
                        let date = name.trim_end_matches(".json").to_string();
                        if date.len() == 10 {
                            match &earliest {
                                None => earliest = Some(date),
                                Some(current) => {
                                    if date < *current {
                                        earliest = Some(date);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        axum::Json(serde_json::json!({"earliest": earliest}))
    };

    let app = Router::new()
        .route("/history", get(today_handler))
        .route("/history/{date}", get(date_handler))
        .route("/history/earliest", get(earliest_handler))         // FIX: new endpoint
        .layer(CorsLayer::new().allow_origin(Any).allow_methods(Any));

    let addr = "0.0.0.0:3000".parse::<std::net::SocketAddr>().unwrap();
    let listener = TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

fn hardware_worker(state: SharedState, path: &str, label: &str, id: u8, cached_energy: Option<(f64, f64, f64)>) {
    let api = HidApi::new().expect("HID Init Fail");
    let mut last_energy_query = Instant::now() - Duration::from_secs(600);

    let (mut cached_qed, mut cached_qld, mut cached_qbd) = if let Some((qed, qld, qbd)) = cached_energy {
        (format!("{:.2}", qed), format!("{:.2}", qld), format!("{:.2}", qbd))
    } else {
        (String::from("0.00"), String::from("0.00"), String::from("0.00"))
    };

    loop {
        if let Ok(dev) = api.open_path(&std::ffi::CString::new(path).unwrap()) {
            if let Some(fields) = query_and_parse_safe(&dev, &format!("QPGS{}", id)) {

                if last_energy_query.elapsed() > Duration::from_secs(300) {
                    let date = Local::now().format("%Y%m%d").to_string();

                    let qed_val = send_and_receive_raw(&dev, &format!("QED{}", date))
                        .and_then(|bytes| parse_energy_wh(&bytes))
                        .map(|wh| format!("{:.2}", wh / 1000.0));

                    let qld_val = send_and_receive_raw(&dev, &format!("QLD{}", date))
                        .and_then(|bytes| parse_energy_wh(&bytes))
                        .map(|wh| format!("{:.2}", wh / 1000.0));

                    if let (Some(qed), Some(qld)) = (qed_val, qld_val) {
                        let qed_num = qed.parse::<f64>().unwrap_or(0.0);
                        let qld_num = qld.parse::<f64>().unwrap_or(0.0);
                        cached_qed = qed;
                        cached_qld = qld;
                        cached_qbd = format!("{:.2}", qed_num - qld_num);
                        last_energy_query = Instant::now();
                    }
                }

                let serial = if fields.len() > 1 { fields[1].clone() } else { String::new() };

                state.write().unwrap().insert(
                    id,
                    InverterState {
                        label: label.to_string(),
                        serial,
                        raw_data: fields,
                        qed: cached_qed.clone(),
                        qld: cached_qld.clone(),
                        qbd: cached_qbd.clone(),
                        last_update: Local::now().format("%H:%M:%S").to_string(),
                    },
                );
            }
        }
        thread::sleep(Duration::from_millis(2000));
    }
}

fn parse_energy_wh(resp_bytes: &[u8]) -> Option<f64> {
    let start_pos = resp_bytes.iter().position(|&b| b == 0x28).map(|i| i + 1).unwrap_or(0);
    let end_pos = resp_bytes.iter().position(|&b| b == 0x0D).unwrap_or(resp_bytes.len());
    if end_pos <= start_pos { return None; }
    let clean_data = String::from_utf8_lossy(&resp_bytes[start_pos..end_pos]);
    let numeric_part: String = clean_data.chars().take_while(|c| c.is_numeric()).collect();
    if numeric_part.len() == 8 {
        numeric_part.parse::<f64>().ok()
    } else {
        None
    }
}

pub fn query_and_parse_safe(device: &HidDevice, command: &str) -> Option<Vec<String>> {
    let resp_bytes = send_and_receive_raw(device, command)?;
    let start_pos = resp_bytes.iter().position(|&b| b == 0x28).map(|i| i + 1).unwrap_or(0);
    let end_pos = resp_bytes.iter().position(|&b| b == 0x0D).unwrap_or(resp_bytes.len());
    let data_end = if end_pos > 2 { end_pos - 2 } else { end_pos };
    if data_end <= start_pos { return None; }
    let clean_str = String::from_utf8_lossy(&resp_bytes[start_pos..data_end]);
    Some(clean_str.split_whitespace().map(|s| s.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '.').collect()).collect())
}

fn send_and_receive_raw(device: &HidDevice, cmd: &str) -> Option<Vec<u8>> {
    let mut buf = [0u8; 64];
    while let Ok(len) = device.read_timeout(&mut buf, 10) { if len == 0 { break; } }
    let mut bytes = cmd.as_bytes().to_vec();
    let mut crc: u16 = 0;
    let table: [u16; 16] = [0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50a5, 0x60c6, 0x70e7, 0x8108, 0x9129, 0xa14a, 0xb16b, 0xc18c, 0xd1ad, 0xe1ce, 0xf1ef];
    for &b in &bytes {
        let mut da = ((crc >> 8) >> 4) as u8;
        crc <<= 4; da ^= b >> 4; crc ^= table[da as usize];
        da = ((crc >> 8) >> 4) as u8;
        crc <<= 4; da ^= b & 0x0f; crc ^= table[da as usize];
    }
    let (mut low, mut high) = ((crc & 0xff) as u8, (crc >> 8) as u8);
    if [0x28, 0x0d, 0x0a].contains(&low) { low += 1; }
    if [0x28, 0x0d, 0x0a].contains(&high) { high += 1; }
    bytes.push(high); bytes.push(low); bytes.push(0x0D);
    for chunk in bytes.chunks(8) {
        let mut block = [0u8; 9];
        block[1..chunk.len()+1].copy_from_slice(chunk);
        let _ = device.write(&block);
    }
    let mut resp = Vec::new();
    let start = Instant::now();
    while start.elapsed() < Duration::from_millis(1500) {
        let mut b = [0u8; 64];
        if let Ok(l) = device.read_timeout(&mut b, 50) {
            if l > 0 {
                resp.extend_from_slice(&b[..l]);
                if resp.contains(&0x0D) { break; }
            }
        }
    }
    if resp.is_empty() { None } else { Some(resp) }
}
