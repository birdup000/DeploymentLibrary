# XT Systems Deployment Library

Public collection of cross-platform deployment scripts for XT Systems managed machines. These scripts are automatically synced into the XT Systems platform as built-in global deployments available to all users.

## Structure

```
manifest.json          # Deployment definitions and metadata
windows/               # PowerShell scripts for Windows
linux/                 # Bash scripts for Linux/macOS
```

## Available Deployments

| Deployment | Platforms | Category |
|---|---|---|
| Reboot Machine | Windows, Linux, macOS | System |
| Shutdown Machine | Windows, Linux, macOS | System |
| Install Brave Browser | Windows, Linux | Software |
| Install Visual Studio Code | Windows, Linux | Software |
| Install Git | Windows, Linux | Software |
| Install Python | Windows, Linux | Software |
| Install NVIDIA CUDA Toolkit | Windows, Linux | Software |
| Install PowerShell (Linux) | Linux | Software |
| Install Docker | Windows, Linux | Software |
| Install Node.js | Windows, Linux | Software |
| Install Google Chrome | Windows, Linux | Software |
| Install Google Chrome Enterprise | Windows | Software |
| Update Google Chrome Enterprise | Windows | Maintenance |
| Configure Chrome Enterprise Policies | Windows | Configuration |
| Install 7-Zip | Windows | Software |
| Install Blender | Windows, Linux | Software |
| Update Blender | Windows | Maintenance |
| Install Krita | Windows, Linux | Software |
| Update Krita | Windows | Maintenance |
| Install Blockbench Desktop | Windows | Software |
| Update Blockbench Desktop | Windows | Maintenance |
| Install OBS Studio | Windows, Linux | Software |
| Update OBS Studio | Windows | Maintenance |
| Install CapCut | Windows | Software |
| Update CapCut | Windows | Maintenance |
| Install MCreator | Windows | Software |
| Update MCreator | Windows | Maintenance |
| Install LEGO Education SPIKE | Windows | Software |
| Update LEGO Education SPIKE | Windows | Maintenance |
| Install Windows Sound Recorder | Windows | Software |
| Update Windows Sound Recorder | Windows | Maintenance |
| Install Xbox Game Bar | Windows | Software |
| Update Xbox Game Bar | Windows | Maintenance |
| Install Microsoft Photos | Windows | Software |
| Update Microsoft Photos | Windows | Maintenance |
| Install MIT App Inventor Emulator Setup | Windows | Software |
| Update MIT App Inventor Emulator Setup | Windows | Maintenance |
| Create Web App Shortcut | Windows | Software |
| Refresh Web App Shortcut | Windows | Maintenance |
| Install Roblox Studio | Windows | Software |
| Update Roblox Studio | Windows | Maintenance |
| Collect System Information | Windows, Linux, macOS | Diagnostics |
| Disk Cleanup | Windows, Linux | Maintenance |
| Run Windows Update | Windows | Maintenance |
| Run Linux Updates | Linux | Maintenance |
| Enable Remote Desktop | Windows | Configuration |
| Enable SSH Server | Windows, Linux | Configuration |
| Set Hostname | Windows, Linux | Configuration |
| Flush DNS Cache | Windows, Linux, macOS | Network |

## Contributing

1. Add your script files to the appropriate platform folder (`windows/` or `linux/`)
2. Add a deployment entry to `manifest.json` with metadata
3. Submit a pull request

Scripts are automatically picked up by the XT Systems backend on startup.
