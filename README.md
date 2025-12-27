# ☀️ Solar Monitor
A high-performance monitoring solution for solar inverters. 🚀 This project features a Rust-powered backend for hardware communication and a Flutter UI for a sleek, real-time energy dashboard.


# 📜 Attribution & License

This project is open-source under the MIT License.

Requirement: If you use, modify, or distribute this code, you must include the original copyright notice. Please credit the author by linking back to this repository: https://github.com/CoderMaximus/SolarMonitor


# 🏗️ Project Structure
`inverter_api/`: 🦀 The Rust backend. Handles talking to USB HID devices.

`solar_monitor/`: ⚡ The Flutter frontend. Provides a beautiful interface to visualize your solar and load data.

# ⚙️ Installation & Setup

1️⃣ Prerequisites

Make sure you have the following installed:

  • Flutter SDK.
  
  • Rust & Cargo.
  
  • A Linux-based device (like a Raspberry Pi 5, or an old laptop) to act as the server.


2️⃣ Clone:

`git clone https://github.com/CoderMaximus/SolarMonitor.git`

`cd SolarMonitor`


3️⃣ Configure the Rust Backend: `inverter_api`:

  • Edit your inverter's USB HID paths in `src/main.rs`:

        let master_s = Arc::clone(&state); //Example for 2 inverters
        thread::spawn(move || hardware_worker(master_s, "/dev/hidrawX", "Master", 1));

        let slave_s = Arc::clone(&state);
        thread::spawn(move || hardware_worker(slave_s, "/dev/hidrawY", "Slave", 2));
    
  • Change the permissions of the `hidrawX` you are using(WARNING: this is a temporary setup, for a permanent setup, read the UDEV section ):
  
    `chmod 666 /dev/hidrawX`

  • Build & Run:
  
    `cargo build --release`

    `./target/release/inverter_api`

  Note: Rust binaries can be compiled for ARM64 (Raspberry Pi) directly on the device or via cross-compilation!


4️⃣ Build Flutter Frontend:

  ```
cd solar_monitor
flutter pub get
flutter build apk --release // should work on Windows and Linux desktops too, not tested on iOS
  ```
The apk can be found in `/build/app/outputs/flutter-apk/app-release.apk`


Connect to the same network the server is running on, Run the App, go to settings, and put the local IP Address and the port, which is set to 3000 by defualt.



# Persistent USB Naming (udev)

By default, Linux assigns `hidrawX` IDs dynamically. If your server restarts, `/dev/hidraw0` might become `/dev/hidraw4`, breaking your configuration. To prevent this, we use `udev` rules to bind a permanent alias (symlink) to the physical USB port.

1️⃣ Identify your Inverter

  Plug in your inverter and list the current devices:

    `ls -la /dev/hidraw*`

  If a new device like `/dev/hidraw4` appears, that is your target.

2️⃣ Get the Physical Path

  Run the following command to find the unique hardware path for that port:

    `udevadm info --query=property --name=/dev/hidraw4 | grep ID_PATH=`

  Copy the result. It will look something like: `ID_PATH=pci-0000:00:14.0-usb-0:7:1.0`

3️⃣ Create the Mapping Rule

  Create a new rules file:

    `sudo nano /etc/udev/rules.d/99-solar-inverters.rules`

  Paste the following line, replacing the ID_PATH with yours:

    `SUBSYSTEM=="hidraw", ENV{ID_PATH}=="pci-0000:00:14.0-usb-0:7:1.0", SYMLINK+="inverter_1", MODE="0666"`

  Repeat this for additional inverters, ensuring each has a unique SYMLINK name (e.g., inverter_2).


4️⃣ Apply & Verify

  Reload the system rules and check for your new alias:

    `sudo udevadm control --reload-rules && sudo udevadm trigger`
    `ls -la /dev/inverter*`

Success! If you see `/dev/inverter_1 -> hidraw4`, you can now use `/dev/inverter_1` in your Rust code. It will now remain constant regardless of reboots.


# IMPORTANT: Known Bugs 🐜:
  • PV Power might spike(27000W or something like that) it's probably due to wrong readings from the inverter.



# 🤝 Contributing

Contributions are what make the open-source community such an amazing place to learn, inspire, and create. Any contributions you make are greatly appreciated.
How to Contribute:

  • Report Bugs: Open an Issue if you find hardware compatibility problems or UI bugs.

  • Feature Requests: Have an idea for a better chart or a new inverter protocol? Let me know in the Issues!

➡️ Pull Requests:

   • Fork the Project.

   • Create your Feature Branch (git checkout -b feature/AmazingFeature).

   • Commit your Changes (git commit -m 'Add some AmazingFeature').

   • Push to the Branch (git push origin feature/AmazingFeature).

   • Open a Pull Request.
