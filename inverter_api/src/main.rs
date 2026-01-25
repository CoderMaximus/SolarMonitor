#[macro_use]
extern crate lazy_static;

use axum::{routing::get, Router};
use chrono::{Local, Timelike};
use futures_util::SinkExt;
use hidapi::{HidApi, HidDevice};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{BufReader, BufWriter};
use std::path::Path;
use std::sync::{Arc, RwLock};
use std::thread;
use std::time::{Duration, Instant};
use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::protocol::Message;

#[derive(Serialize, Clone, Default, Debug)]
struct InverterState {
    label: String,
    raw_data: Vec<String>,
    qed: String,
    last_update: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct HistoryPoint {
    time: String,  // "HH:MM:SS" format
    pv: f32,
    load: f32,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
struct HistoryFile {
    data: Vec<HistoryPoint>,
    qed: HashMap<String, f64>, // Serial Number -> QED value (kWh), updated in place
}

type SharedState = Arc<RwLock<HashMap<u8, InverterState>>>;

lazy_static! {
    static ref HISTORY: Arc<RwLock<HistoryFile>> = Arc::new(RwLock::new(HistoryFile::default()));
}

fn load_today_history() -> HistoryFile {
    let today = Local::now().format("%Y-%m-%d").to_string();
    let file_path = Path::new("history").join(format!("{}.json", today));
    
    if file_path.exists() {
        if let Ok(file) = File::open(&file_path) {
            let reader = BufReader::new(file);
            if let Ok(data) = serde_json::from_reader::<_, HistoryFile>(reader) {
                println!("📂 Loaded {} history points from {}", data.data.len(), file_path.display());
                return data;
            }
        }
    }
    HistoryFile::default()
}

#[tokio::main]
async fn main() {
    let state: SharedState = Arc::new(RwLock::new(HashMap::new()));
    let ws_state = Arc::clone(&state);

    // Load existing history from today's file on startup
    {
        let mut h_lock = HISTORY.write().unwrap();
        *h_lock = load_today_history();
    }

    println!("🚀 PI30MAX Server Online | Logging every 5s | Ports: 3000/3001");

    // 1. Hardware Workers
    let master_s = Arc::clone(&state);
    thread::spawn(move || hardware_worker(master_s, "/dev/inverter_master", "Master", 1));

    let slave_s = Arc::clone(&state);
    thread::spawn(move || hardware_worker(slave_s, "/dev/inverter_slave", "Slave", 2));

    // 2. Background Recorder (Graph Data - every 5 seconds, saved to history/yyyy-mm-dd.json)
    let history_state = Arc::clone(&state);
    thread::spawn(move || {
        let mut last_block = -1;
        let mut current_date = Local::now().format("%Y-%m-%d").to_string();
        
        loop {
            let now = Local::now();
            let today = now.format("%Y-%m-%d").to_string();
            let time_str = now.format("%H:%M:%S").to_string();
            let total_seconds = (now.hour() * 3600 + now.minute() * 60 + now.second()) as i32;
            let current_block = total_seconds / 5; // 5-second blocks (0 to 17279)

            if current_block != last_block {
                let mut total_pv = 0.0;
                let mut total_load = 0.0;
                let mut qed_map: HashMap<String, f64> = HashMap::new();

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
                            
                            // Use serial number (field index 1) as key for QED
                            let serial = fields.get(1).cloned().unwrap_or_else(|| "unknown".to_string());
                            let qed_val = inv.qed.parse::<f64>().unwrap_or(0.0);
                            qed_map.insert(serial, qed_val);
                        }
                    }
                }

                let mut h_lock = HISTORY.write().unwrap();
                
                // Reset at start of day or if date changed
                if today != current_date {
                    h_lock.data.clear();
                    h_lock.qed.clear();
                    current_date = today.clone();
                    println!("🌙 History reset for new day: {}", current_date);
                }
                
                // Add new data point
                let point = HistoryPoint {
                    time: time_str,
                    pv: total_pv,
                    load: total_load,
                };
                h_lock.data.push(point);
                
                // Update QED values (overwrites with latest)
                for (serial, qed_val) in qed_map {
                    h_lock.qed.insert(serial, qed_val);
                }
                
                // Save to file
                let history_dir = Path::new("history");
                if !history_dir.exists() {
                    let _ = fs::create_dir_all(history_dir);
                }
                
                let file_path = history_dir.join(format!("{}.json", today));
                if let Ok(file) = File::create(&file_path) {
                    let writer = BufWriter::new(file);
                    let _ = serde_json::to_writer(writer, &*h_lock);
                }
                
                last_block = current_block;
            }
            thread::sleep(Duration::from_secs(1)); // Check every 1 second to stay in sync
        }
    });

    // 3. WebSocket Server (1000ms Push)
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

    // 4. REST API
    let app = Router::new()
        .route(
            "/history",
            get(|| async { axum::Json(HISTORY.read().unwrap().clone()) }),
        )
        .route(
            "/dates",
            get(|| async {
                let history_dir = Path::new("history");
                let mut dates: Vec<String> = Vec::new();
                
                if history_dir.exists() {
                    if let Ok(entries) = fs::read_dir(history_dir) {
                        for entry in entries.flatten() {
                            if let Some(name) = entry.file_name().to_str() {
                                if name.ends_with(".json") {
                                    // Extract date from filename (yyyy-mm-dd.json -> yyyy-mm-dd)
                                    dates.push(name.trim_end_matches(".json").to_string());
                                }
                            }
                        }
                    }
                }
                
                dates.sort();
                axum::Json(dates)
            }),
        )
        .route(
            "/history/{date}",
            get(|axum::extract::Path(date): axum::extract::Path<String>| async move {
                // If requesting today's date, return in-memory data
                let today = Local::now().format("%Y-%m-%d").to_string();
                if date == today {
                    let data = HISTORY.read().unwrap().clone();
                    return axum::response::Response::builder()
                        .status(axum::http::StatusCode::OK)
                        .header("Content-Type", "application/json")
                        .body(axum::body::Body::from(serde_json::to_string(&data).unwrap()))
                        .unwrap();
                }
                
                // Otherwise, read from file
                let file_path = Path::new("history").join(format!("{}.json", date));
                if file_path.exists() {
                    if let Ok(file) = File::open(&file_path) {
                        let reader = BufReader::new(file);
                        if let Ok(data) = serde_json::from_reader::<_, HistoryFile>(reader) {
                            return axum::response::Response::builder()
                                .status(axum::http::StatusCode::OK)
                                .header("Content-Type", "application/json")
                                .body(axum::body::Body::from(serde_json::to_string(&data).unwrap()))
                                .unwrap();
                        }
                    }
                }
                axum::response::Response::builder()
                    .status(axum::http::StatusCode::NOT_FOUND)
                    .header("Content-Type", "application/json")
                    .body(axum::body::Body::from("{\"data\":[],\"qed\":{}}"))
                    .unwrap()
            }),
        );

    let addr = "0.0.0.0:3000".parse::<std::net::SocketAddr>().unwrap();
    let listener = TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

fn hardware_worker(state: SharedState, path: &str, label: &str, id: u8) {
    let api = HidApi::new().expect("HID Init Fail");
    let mut last_qed_query = Instant::now() - Duration::from_secs(600);
    let mut cached_qed = String::from("0.00");

    loop {
        if let Ok(dev) = api.open_path(&std::ffi::CString::new(path).unwrap()) {
            if let Some(fields) = query_and_parse_safe(&dev, &format!("QPGS{}", id)) {
                
                // QED Check with 8-character validation
                if last_qed_query.elapsed() > Duration::from_secs(300) {
                    let date = Local::now().format("%Y%m%d").to_string();
                    if let Some(resp_bytes) = send_and_receive_raw(&dev, &format!("QED{}", date)) {
                        let start_pos = resp_bytes.iter().position(|&b| b == 0x28).map(|i| i + 1).unwrap_or(0);
                        let end_pos = resp_bytes.iter().position(|&b| b == 0x0D).unwrap_or(resp_bytes.len());
                        if end_pos > start_pos {
                            let clean_data = String::from_utf8_lossy(&resp_bytes[start_pos..end_pos]);
                            let numeric_part: String = clean_data.chars().take_while(|c| c.is_numeric()).collect();

                            if numeric_part.len() == 8 {
                                if let Ok(wh_val) = numeric_part.parse::<f64>() {
                                    cached_qed = format!("{:.2}", wh_val / 1000.0);
                                    last_qed_query = Instant::now();
                                }
                            }
                        }
                    }
                }

                state.write().unwrap().insert(
                    id,
                    InverterState {
                        label: label.to_string(),
                        raw_data: fields,
                        qed: cached_qed.clone(),
                        last_update: Local::now().format("%H:%M:%S").to_string(),
                    },
                );
            }
        }
        thread::sleep(Duration::from_millis(2000));
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