#!/usr/bin/env python3
import subprocess
import sys
import os

# ═════════════════════════════════════════════════════════════════
# HARD CODED SAFETY NET (JANGAN PERNAH HAPUS INI, BIAR PUN DI LIST LO)
# Menghapus ini = Bootloop / Brick / Hilang Akses Root
# ═════════════════════════════════════════════════════════════════
CRITICAL_PACKAGES = [
    "com.android.systemui", "com.android.settings", "com.android.phone",
    "com.android.packageinstaller", "com.android.providers.settings",
    "com.google.android.gsf", "com.google.android.gms", "com.google.android.gsf.login",
    "android", "com.termux", "com.topjohnwu.magisk", "io.github.vvb2060.magisk",
    "com.android.shell", "com.android.wallpaperbackup", "com.android.providers.telephony"
]

def run_su(command):
    """Jalankan perintah dengan akses root"""
    try:
        result = subprocess.run(f"su -c '{command}'", shell=True, check=True, capture_output=True, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return None

def dump_all_packages():
    """Fase 1: Dump semua package ke file teks"""
    print("[Info] Mengambil daftar semua package... (Ini mungkin memakan waktu beberapa detik)")
    
    # Ambil semua package, hapus prefix "package:", dan urutkan
    raw_output = run_su("pm list packages")
    if not raw_output:
        print("[Error] Gagal mengambil daftar. Pastikan akses root aktif.")
        sys.exit(1)
    
    packages = sorted([line.split(":")[1] for line in raw_output.splitlines() if line.startswith("package:")])
    
    # Simpan ke all_packages.txt
    with open("all_packages.txt", "w") as f:
        for pkg in packages:
            f.write(f"{pkg}\n")
            
    # Buat template custom list jika belum ada
    if not os.path.exists("my_deletable_list.txt"):
        with open("my_deletable_list.txt", "w") as f:
            f.write("# LIST CUSTOM DEBLOAT\n")
            f.write("# Hapus tanda '#' di depan nama package yang INGIN dihapus.\n")
            f.write("# Contoh:\n")
            f.write("# com.facebook.katana\n")
            f.write("# com.google.android.videos\n")
            f.write("\n")
            
    print(f"✅ [Success] Berhasil mengekstrak {len(packages)} package!")
    print("📁 File disimpan sebagai: all_packages.txt")
    print("📝 Silakan edit file: my_deletable_list.txt (pakai perintah: nano my_deletable_list.txt)")
    print("💡 Tip: Cari package di all_packages.txt, copy, lalu paste ke my_deletable_list.txt dan hapus tanda '#'.")

def execute_debloat(dry_run=False):
    """Fase 2: Eksekusi penghapusan berdasarkan custom list"""
    if not os.path.exists("my_deletable_list.txt"):
        print("[Error] File my_deletable_list.txt tidak ditemukan. Jalankan --dump dulu.")
        sys.exit(1)
        
    with open("my_deletable_list.txt", "r") as f:
        # Baca baris, abaikan komentar (#) dan baris kosong
        target_packages = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]
        
    if not target_packages:
        print("[Info] Tidak ada package yang dipilih untuk dihapus di my_deletable_list.txt")
        return

    print(f"\n[Info] Ditemukan {len(target_packages)} target untuk diproses.")
    mode_text = "[DRY RUN - SIMULASI]" if dry_run else "[LIVE EXECUTION]"
    print(f"{mode_text} Memulai proses...\n")

    success_count = 0
    blocked_count = 0
    fail_count = 0

    for pkg in target_packages:
        # 1. Cek Safety Net
        if any(critical in pkg for critical in CRITICAL_PACKAGES):
            print(f"⛔ [BLOCKED] {pkg} -> Terlalu berbahaya (Critical System Package). Dilewati.")
            blocked_count += 1
            continue

        # 2. Eksekusi Uninstall
        print(f"🔄 [Processing] {pkg} ...", end=" ")
        if dry_run:
            print(" (Akan dihapus)")
            success_count += 1
        else:
            result = run_su(f"pm uninstall -k --user 0 {pkg}")
            if result and "Success" in result:
                print("✅ Success")
                success_count += 1
            elif result and "Failure [DELETE_FAILED_INTERNAL_ERROR]" in result:
                print("⚠️ Skipped (Sudah ter-uninstall atau tidak bisa dihapus)")
            else:
                print("❌ Failed")
                fail_count += 1

    print("\n" + "=" * 60)
    print("📊 HASIL EKSEKUSI:")
    print(f"  ✅ Berhasil / Simulasi : {success_count}")
    print(f"  ⛔ Diblokir (Safety Net): {blocked_count}")
    print(f"  ❌ Gagal               : {fail_count}")
    print("=" * 60)
    
    if not dry_run and success_count > 0:
        print("\n💡 REKOMENDASI: Reboot Cloud Phone Anda sekarang untuk membebaskan RAM.")
        print("   Ketik: su -c 'reboot'")

def print_help():
    print("""
🛡️ KYRIEL'S CUSTOM ROOT DEBLOAT MANAGER

Usage:
  python debloat_manager.py [COMMAND]

Commands:
  --dump       : Ekstrak semua package ke 'all_packages.txt' & buat template 'my_deletable_list.txt'
  --run        : Ekseku
