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
    pv: f32,   // We calculate this in the recorder loop using V*I
    load: f32, // We calculate this using V*I or raw active power
}

type SharedState = Arc<RwLock<HashMap<u8, InverterState>>>;

lazy_static! {
    static ref HISTORY: Arc<RwLock<Vec<HistoryPoint>>> = Arc::new(RwLock::new(Vec::new()));
}

#[tokio::main]
async fn main() {
    let state: SharedState = Arc::new(RwLock::new(HashMap::new()));
    let ws_state = Arc::clone(&state);

    println!("🚀 Server Online: Raw Data Streaming Mode");

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
                        let raw = &inv.raw_data;
                        if raw.len() > 14 {
                            // PV1: Volts (11) * Amps (12)
                            let v1 = raw
                                .get(11)
                                .and_then(|s| s.parse::<f32>().ok())
                                .unwrap_or(0.0);
                            let a1 = raw
                                .get(12)
                                .and_then(|s| s.parse::<f32>().ok())
                                .unwrap_or(0.0);
                            // PV2: Volts (14) * Amps (15) -- Adjust indices if needed for your specific card
                            let v2 = raw
                                .get(14)
                                .and_then(|s| s.parse::<f32>().ok())
                                .unwrap_or(0.0);
                            let a2 = raw
                                .get(15)
                                .and_then(|s| s.parse::<f32>().ok())
                                .unwrap_or(0.0);

                            total_pv += (v1 * a1) + (v2 * a2);
                            total_load += raw
                                .get(9)
                                .and_then(|s| s.parse::<f32>().ok())
                                .unwrap_or(0.0);
                        }
                    }
                }

                let mut h_lock = HISTORY.write().unwrap();
                if current_min == 0 {
                    h_lock.clear();
                }
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

    let app = Router::new().route(
        "/history",
        get(|| async { axum::Json(HISTORY.read().unwrap().clone()) }),
    );

    tokio::spawn(async move {
        let listener = TcpListener::bind("0.0.0.0:3001").await.unwrap();
        while let Ok((stream, _)) = listener.accept().await {
            let state_ref = Arc::clone(&ws_state);
            tokio::spawn(async move {
                if let Ok(mut ws_stream) = accept_async(stream).await {
                    loop {
                        let data = state_ref.read().unwrap().clone();
                        let _ = ws_stream
                            .send(Message::Text(serde_json::to_string(&data).unwrap().into()))
                            .await;
                        tokio::time::sleep(Duration::from_millis(800)).await;
                    }
                }
            });
        }
    });

    axum::serve(TcpListener::bind("0.0.0.0:3000").await.unwrap(), app)
        .await
        .unwrap();
}

fn hardware_worker(state: SharedState, path: &str, label: &str, id: u8) {
    let api = HidApi::new().expect("HID Init Fail");
    let mut last_qed = Instant::now() - Duration::from_secs(600);
    let mut qed_val = String::from("0.0");
    loop {
        if let Ok(dev) = api.open_path(&std::ffi::CString::new(path).unwrap()) {
            if let Some(fields) = query_and_parse(&dev, &format!("QPGS{}", id), false) {
                if last_qed.elapsed() > Duration::from_secs(300) {
                    let date = Local::now().format("%Y%m%d").to_string();
                    if let Some(q) = query_and_parse(&dev, &format!("QED{}", date), true) {
                        qed_val = q.first().cloned().unwrap_or(qed_val);
                        last_qed = Instant::now();
                    }
                }
                state.write().unwrap().insert(
                    id,
                    InverterState {
                        label: label.to_string(),
                        raw_data: fields,
                        qed: qed_val.clone(),
                        last_update: format!("{:?}", Instant::now()),
                    },
                );
            }
        }
        thread::sleep(Duration::from_millis(500));
    }
}

pub fn query_and_parse(device: &HidDevice, command: &str, sanitize: bool) -> Option<Vec<String>> {
    let raw = send_and_receive(device, command)?;
    let clean = raw.trim_start_matches('(').split('\r').next()?;
    let processed = if sanitize {
        clean
            .chars()
            .filter(|c| c.is_numeric() || *c == '.' || c.is_whitespace())
            .collect()
    } else {
        clean.to_string()
    };
    Some(
        processed
            .split_whitespace()
            .map(|s| s.to_string())
            .collect(),
    )
}

fn send_and_receive(device: &HidDevice, cmd: &str) -> Option<String> {
    let mut buf = [0u8; 64];
    while let Ok(len) = device.read_timeout(&mut buf, 1) {
        if len == 0 {
            break;
        }
    }
    let mut bytes = cmd.as_bytes().to_vec();
    let mut crc: u16 = 0;
    let table: [u16; 16] = [
        0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50a5, 0x60c6, 0x70e7, 0x8108, 0x9129, 0xa14a,
        0xb16b, 0xc18c, 0xd1ad, 0xe1ce, 0xf1ef,
    ];
    for &b in &bytes {
        let mut da = ((crc >> 8) >> 4) as u8;
        crc <<= 4;
        da ^= b >> 4;
        crc ^= table[da as usize];
        da = ((crc >> 8) >> 4) as u8;
        crc <<= 4;
        da ^= b & 0x0f;
        crc ^= table[da as usize];
    }
    let (mut low, mut high) = ((crc & 0xff) as u8, (crc >> 8) as u8);
    if [0x28, 0x0d, 0x0a].contains(&low) {
        low += 1;
    }
    if [0x28, 0x0d, 0x0a].contains(&high) {
        high += 1;
    }
    bytes.push(high);
    bytes.push(low);
    bytes.push(0x0D);
    for chunk in bytes.chunks(8) {
        let mut block = [0u8; 8];
        block[..chunk.len()].copy_from_slice(chunk);
        let _ = device.write(&block);
    }
    let mut resp = Vec::new();
    let start = Instant::now();
    while start.elapsed() < Duration::from_millis(1500) {
        let mut b = [0u8; 64];
        if let Ok(l) = device.read_timeout(&mut b, 20) {
            if l > 0 {
                resp.extend_from_slice(&b[..l]);
                if resp.contains(&0x0D) {
                    break;
                }
            }
        }
    }
    let s = String::from_utf8_lossy(&resp).to_string();
    s.find('(').map(|i| s[i..].to_string())
}
