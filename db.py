#!/usr/bin/env python3
import subprocess
import sys
import os

# ═════════════════════════════════════════════════════════════════
# CRITICAL PACKAGES DATABASE (EXACT MATCH)
# JANGAN PERNAH MENCOBA MENGHAPUS/MENONAKTIFKAN PACKAGE INI!
# Berbasis analisis dumpsys & struktur Cloud Phone umum.
# ═════════════════════════════════════════════════════════════════
CRITICAL_PACKAGES = {
    # --- Android Core Framework ---
    "android",
    "android.ext.services",
    "android.ext.shared",
    "com.android.shell",
    "com.android.systemui",
    "com.android.settings",
    "com.android.providers.settings",
    "com.android.permissioncontroller",
    "com.android.packageinstaller",
    
    # --- Cloud Phone Specific Infrastructure (VITAL!) ---
    "com.baidu.cloud.service",
    "com.wshl.file.observerservice",
    "com.android.provider.xmonitor",
    "com.android.monitor",
    "com.android.toolkit",
    "com.android.tools",
    "com.android.provider.root",
    "com.android.provider.multiapp",
    "com.android.provider.mock",
    "com.android.provider.patch",
    "com.android.provider.proxy",
    "com.android.provider.apt",
    "com.android.provider.devicecheck",
    
    # --- Connectivity & Network Stack ---
    "com.android.networkstack.inprocess",
    "com.android.networkstack.tethering.inprocess",
    "com.android.networkstack.permissionconfig",
    "com.android.connectivity.resources",
    "com.android.bluetooth",
    "com.android.nfc",
    "com.android.se",
    "com.android.location.fused",
    "com.android.server.telecom",
    "com.android.phone",
    "com.android.mms.service",
    
    # --- Launcher & UI Components ---
    "com.android.launcher3",
    "com.android12.launcher3",
    "com.android.inputdevices",
    "com.android.keychain",
    "com.android.wallpaperbackup",
    "com.android.dynsystem",
    
    # --- Google Core Services ---
    "com.google.android.gms",
    "com.google.android.gsf",
    "com.google.android.gsf.login",
    "com.google.android.webview",
    "com.android.vending", # Play Store
    
    # --- Storage & Media Providers ---
    "com.android.externalstorage",
    "com.android.providers.media",
    "com.android.providers.media.module",
    "com.android.providers.downloads",
    "com.android.providers.downloads.ui",
    "com.android.providers.contacts",
    "com.android.providers.telephony",
    "com.android.providers.blockednumber",
    "com.android.providers.calendar",
    "com.android.providers.userdictionary",
    
    # --- Other System Essentials ---
    "com.android.localtransport",
    "com.android.backupconfirm",
    "com.android.managedprovisioning",
    "com.android.provision",
    "com.android.certinstaller",
    "com.android.captiveportallogin",
    "com.android.simappdialog",
    "com.android.companiondevicemanager",
    "com.android.cts.ctsshim",
    "com.android.cts.priv.ctsshim",
    "com.android.modulemetadata",
    
    # --- Termux & Root Tools ---
    "com.termux",
    "com.topjohnwu.magisk",
    "io.github.vvb2060.magisk",
}

def run_su(command):
    """Menjalankan perintah dengan akses root"""
    try:
        result = subprocess.run(f"su -c '{command}'", shell=True, check=True, capture_output=True, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return None

def dump_all_packages():
    """Fase 1: Dump semua package ke file teks"""
    print("[Info] Mengambil daftar semua package...")
    raw_output = run_su("pm list packages")
    if not raw_output:
        print("[Error] Gagal mengambil daftar. Pastikan akses root aktif.")
        sys.exit(1)
    
    packages = sorted([line.split(":")[1] for line in raw_output.splitlines() if line.startswith("package:")])
    
    with open("all_packages.txt", "w") as f:
        for pkg in packages:
            f.write(f"{pkg}\n")
            
    if not os.path.exists("my_deletable_list.txt"):
        with open("my_deletable_list.txt", "w") as f:
            f.write("# LIST CUSTOM DEBLOAT\n")
            f.write("# Hapus tanda '#' di depan nama package yang INGIN dihapus/dinonaktifkan.\n")
            f.write("# Contoh:\n")
            f.write("# com.facebook.katana\n")
            f.write("# com.google.android.videos\n\n")
            
    print(f"[Success] Berhasil mengekstrak {len(packages)} package!")
    print("📁 File disimpan sebagai: all_packages.txt")
    print("📝 Silakan edit file: my_deletable_list.txt (pakai perintah: nano my_deletable_list.txt)")

def execute_debloat(dry_run=False, uninstall_mode=False):
    """Fase 2: Eksekusi berdasarkan custom list"""
    if not os.path.exists("my_deletable_list.txt"):
        print("[Error] File my_deletable_list.txt tidak ditemukan. Jalankan --dump dulu.")
        sys.exit(1)
        
    with open("my_deletable_list.txt", "r") as f:
        target_packages = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]
        
    if not target_packages:
        print("[Info] Tidak ada package yang dipilih untuk diproses di my_deletable_list.txt")
        return

    mode_name = "UNINSTALL" if uninstall_mode else "DISABLE"
    print(f"\n[Info] Ditemukan {len(target_packages)} target untuk diproses ({mode_name} MODE).")
    
    if dry_run:
        print("[DRY RUN MODE] Simulasi saja, tidak ada perubahan sistem.\n")
    else:
        print(f"[LIVE MODE] Melakukan {mode_name} pada sistem...\n")

    success_count = 0
    blocked_count = 0
    fail_count = 0

    for pkg in target_packages:
        # 1. Cek Safety Net (Exact Match)
        if pkg in CRITICAL_PACKAGES:
            print(f"⛔ [BLOCKED] {pkg} -> Critical System Package. Dilewati demi keamanan.")
            blocked_count += 1
            continue

        # 2. Eksekusi
        print(f"🔄 [{mode_name}] {pkg} ...", end=" ")
        
        if dry_run:
            print("(Akan diproses)")
            success_count += 1
        else:
            if uninstall_mode:
                cmd = f"pm uninstall -k --user 0 {pkg}"
            else:
                cmd = f"pm disable-user --user 0 {pkg}"
                
            result = run_su(cmd)
            
            if result and ("Success" in result or "disabled" in result.lower()):
                print("✅ Success")
                success_count += 1
            elif result and "already disabled" in result.lower():
                print("⚠️ Already Disabled")
                success_count += 1
            elif result and "not installed" in result.lower():
                print("ℹ️ Not Installed")
                success_count += 1
            else:
                print("❌ Failed")
                fail_count += 1

    print("\n" + "=" * 60)
    print(f"📊 HASIL EKSEKUSI ({mode_name}):")
    print(f"  ✅ Berhasil / Simulasi : {success_count}")
    print(f"  ⛔ Diblokir (Safety)   : {blocked_count}")
    print(f"  ❌ Gagal               : {fail_count}")
    print("=" * 60)
    
    if not dry_run and success_count > 0:
        print("\n💡 REKOMENDASI: Reboot Cloud Phone Anda untuk membebaskan RAM sepenuhnya.")
        print("   Ketik: su -c 'reboot'")

def print_help():
    help_lines = [
        "",
        "🛡️ KYRIEL'S SAFE CLOUD PHONE DEBLOAT MANAGER v3",
        "=" * 50,
        "",
        "Usage: python db.py [COMMAND]",
        "",
        "Commands:",
        "  --dump       : Ekstrak semua package ke all_packages.txt & buat template",
        "  --run        : Eksekusi DISABLE berdasarkan my_deletable_list.txt (AMAN)",
        "  --uninstall  : Eksekusi UNINSTALL berdasarkan my_deletable_list.txt (BERISIKO)",
        "  --dry-run    : Simulasi proses (TIDAK MENGUBAH SISTEM)",
        "  --help       : Tampilkan bantuan ini",
        "",
        "Workflow Aman:",
        "  1. python db.py --dump",
        "  2. nano my_deletable_list.txt (hapus tanda # pada target)",
        "  3. python db.py --dry-run (cek dulu)",
        "  4. python db.py --run (disable dulu)",
        "  5. su -c 'reboot' (test stabilitas)",
        "  6. Jika stabil, baru gunakan --uninstall jika perlu storage",
        ""
    ]
    print("\n".join(help_lines))

def main():
    if len(sys.argv) < 2 or sys.argv[1] == "--help":
        return print_help()

    # Cek root di awal
    if not run_su("id"):
        print("[Fatal] Akses root tidak terdeteksi! Pastikan Termux sudah diberi izin Superuser.")
        sys.exit(1)
    print("✅ Root access confirmed.\n")

    command = sys.argv[1]
    
    if command == "--dump":
        dump_all_packages()
    elif command == "--run":
        execute_debloat(dry_run=False, uninstall_mode=False)
    elif command == "--uninstall":
        print("⚠️ PERINGATAN: Mode Uninstall akan menghapus APK dari sistem.")
        print("⚠️ Gunakan hanya jika Anda sudah yakin 100% dan memiliki backup.")
        confirm = input("Lanjut? (y/n): ").strip().lower()
        if confirm == 'y':
            execute_debloat(dry_run=False, uninstall_mode=True)
        else:
            print("[Aborted]")
    elif command == "--dry-run":
        execute_debloat(dry_run=True, uninstall_mode=False)
    else:
        print(f"[Error] Perintah '{command}' tidak dikenali. Ketik --help untuk bantuan.")

if __name__ == "__main__":
    main()
