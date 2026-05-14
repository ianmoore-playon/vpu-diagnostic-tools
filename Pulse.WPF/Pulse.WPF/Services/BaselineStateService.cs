using System;
using System.IO;
using System.Xml.Serialization;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Persists the last baseline summary under the user's local profile.
    /// XML keeps it support-readable and avoids adding a package dependency.
    /// </summary>
    public class BaselineStateService
    {
        public string StateDirectory { get; }
        public string LastBaselinePath { get; }

        public BaselineStateService()
        {
            try
            {
                var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                StateDirectory = Path.Combine(local, "Pulse.WPF", "State");
                Directory.CreateDirectory(StateDirectory);
            }
            catch
            {
                StateDirectory = Path.Combine(Path.GetTempPath(), "Pulse.WPF", "State");
                try { Directory.CreateDirectory(StateDirectory); } catch { }
            }

            LastBaselinePath = Path.Combine(StateDirectory, "last-baseline.xml");
        }

        public BaselineSnapshot LoadLast()
        {
            try
            {
                if (!File.Exists(LastBaselinePath)) return null;
                var serializer = new XmlSerializer(typeof(BaselineSnapshot));
                using (var fs = File.OpenRead(LastBaselinePath))
                {
                    return serializer.Deserialize(fs) as BaselineSnapshot;
                }
            }
            catch
            {
                return null;
            }
        }

        public bool Save(BaselineSnapshot snapshot)
        {
            if (snapshot == null) return false;
            var tmp = LastBaselinePath + ".tmp";
            try
            {
                Directory.CreateDirectory(StateDirectory);
                var serializer = new XmlSerializer(typeof(BaselineSnapshot));
                using (var fs = File.Create(tmp))
                {
                    serializer.Serialize(fs, snapshot);
                }

                if (File.Exists(LastBaselinePath)) File.Delete(LastBaselinePath);
                File.Move(tmp, LastBaselinePath);
                return true;
            }
            catch
            {
                try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
                return false;
            }
        }
    }
}
