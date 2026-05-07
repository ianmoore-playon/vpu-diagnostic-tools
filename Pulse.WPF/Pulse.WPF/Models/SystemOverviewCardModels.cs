using System.Collections.Generic;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    // ============================================================
    // Typed POCO models for the System Overview card layout
    // (UX_REVIEW round 2 §3 / §5). These replace the single flat
    // List<SystemOverviewRow> Inventory as the authoritative shape
    // for the panel — the flat inventory is still produced for
    // back-compat of the Copy-as-text path, but every card now binds
    // to its own typed model so the XAML stays declarative and per-
    // card layouts can diverge (tables, expanders, etc.) without
    // each card having to know about the others.
    //
    // All card models derive from ObservableObject so a service can
    // (in a future round) mutate individual fields and the UI will
    // refresh in place. Today the service rebuilds the model whole
    // and the parent VM swaps the reference, but the inheritance is
    // cheap insurance against the partial-update use case.
    // ============================================================

    /// <summary>One label/value pair inside a card. </summary>
    public class KeyValueRow
    {
        public string Label { get; set; } = "";
        public string Value { get; set; } = "Not reported";
    }

    /// <summary>Identity card — manufacturer / model / serial / asset / chassis. </summary>
    public class IdentityCardModel : ObservableObject
    {
        private string _computerName = "Not reported";
        public string ComputerName { get => _computerName; set => Set(ref _computerName, value); }
        private string _manufacturer = "Not reported";
        public string Manufacturer { get => _manufacturer; set => Set(ref _manufacturer, value); }
        private string _model = "Not reported";
        public string Model { get => _model; set => Set(ref _model, value); }
        private string _serialNumber = "Not reported";
        public string SerialNumber { get => _serialNumber; set => Set(ref _serialNumber, value); }
        private string _assetTag = "Not reported";
        public string AssetTag { get => _assetTag; set => Set(ref _assetTag, value); }
        private string _chassisType = "Not reported";
        public string ChassisType { get => _chassisType; set => Set(ref _chassisType, value); }
        private string _systemType = "Not reported";
        public string SystemType { get => _systemType; set => Set(ref _systemType, value); }
        private string _network = "Not reported";
        public string Network { get => _network; set => Set(ref _network, value); }
        private string _biosVersion = "Not reported";
        public string BiosVersion { get => _biosVersion; set => Set(ref _biosVersion, value); }
    }

    /// <summary>Pixellot Software card. </summary>
    public class PixellotSoftwareCardModel : ObservableObject
    {
        private string _appVersion = "Not reported";
        public string AppVersion { get => _appVersion; set => Set(ref _appVersion, value); }
        private string _systemImageVersion = "Not reported";
        public string SystemImageVersion { get => _systemImageVersion; set => Set(ref _systemImageVersion, value); }
        private string _packageDependencies = "Not reported";
        public string PackageDependencies { get => _packageDependencies; set => Set(ref _packageDependencies, value); }
        private string _installDate = "Not reported";
        public string InstallDate { get => _installDate; set => Set(ref _installDate, value); }
    }

    /// <summary>Processor card. </summary>
    public class ProcessorCardModel : ObservableObject
    {
        private string _name = "Not reported";
        public string Name { get => _name; set => Set(ref _name, value); }
        private string _manufacturer = "Not reported";
        public string Manufacturer { get => _manufacturer; set => Set(ref _manufacturer, value); }
        private string _cores = "Not reported";
        public string Cores { get => _cores; set => Set(ref _cores, value); }
        private string _maxSpeed = "Not reported";
        public string MaxSpeed { get => _maxSpeed; set => Set(ref _maxSpeed, value); }
        private string _socket = "Not reported";
        public string Socket { get => _socket; set => Set(ref _socket, value); }
        private string _family = "Not reported";
        public string Family { get => _family; set => Set(ref _family, value); }
        private string _stepping = "Not reported";
        public string Stepping { get => _stepping; set => Set(ref _stepping, value); }
        private string _processorId = "Not reported";
        public string ProcessorId { get => _processorId; set => Set(ref _processorId, value); }
        private string _virtualization = "Not reported";
        public string Virtualization { get => _virtualization; set => Set(ref _virtualization, value); }
        private string _l2 = "Not reported";
        public string L2Cache { get => _l2; set => Set(ref _l2, value); }
        private string _l3 = "Not reported";
        public string L3Cache { get => _l3; set => Set(ref _l3, value); }
    }

    /// <summary>One physical memory slot. </summary>
    public class DimmSlot
    {
        public string Locator      { get; set; } = "";
        public string Capacity     { get; set; } = "";
        public string Type         { get; set; } = "";
        public string Speed        { get; set; } = "";
        public string PartNumber   { get; set; } = "";
        public string Manufacturer { get; set; } = "";
    }

    /// <summary>Memory card. </summary>
    public class MemoryCardModel : ObservableObject
    {
        private string _totalRam = "Not reported";
        public string TotalRam { get => _totalRam; set => Set(ref _totalRam, value); }
        private string _available = "Not reported";
        public string Available { get => _available; set => Set(ref _available, value); }
        private string _slotsTotal = "Not reported";
        public string SlotsTotal { get => _slotsTotal; set => Set(ref _slotsTotal, value); }
        private string _slotsUsed = "Not reported";
        public string SlotsUsed { get => _slotsUsed; set => Set(ref _slotsUsed, value); }
        public List<DimmSlot> Slots { get; set; } = new List<DimmSlot>();
    }

    /// <summary>One graphics adapter. </summary>
    public class GraphicsAdapter
    {
        public string Name          { get; set; } = "";
        public string Vram          { get; set; } = "";
        public string DriverVersion { get; set; } = "";
        public string DriverDate    { get; set; } = "";
    }

    /// <summary>Graphics card. </summary>
    public class GraphicsCardModel : ObservableObject
    {
        private string _displayCount = "Not reported";
        public string DisplayCount { get => _displayCount; set => Set(ref _displayCount, value); }
        public List<GraphicsAdapter> Adapters { get; set; } = new List<GraphicsAdapter>();
    }

    /// <summary>One physical disk row in the storage table. </summary>
    public class PhysicalDisk
    {
        public string Index     { get; set; } = "";
        public string Model     { get; set; } = "";
        public string Size      { get; set; } = "";
        public string BusType   { get; set; } = "";
        public string MediaType { get; set; } = "";
        public string Serial    { get; set; } = "";
        public string Firmware  { get; set; } = "";
    }

    /// <summary>One logical (mounted) volume. </summary>
    public class LogicalVolume
    {
        public string DriveLetter { get; set; } = "";
        public string Label       { get; set; } = "";
        public string FileSystem  { get; set; } = "";
        public string Size        { get; set; } = "";
        public string FreeSpace   { get; set; } = "";
        public string PercentUsed { get; set; } = "";
    }

    /// <summary>Storage card. </summary>
    public class StorageCardModel : ObservableObject
    {
        public List<PhysicalDisk>  Disks   { get; set; } = new List<PhysicalDisk>();
        public List<LogicalVolume> Volumes { get; set; } = new List<LogicalVolume>();
    }

    /// <summary>Operating System &amp; Locale card. </summary>
    public class OsLocaleCardModel : ObservableObject
    {
        private string _edition = "Not reported";
        public string Edition { get => _edition; set => Set(ref _edition, value); }
        private string _version = "Not reported";
        public string Version { get => _version; set => Set(ref _version, value); }
        private string _build = "Not reported";
        public string Build { get => _build; set => Set(ref _build, value); }
        private string _architecture = "Not reported";
        public string Architecture { get => _architecture; set => Set(ref _architecture, value); }
        private string _installDate = "Not reported";
        public string InstallDate { get => _installDate; set => Set(ref _installDate, value); }
        private string _uptime = "Not reported";
        public string Uptime { get => _uptime; set => Set(ref _uptime, value); }
        private string _timezone = "Not reported";
        public string Timezone { get => _timezone; set => Set(ref _timezone, value); }
        private string _systemTime = "Not reported";
        public string SystemTime { get => _systemTime; set => Set(ref _systemTime, value); }
        private string _ntp = "Not reported";
        public string NtpServer { get => _ntp; set => Set(ref _ntp, value); }
        private string _dotNet = "Not reported";
        public string DotNetRuntimes { get => _dotNet; set => Set(ref _dotNet, value); }
        private string _lastUpdate = "Not reported";
        public string LastUpdate { get => _lastUpdate; set => Set(ref _lastUpdate, value); }
    }

    /// <summary>One network adapter row in the table. </summary>
    public class NicInventoryRow
    {
        public string Name          { get; set; } = "";
        public string Mac           { get; set; } = "";
        public string Speed         { get; set; } = "";
        public string Status        { get; set; } = "";
        public string DriverVersion { get; set; } = "";
        public string DriverDate    { get; set; } = "";
    }

    /// <summary>One installed-software row. </summary>
    public class InstalledApp
    {
        public string DisplayName    { get; set; } = "";
        public string DisplayVersion { get; set; } = "";
        public string Publisher      { get; set; } = "";
        public string InstallDate    { get; set; } = "";
        public bool   IsFlagged      { get; set; }
    }

    /// <summary>Software Inventory card. </summary>
    public class SoftwareInventoryCardModel : ObservableObject
    {
        private int _totalCount;
        public int TotalCount { get => _totalCount; set => Set(ref _totalCount, value); }
        private int _flaggedCount;
        public int FlaggedCount { get => _flaggedCount; set => Set(ref _flaggedCount, value); }
        public List<InstalledApp> AllApps     { get; set; } = new List<InstalledApp>();
        public List<InstalledApp> FlaggedApps { get; set; } = new List<InstalledApp>();
    }
}
