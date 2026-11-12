#!/usr/bin/env python3
import subprocess
import time
import sys

# ═════════════════════════════════════════════════════════════════
# KONFIGURASI (SESUAIKAN DENGAN DEVICE LO)
# ═════════════════════════════════════════════════════════════════
# Ganti dengan package name Delta Executor lo (bisa cek pake 'pm list packages | grep delta')
DELTA_PKG_1 = "com.roblox.clienw"       # Instance 1
DELTA_PKG_2 = "com.roblox.clienx" # Instance 2

GAME_URL = "https://www.roblox.com/games/15002061926" # Death Ball

# SCRIPT YANG MAU DI-INJECT (Paste script Lua lo di sini)
# Gunakan \n untuk baris baru. Contoh sederhana: print("Hacked by Kyriel")
LUA_SCRIPT = "print('Auto-Executed by Kyriel Bot!')" 

# ⚠️ PENTING: Koordinat ini HARUS dikalibrasi sesuai layar Cloud Phone lo!
# Aktifkan "Show Taps" di Developer Options untuk melihat X Y saat lo tap.
COORD_RECENTS_CARD = "540 400"       # Tap kartu aplikasi pertama di Recent Apps
COORD_SPLIT_ICON = "540 250"         # Tap ikon Split Screen
COORD_SECOND_APP = "540 1200"        # Tap aplikasi kedua di daftar split screen

# Koordinat Tombol "Play/Execute" di dalam Delta Executor
# (Biasanya ada di tengah bawah atau tengah layar setelah game load)
COORD_DELTA_EXECUTE_BTN = "540 1800" 

def run_su(command):
    try:
        result = subprocess.run(f"su -c '{command}'", shell=True, check=True, capture_output=True, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"[Error Root] {command} failed.")
        return None

def launch_app(package):
    print(f"[Info] Launching {package}...")
    run_su(f"am force-stop {package}")
    time.sleep(1)
    # Buka Delta langsung ke Roblox via Deep Link
    run_su(f"am start -a android.intent.action.VIEW -d '{GAME_URL}' {package}")
    print(f"[Success] {package} launched with game link.")

def trigger_split_screen():
    print("[Info] Triggering Split Screen via Input Injection...")
    run_su("input keyevent KEYCODE_APP_SWITCH")
    time.sleep(2.0)
    run_su(f"input tap {COORD_RECENTS_CARD}")
    time.sleep(1.0)
    run_su(f"input tap {COORD_SPLIT_ICON}")
    time.sleep(1.5)
    run_su(f"input tap {COORD_SECOND_APP}")
    print("[Success] Split Screen activated.")

def auto_inject_and_execute():
    print("[Info] Waiting for games to load (15 seconds)...")
    time.sleep(15) # Tunggu Roblox & Delta load sepenuhnya
    
    print("[Info] Simulating Execute Button Click on both screens...")
    # Karena kita di split screen, koordinat Y mungkin berubah tergantung ukuran jendela.
    # Kita coba tap di area tengah bawah layar (asumsi tombol execute ada di sana)
    
    # Inject ke Instance 1 (Layar Atas/Kiri)
    # Catatan: Di split screen, koordinat relatif terhadap jendela masing-masing
    run_su(f"input tap {COORD_DELTA_EXECUTE_BTN.split()[0]} {str(int(COORD_DELTA_EXECUTE_BTN.split()[1]) // 2)}") 
    time.sleep(1)
    
    # Inject ke Instance 2 (Layar Bawah/Kanan)
    # Kita perlu pindah fokus atau tap di area jendela kedua. 
    # Cara paling aman: Tap area kosong di jendela 2 dulu buat fokus, lalu tap tombol execute
    run_su(f"input tap {COORD_DELTA_EXECUTE_BTN.split()[0]} {str(int(COORD_DELTA_EXECUTE_BTN.split()[1]) + 200)}")
    time.sleep(1)
    
    # Klik tombol Execute/Paste di Delta (Posisi ini sangat tergantung UI Delta)
    # Biasanya tombol Execute ada di tengah. Kita simulasi tap tengah layar masing-masing bagian
    print("[Info] Attempting to click Execute/Paste buttons...")
    # Simulasi tap tengah layar atas
    run_su("input tap 540 600") 
    time.sleep(0.5)
    # Simulasi tap tengah layar bawah
    run_su("input tap 540 1800")
    
    print("[Success] Injection simulation completed.")

def main():
    print("=" * 60)
    print("🚀 KYRIEL'S AUTO DELTA SPLIT & INJECTOR")
    print("=" * 60)
    
    if not run_su("id"):
        print("[Fatal] Root access denied!")
        sys.exit(1)
    print("[OK] Root confirmed.\n")

    # 1. Launch Apps
    launch_app(DELTA_PKG_1)
    time.sleep(2)
    launch_app(DELTA_PKG_2)
    time.sleep(3)

    # 2. Split Screen
    trigger_split_screen()
    
    # 3. Wait & Inject
    auto_inject_and_execute()

    print("\n" + "=" * 60)
    print("✅ DONE! Cek layar Cloud Phone lo.")
    print("⚠️ Jika script belum ter-paste otomatis, lo mungkin perlu")
    print("   menyesuaikan COORD_DELTA_EXECUTE_BTN di dalam script.")
    print("=" * 60)

if __name__ == "__main__":
    main()
