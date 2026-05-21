import { useApi } from "../hooks/useApi";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import KeyValueRow from "../components/KeyValueRow";
import DataTable from "../components/DataTable";
import RefreshButton from "../components/RefreshButton";
import LoadingSpinner from "../components/LoadingSpinner";

const DDR_MAP = { 20: "DDR", 21: "DDR2", 24: "DDR3", 26: "DDR4", 34: "DDR5" };

function formatBytes(bytes) {
  if (!bytes) return "--";
  const gb = bytes / (1024 * 1024 * 1024);
  return gb >= 1 ? `${gb.toFixed(1)} GB` : `${(bytes / (1024 * 1024)).toFixed(0)} MB`;
}

export default function SystemOverview() {
  const { data, loading, refetch } = useApi("/system");

  const identity = data?.identity || {};
  const hw = data?.hardware || {};
  const cpu = hw.cpu || {};
  const memory = hw.memory || {};
  const gpu = hw.gpu || {};
  const os = data?.os || {};
  const software = data?.installedSoftware || [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="System Overview"
        subtitle={identity.hostname}
        actions={<RefreshButton onClick={refetch} loading={loading} />}
      />

      {loading && !data ? (
        <LoadingSpinner />
      ) : (
        <>
          {/* Summary Cards */}
          <div className="grid grid-cols-3 gap-4">
            <Card title="VPU Identity">
              <div className="space-y-0">
                <KeyValueRow label="Hostname" value={identity.hostname} />
                <KeyValueRow label="Manufacturer" value={identity.manufacturer} />
                <KeyValueRow label="Model" value={identity.model} />
                <KeyValueRow label="Serial" value={identity.serialNumber} mono />
                <KeyValueRow label="BIOS" value={identity.biosVersion} />
                <KeyValueRow label="Asset Tag" value={identity.assetTag} />
                {identity.pixellotVersion && (
                  <KeyValueRow label="Pixellot Version" value={identity.pixellotVersion} />
                )}
                {identity.imageVersion && (
                  <KeyValueRow label="Image Version" value={identity.imageVersion} />
                )}
              </div>
            </Card>

            <Card title="Operating System">
              <div className="space-y-0">
                <KeyValueRow label="OS" value={os.caption} />
                <KeyValueRow label="Version" value={os.version} mono />
                <KeyValueRow label="Build" value={os.buildNumber} mono />
                <KeyValueRow label="Architecture" value={os.architecture} />
                <KeyValueRow label="Install Date" value={os.installDate} />
                <KeyValueRow label="Last Boot" value={os.lastBootUpTime} />
                <KeyValueRow label="Time Zone" value={os.timeZone} />
                <KeyValueRow label="Last KB" value={os.lastKb} mono />
              </div>
            </Card>

            <Card title="CPU">
              <div className="space-y-0">
                <KeyValueRow label="Name" value={cpu.name} />
                <KeyValueRow label="Cores" value={cpu.cores} />
                <KeyValueRow label="Logical Processors" value={cpu.logicalProcessors} />
                <KeyValueRow label="Max Clock" value={cpu.maxClockSpeed ? `${cpu.maxClockSpeed} MHz` : null} />
                <KeyValueRow label="Socket" value={cpu.socket} />
                <KeyValueRow label="L2 Cache" value={cpu.l2CacheSize ? `${cpu.l2CacheSize} KB` : null} />
                <KeyValueRow label="L3 Cache" value={cpu.l3CacheSize ? `${cpu.l3CacheSize} KB` : null} />
              </div>
            </Card>

            <Card title="Memory">
              <div className="space-y-0">
                <KeyValueRow label="Total" value={formatBytes(memory.totalBytes)} />
                <KeyValueRow label="Sticks" value={memory.sticks?.length || 0} />
                {memory.sticks?.map((stick, i) => (
                  <KeyValueRow
                    key={i}
                    label={stick.deviceLocator || `DIMM ${i}`}
                    value={`${formatBytes(stick.capacity)} ${DDR_MAP[stick.memoryType] || ""} ${stick.speed || ""}MHz`}
                  />
                ))}
              </div>
            </Card>

            <Card title="GPU">
              <div className="space-y-0">
                <KeyValueRow label="Name" value={gpu.name} />
                <KeyValueRow label="VRAM" value={formatBytes(gpu.adapterRam)} />
                <KeyValueRow label="Driver" value={gpu.driverVersion} mono />
                <KeyValueRow label="Driver Date" value={gpu.driverDate} />
                <KeyValueRow label="Monitors" value={hw.monitorCount} />
              </div>
            </Card>

            <Card title="Storage">
              <div className="space-y-0">
                <KeyValueRow label="Drives" value={hw.disks?.length || 0} />
                {hw.disks?.map((disk, i) => (
                  <KeyValueRow
                    key={i}
                    label={`Disk ${disk.index ?? i}`}
                    value={`${formatBytes(disk.size)} ${disk.interfaceType || ""}`}
                  />
                ))}
              </div>
            </Card>
          </div>

          {/* Disks Table */}
          {hw.disks?.length > 0 && (
            <Card title="Physical Disks" noPad>
              <DataTable
                columns={[
                  { key: "index", label: "#", className: "w-10" },
                  { key: "model", label: "Model" },
                  { key: "serialNumber", label: "Serial", cellClass: "font-mono text-xs" },
                  { key: "interfaceType", label: "Interface" },
                  { key: "size", label: "Size", render: (v) => formatBytes(v) },
                  { key: "firmwareRevision", label: "Firmware", cellClass: "font-mono text-xs" },
                ]}
                rows={hw.disks}
              />
            </Card>
          )}

          {/* Installed Software */}
          <Card title={`Installed Software (${software.length})`} noPad>
            <DataTable
              columns={[
                { key: "displayName", label: "Name" },
                { key: "publisher", label: "Publisher" },
                { key: "displayVersion", label: "Version", cellClass: "font-mono text-xs" },
                { key: "installDate", label: "Installed" },
              ]}
              rows={software}
              emptyMessage="No software data"
            />
          </Card>
        </>
      )}
    </div>
  );
}
