## Installation

### Ubuntu / Debian / Kali Linux / NetHunter

```bash
sudo apt update && sudo apt install -y git python3 python3-pip python3-venv
git clone https://github.com/Chrnouz/MeduzaV3.git
cd MeduzaV3
chmod +x install.sh
./install.sh
```

### Termux (Android)

```bash
pkg update && pkg upgrade -y
termux-setup-storage
pkg install git python -y
git clone https://github.com/Chrnouz/MeduzaV3.git
cd MeduzaV3
chmod +x install.sh
./install.sh
```

### macOS

```bash
brew install git python
git clone https://github.com/Chrnouz/MeduzaV3.git
cd MeduzaV3
chmod +x install.sh
./install.sh
```

### Additional Dependencies

If the installer does not install them automatically:

```bash
python -m pip install websockets websocket-client
```
