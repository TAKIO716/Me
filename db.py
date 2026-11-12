#!/usr/bin/env python3
import subprocess
import sys
import os

# ═════════════════════════════════════════════════════════════════
# HARD CODED SAFETY NET (JANGAN PERNAH HAPUS INI)
# ═════════════════════════════════════════════════════════════════
CRITICAL_PACKAGES = [
    "com.android.systemui", "com.android.settings", "com.android.phone",
    "com.android.packageinstaller", "com.android.providers.settings",
    "com.google.android.gsf", "com.google.android.gms", "com.google.android.gsf.login",
    "android", "com.termux", "com.topjohnwu.magisk", "io.github.vvb2060.magisk",
    "com.android.shell", "com.android.wallpaperbackup", "com.android.providers.telephony"
]

def run_su(command):
    try:
        result = subprocess.run(f"su -c '{command}'", shell=True, check=True, capture_output=True, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return None

def dump_all_packages():
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
            f.write("# Hapus tanda '#' di depan nama package yang INGIN dihapus.\n")
            f.write("# Contoh:\n")
            f.write("# com.facebook.katana\n")
            f.write("# com.google.android.videos\n\n")
            
    print(f"[Success] Berhasil mengekstrak {len(packages)} package!")
    print("File disimpan sebagai: all_packages.txt")
    print("Silakan edit file: my_deletable_list.txt")

def execute_debloat(dry_run=False):
    if not os.path.exists("my_deletable_list.txt"):
        print("[Error] File my_deletable_list.txt tidak ditemukan. Jalankan --dump dulu.")
        sys.exit(1)
        
    with open("my_deletable_list.txt", "r") as f:
        target_packages = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]
        
    if not target_packages:
        print("[Info] Tidak ada package yang dipilih untuk dihapus.")
        return

    print(f"\n[Info] Ditemukan {len(target_packages)} target untuk diproses.")
    mode_text = "[DRY RUN]" if dry_run else "[LIVE]"
    print(f"{mode_text} Memulai proses...\n")

    success_count = 0
    blocked_count = 0
    fail_count = 0

    for pkg in target_packages:
        if any(critical in pkg for critical in CRITICAL_PACKAGES):
            print(f"[BLOCKED] {pkg} -> Critical System. Dilewati.")
            blocked_count += 1
            continue

        print(f"[Processing] {pkg} ...", end=" ")
        if dry_run:
            print("(Akan dihapus)")
            success_count += 1
        else:
            result = run_su(f"pm uninstall -k --user 0 {pkg}")
            if result and "Success" in result:
                print("Success")
                success_count += 1
            else:
                print("Failed/Skipped")
                fail_count += 1

    print("\n" + "=" * 60)
    print("HASIL EKSEKUSI:")
    print(f"  Berhasil / Simulasi : {success_count}")
    print(f"  Diblokir (Safety)   : {blocked_count}")
    print(f"  Gagal               : {fail_count}")
    print("=" * 60)
    
    if not dry_run and success_count > 0:
        print("\nREKOMENDASI: Reboot Cloud Phone Anda.")
        print("Ketik: su -c 'reboot'")

def print_help():
    help_lines = [
        "",
        "KYRIEL'S CUSTOM ROOT DEBLOAT MANAGER",
        "=" * 50,
        "",
        "Usage: python db.py [COMMAND]",
        "",
        "Commands:",
        "  --dump     : Ekstrak semua package ke all_packages.txt",
        "  --run      : Eksekusi penghapusan berdasarkan my_deletable_list.txt",
        "  --dry-run  : Simulasi (TIDAK MENGHAPUS ASLI)",
        "  --help     : Tampilkan bantuan ini",
        "",
        "Workflow:",
        "  1. python db.py --dump",
        "  2. nano my_deletable_list.txt (hapus tanda #)",
        "  3. python db.py --dry-run",
        "  4. python db.py --run",
        "  5. su -c 'reboot'",
        ""
    ]
    print("\n".join(help_lines))

def main():
    if len(sys.argv) < 2 or sys.argv[1] == "--help":
        return print_help()

    if not run_su("id"):
        print("[Fatal] Akses root tidak terdeteksi!")
        sys.exit(1)
    print("[OK] Root access confirmed.\n")

    command = sys.argv[1]
    
    if command == "--dump":
        dump_all_packages()
    elif command == "--run":
        execute_debloat(dry_run=False)
    elif command == "--dry-run":
        execute_debloat(dry_run=True)
    else:
        print(f"[Error] Perintah '{command}' tidak dikenali.")
        print_help()

if __name__ == "__main__":
    main()
