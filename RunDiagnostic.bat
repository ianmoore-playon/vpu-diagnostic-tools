@echo off
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/ianmoore-playon/vpu-diagnostic-tools/refs/heads/main/TestCameraConnectivity.ps1' | iex"
