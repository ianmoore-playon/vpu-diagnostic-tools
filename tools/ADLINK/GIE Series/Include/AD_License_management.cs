using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Runtime.InteropServices;


namespace CS_testSecurity5
{
    class AD_License_management
    {
        [DllImport("SmartPoE.dll", EntryPoint = "AD_InstallSecret")]
        public static extern short AD_InstallSecret(ushort wCardNumber, byte[] MasterSecret,  bool LockBit);

        [DllImport("SmartPoE.dll", EntryPoint = "AD_SetMasterSecret")]
        public static extern short AD_SetMasterSecret(ushort wCardNumber, byte[] MasterSecret);

        [DllImport("SmartPoE.dll", EntryPoint = "AD_EncryptReadSegment")]
        public static extern short AD_EncryptReadSegment(ushort wCardNumber, byte[] data, byte[] romid, byte[] manid, byte[] read_mac, byte[] read_challenge);        

        [DllImport("SmartPoE.dll", EntryPoint = "AD_EncryptComputeEnc")]
        public static extern short AD_EncryptComputeEnc(ushort wCardNumber, byte[] new_data, byte[] romid, byte[] manid, byte[] read_mac, byte[] challenge, byte[] enc_data, byte[] chk_mac);

        [DllImport("SmartPoE.dll", EntryPoint = "AD_EncryptAuthWritePageEnc")]
        public static extern short AD_EncryptAuthWritePageEnc(ushort wCardNumber, ushort numBytesTot, byte[] enc_data, byte[] old_data, byte[] romid, byte[] manid, byte[] chk_mac, byte[] challenge, ushort lockdata);

        [DllImport("SmartPoE.dll", EntryPoint = "AD_ReadInstallSecretStatus")]
        public static extern short AD_ReadInstallSecretStatus(ushort wCardNumber, out byte InstallBit, out byte LockBit);
    }
}
