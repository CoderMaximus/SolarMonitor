// main.rs
#[macro_use]
extern crate lazy_static;

use axum::{routing::get, Router};
use chrono::{Local, Timelike};
use futures_util::SinkExt;
use hidapi::{HidApi, HidDevice};
use serde::Serialize;
use std::collections::HashMap;
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

#[derive(Serialize, Clone, Debug)]
struct HistoryPoint {
    x: u32,
    pv: f32,
    load: f32,
}

type SharedState = Arc<RwLock<HashMap<u8, InverterState>>>;

lazy_static! {
    static ref HISTORY: Arc<RwLock<Vec<HistoryPoint>>> = Arc::new(RwLock::new(Vec::new()));
}

#[tokio::main]
async fn main() {
    let state: SharedState = Arc::new(RwLock::new(HashMap::new()));
    let ws_state = Arc::clone(&state);

    println!("🚀 PI30MAX Server Online | Port 3000 (REST) | Port 3001 (WS)");

    // Hardware Workers
    let master_s = Arc::clone(&state);
    thread::spawn(move || hardware_worker(master_s, "/dev/inverter_master", "Master", 1));

    let slave_s = Arc::clone(&state);
    thread::spawn(move || hardware_worker(slave_s, "/dev/inverter_slave", "Slave", 2));

    // BACKGROUND RECORDER: Calculates power for the history graph
    let history_state = Arc::clone(&state);
    thread::spawn(move || {
        let mut last_min = -1;
        loop {
            let now = Local::now();
            let current_min = (now.hour() * 60 + now.minute()) as i32;

            if current_min != last_min {
                let mut total_pv = 0.0;
                let mut total_load = 0.0;

                {
                    let lock = history_state.read().unwrap();
                    for (_, inv) in lock.iter() {
                        let fields = &inv.raw_data;
                        if fields.len() >= 29 {
                            // PV1: Index 14 (V) and Index 25 (A)
                            let v1 = fields[14].parse::<f32>().unwrap_or(0.0);
                            let a1 = fields[25].parse::<f32>().unwrap_or(0.0);
                            
                            // PV2: Index 27 (V) and Index 28 (A)
                            let v2 = fields[27].parse::<f32>().unwrap_or(0.0);
                            let a2 = fields[28].parse::<f32>().unwrap_or(0.0);

                            // Load: Index 9 (Active Power in Watts)
                            let load = fields[9].parse::<f32>().unwrap_or(0.0);

                            total_pv += (v1 * a1) + (v2 * a2);
                            total_load += load;
                        }
                    }
                }

                let mut h_lock = HISTORY.write().unwrap();
                if current_min == 0 { h_lock.clear(); }
                h_lock.push(HistoryPoint {
                    x: current_min as u32,
                    pv: total_pv,
                    load: total_load,
                });
                last_min = current_min;
            }
            thread::sleep(Duration::from_secs(10));
        }
    });

    // WebSocket Server (Port 3001)
    tokio::spawn(async move {
        let listener = TcpListener::bind("0.0.0.0:3001").await.unwrap();
        while let Ok((stream, _)) = listener.accept().await {
            let state_ref = Arc::clone(&ws_state);
            tokio::spawn(async move {
                if let Ok(mut ws_stream) = accept_async(stream).await {
                    loop {
                        let data = state_ref.read().unwrap().clone();
                        let json = serde_json::to_string(&data).unwrap();
                        if ws_stream.send(Message::Text(json.into())).await.is_err() {
                            break; 
                        }
                        tokio::time::sleep(Duration::from_millis(1000)).await;
                    }
                }
            });
        }
    });

    // REST API (Port 3000)
    let app = Router::new().route(
        "/history",
        get(|| async { axum::Json(HISTORY.read().unwrap().clone()) }),
    );

    axum::serve(TcpListener::bind("0.0.0.0:3000").await.unwrap(), app)
        .await
        .unwrap();
}

fn hardware_worker(state: SharedState, path: &str, label: &str, id: u8) {
    let api = HidApi::new().expect("HID Init Fail");
    let mut last_qed_query = Instant::now() - Duration::from_secs(600);
    let mut cached_qed = String::from("0.00");

    loop {
        if let Ok(dev) = api.open_path(&std::ffi::CString::new(path).unwrap()) {
            // 1. Get Main Parallel Data (QPGS)
            if let Some(fields) = query_and_parse_safe(&dev, &format!("QPGS{}", id)) {
                
                // 2. Periodic Energy Query (QED) - Dedicated Fix for Slave
                if last_qed_query.elapsed() > Duration::from_secs(300) {
                    let date = Local::now().format("%Y%m%d").to_string();
                    let qed_cmd = format!("QED{}", date);
                    
                    if let Some(resp_bytes) = send_and_receive_raw(&dev, &qed_cmd) {
                        let start_pos = resp_bytes.iter().position(|&b| b == 0x28).map(|i| i + 1).unwrap_or(0);
                        let end_pos = resp_bytes.iter().position(|&b| b == 0x0D).unwrap_or(resp_bytes.len());
                        
                        if end_pos > start_pos {
                            let clean_data = String::from_utf8_lossy(&resp_bytes[start_pos..end_pos]);
                            // take_while ensures we stop at the end of the energy number
                            let numeric_part: String = clean_data.chars()
                                .take_while(|c| c.is_numeric())
                                .collect();

                            if let Ok(wh_val) = numeric_part.parse::<f64>() {
                                cached_qed = format!("{:.2}", wh_val / 1000.0);
                                last_qed_query = Instant::now();
                            }
                        }
                    }
                }

                // 3. Update Shared State
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
        // Small delay to prevent CPU pinning
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
    
    Some(
        clean_str
            .split_whitespace()
            .map(|s| s.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '.').collect())
            .collect(),
    )
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