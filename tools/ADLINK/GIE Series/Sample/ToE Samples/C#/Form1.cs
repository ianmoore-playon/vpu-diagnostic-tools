using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Diagnostics;
using System.Drawing;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace ToESample
{
    public partial class Form1 : Form
    {
        short m_Number = -1;
        short m_port = -1;
        public static int index;

        UInt32 myDeviceKey = 1;
        UInt32 myGroupKey = 1;
        UInt32 myGroupMask = 1;

        public Form1()
        {
            InitializeComponent();
        }

        private void Form1_Load(object sender, EventArgs e)
        {
            ushort i;
            short num;
            for (i = 0; i < SmartPoE.MAX_CARD; i++)
            {
                if ((num = SmartPoE.SmartPoE_Register_Card(i)) != 0)
                    break;

                SmartPoE.SmartPoE_Release_Card((ushort)num);

                cboCardNumber.Items.Add(i.ToString());
            }

            if (i == 0)
            {
                MessageBox.Show("No card is found!");
                Close();
                return;
            }

            cboCardNumber.SelectedIndex = 0;
            comboBox1.SelectedIndex = 0;
            initialDeviceConfig();
        }


        public void initialDeviceConfig()
        {
            int ret;

            uint Debounce;
            ushort type, Activation, Mode, Source;
            ushort Port1Status, Port2Status, Port3Status, Port4Status;

            SmartPoE.GIE_GetTriggerMode((ushort)m_Number, out Mode);
            SmartPoE.GIE_GetTriggerSource((ushort)m_Number, out Source);
            ret = SmartPoE.GIE_GetTriggerActivation((ushort)m_Number, out Activation);
            SmartPoE.GIE_GetTriggerType((ushort)m_Number, out type);
           
            SmartPoE.GIE_GetTriggerDebounce((ushort)m_Number, out Debounce);
            SmartPoE.SmartPoE_Get_Power_Enable((ushort)m_Number, out Port1Status, out Port2Status, out  Port3Status, out  Port4Status);

            TriggerStatecheckBox.Checked = Convert.ToBoolean(Mode);

            for (int port = 1; port <= 4; port++ )
            {
                if(port == 1)
                {
                    CheckPoEStatus(rdoOn1, rdoOff1, Port1Status);
                }
                else if(port == 2)
                {
                    CheckPoEStatus(rdoOn2, rdoOff2, Port2Status);
                }
                else if (port == 3)
                {
                    CheckPoEStatus(rdoOn3, rdoOff3, Port3Status);
                }
                else if (port == 4)
                {
                    CheckPoEStatus(rdoOn4, rdoOff4, Port4Status);
                }
            }


            if (Source == 0)
            {
                radioButtonSoft.Checked = true;
            }
            else
            {
                radioButtonExternal.Checked = true;
            }

            //1 :Falling Edge 
            //2 :Rising Edge

            if (Activation == 1)
            {
                radioButtonFalling.Checked = true;
            }
            else if (Activation == 0)
            {
                radioButtonRising.Checked = true;
            }


            if (type == 0)
            {
                radioButton4to4.Checked = true;
            }
            else
            {
                radioButton1to4.Checked = true;
            }


            textDebounce.Text = Debounce.ToString();

        }

        private void CheckPoEStatus(RadioButton buttonON, RadioButton buttonOFF, ushort Status)
        {
            switch (Status)
            {
                case 0:
                    buttonON.Checked = false;
                    buttonOFF.Checked = true;
                    break;
                case 1:
                    buttonON.Checked = true;
                    buttonOFF.Checked = false;
                    break;
            }
        }



        private void Form1_FormClosed(object sender, FormClosedEventArgs e)
        {
            if (m_Number >= 0)
                SmartPoE.SmartPoE_Release_Card((ushort)m_Number);
        }

        private void cboCardNumber_SelectedIndexChanged(object sender, EventArgs e)
        {
            short Number;
            ushort card_num = (ushort)cboCardNumber.SelectedIndex;

            if(m_Number >= 0)
                SmartPoE.SmartPoE_Release_Card((ushort)m_Number);

            Number = SmartPoE.SmartPoE_Register_Card(card_num);
            if (Number != 0)
            {
                MessageBox.Show("Selecting card is failed");
                return;
            }

            ushort ID = 0;
            short ret = SmartPoE.SmartPoE_Get_ID((ushort)Number, out ID);
            if (ret < 0)
                txtCardID.Text = "Error";
            else
                txtCardID.Text = ID.ToString();
            
            m_Number = (short)Number;

            initialDeviceConfig();
        }

        private void btnSet_Click(object sender, EventArgs e)
        {
            if (m_Number < 0)
                return;

            if (!CheckUserInput())
            {
                MessageBox.Show("Some ON/OFF state of ports are not set!");
                return;
            }

            ushort EnPort1 = (ushort)(rdoOn1.Checked ? 1 : 0);
            ushort EnPort2 = (ushort)(rdoOn2.Checked ? 1 : 0);
            ushort EnPort3 = (ushort)(rdoOn3.Checked ? 1 : 0);
            ushort EnPort4 = (ushort)(rdoOn4.Checked ? 1 : 0);

            if (SmartPoE.SmartPoE_Power_Enable((ushort)m_Number, EnPort1, EnPort2, EnPort3, EnPort4) != 0)
                MessageBox.Show("Setting power is failed");
        }

        private bool CheckUserInput()
        {
            ushort EnPort1On = (ushort)(rdoOn1.Checked ? 1 : 0);
            ushort EnPort2On = (ushort)(rdoOn2.Checked ? 1 : 0);
            ushort EnPort3On = (ushort)(rdoOn3.Checked ? 1 : 0);
            ushort EnPort4On = (ushort)(rdoOn4.Checked ? 1 : 0);

            ushort EnPort1Off = (ushort)(rdoOff1.Checked ? 1 : 0);
            ushort EnPort2Off = (ushort)(rdoOff2.Checked ? 1 : 0);
            ushort EnPort3Off = (ushort)(rdoOff3.Checked ? 1 : 0);
            ushort EnPort4Off = (ushort)(rdoOff4.Checked ? 1 : 0);

            if ((EnPort1On == 0 && EnPort1Off == 0) ||
                (EnPort2On == 0 && EnPort2Off == 0) ||
                (EnPort3On == 0 && EnPort3Off == 0) ||
                (EnPort4On == 0 && EnPort4Off == 0))
                return false;

            return true;

        }

        private void radioButtonRising_CheckedChanged(object sender, EventArgs e)
        {
            SmartPoE.GIE_SetTriggerActivation((ushort)m_Number, 0);
        }

        private void radioButtonFalling_CheckedChanged(object sender, EventArgs e)
        {
            SmartPoE.GIE_SetTriggerActivation((ushort)m_Number, 1);
        }

        private void radioButton4to4_CheckedChanged(object sender, EventArgs e)
        {
            SmartPoE.GIE_SetTriggerType((ushort)m_Number, 0);
        }

        private void radioButton1to4_CheckedChanged(object sender, EventArgs e)
        {
            SmartPoE.GIE_SetTriggerType((ushort)m_Number, 1);
        }

        private void buttonGet_Click(object sender, EventArgs e)
        {
            uint Debounce;
            SmartPoE.GIE_GetTriggerDebounce((ushort)m_Number, out Debounce);

            textDebounce.Text = Debounce.ToString();
        }

        private void buttonSet_Click(object sender, EventArgs e)
        {
            uint Debounce;

            int ret;

            Debounce = Convert.ToUInt32(textDebounce.Text);

            ret = SmartPoE.GIE_SetTriggerDebounce((ushort)m_Number, Debounce);

            if (ret < 0)
                MessageBox.Show(ret.ToString());
        }

        private void comboBox1_SelectedIndexChanged(object sender, EventArgs e)
        {
            index = comboBox1.SelectedIndex;
          

            switch (index)
            {
                case 0:
                    m_port = 1;
                    ActionCommandKey((ushort)m_port);

                    break;
                case 1:
                    m_port = 2;
                    ActionCommandKey((ushort)m_port);
                  
                    break;
                case 2:
                    m_port = 3;
                    ActionCommandKey((ushort)m_port);

                    break;
                case 3:
                    m_port = 4;
                    ActionCommandKey((ushort)m_port);

                    break;

            }
        }

        private void ActionCommandKey(ushort port)
        {
            uint deviceKey, groupKey, GroupMask;

            SmartPoE.GIE_Get_ActionCommand((ushort)m_Number, (ushort)m_port, out deviceKey, out groupKey, out GroupMask);
            deviceKeyTextBox.Text = "0x" + deviceKey.ToString("X8");
            groupKeyTextBox.Text = "0x" + groupKey.ToString("X8");
            groupMaskTextBox.Text = "0x" + GroupMask.ToString("X8");

        }

        private void ActionCommandbutton_Click(object sender, EventArgs e)
        {
            int ret;


            // Parse the values from the Text Boxes
            string valueString = deviceKeyTextBox.Text.ToUpper();

            // Is this a hex number?
            if (valueString.Contains("0X"))
            {
                valueString = valueString.Substring(valueString.IndexOf("0X") + 2);
                myDeviceKey = UInt32.Parse(valueString, System.Globalization.NumberStyles.HexNumber);
            }
            else // Assume decimal number
            {
                try
                {
                    myDeviceKey = UInt32.Parse(valueString);
                }
                catch (Exception ex)
                {
                    // We could not parse the address as decimal.
                    System.Diagnostics.Debug.WriteLine(ex.Message);
                    myDeviceKey = 0;
                }
            }

            deviceKeyTextBox.Text = "0x" + myDeviceKey.ToString("X8");

            valueString = groupKeyTextBox.Text.ToUpper();

            // Is this a hex number?
            if (valueString.Contains("0X"))
            {
                valueString = valueString.Substring(valueString.IndexOf("0X") + 2);
                myGroupKey = UInt32.Parse(valueString, System.Globalization.NumberStyles.HexNumber);
            }
            else // Assume decimal number
            {
                try
                {
                    myGroupKey = UInt32.Parse(valueString);
                }
                catch (Exception ex)
                {
                    // We could not parse the address as decimal.
                    System.Diagnostics.Debug.WriteLine(ex.Message);
                    myGroupKey = 0;
                }
            }

            groupKeyTextBox.Text = "0x" + myGroupKey.ToString("X8");

            valueString = groupMaskTextBox.Text.ToUpper();

            // Is this a hex number?
            if (valueString.Contains("0X"))
            {
                valueString = valueString.Substring(valueString.IndexOf("0X") + 2);
                myGroupMask = UInt32.Parse(valueString, System.Globalization.NumberStyles.HexNumber);
            }
            else // Assume decimal number
            {
                try
                {
                    myGroupMask = UInt32.Parse(valueString);
                }
                catch (Exception ex)
                {
                    // We could not parse the address as decimal.
                    System.Diagnostics.Debug.WriteLine(ex.Message);
                    myGroupMask = 0;
                }
            }

            groupMaskTextBox.Text = "0x" + myGroupMask.ToString("X8");

            //myDeviceKey, myGroupKey, myGroupMask 
            ret = SmartPoE.GIE_Set_ActionCommand((ushort)m_Number, (ushort)m_port, myDeviceKey, myGroupKey, myGroupMask);
            Thread.Sleep(50); // Delay time will be different with the system

            if (ret < 0)
                MessageBox.Show("Error" + ret.ToString());
        }

        private void StartTriggerButton_Click(object sender, EventArgs e)
        {
            Debug.WriteLine("Start1");
            SmartPoE.GIE_Send_SoftwareActionCommand((ushort)m_Number, (ushort)m_port);
            Debug.WriteLine("End1");
        }



   
        private void buttonCounter1_Click(object sender, EventArgs e)
        {
            ushort TriggerCount;
            ushort TriggerSentCount;
            SmartPoE.GIE_GetTriggerCount((ushort)m_Number, 1, out TriggerCount, out TriggerSentCount);

            Port1TriggerCount.Text = "(" + TriggerCount.ToString() + "," + TriggerSentCount.ToString() + ") counts";
        }

        private void buttonCounter2_Click(object sender, EventArgs e)
        {
            ushort TriggerCount;
            ushort TriggerSentCount;
            SmartPoE.GIE_GetTriggerCount((ushort)m_Number, 2, out TriggerCount, out TriggerSentCount);

            Port2TriggerCount.Text = "(" + TriggerCount.ToString() + "," + TriggerSentCount.ToString() + ") counts";
        }

        private void buttonCounter3_Click(object sender, EventArgs e)
        {
            ushort TriggerCount;
            ushort TriggerSentCount;
            SmartPoE.GIE_GetTriggerCount((ushort)m_Number, 3, out TriggerCount, out TriggerSentCount);

            Port3TriggerCount.Text = "(" + TriggerCount.ToString() + "," + TriggerSentCount.ToString() + ") counts";
        }

        private void buttonCounter4_Click(object sender, EventArgs e)
        {
            ushort TriggerCount;
            ushort TriggerSentCount;
            SmartPoE.GIE_GetTriggerCount((ushort)m_Number, 4, out TriggerCount, out TriggerSentCount);

            Port4TriggerCount.Text = "(" + TriggerCount.ToString() + "," + TriggerSentCount.ToString() + ") counts";
        }

        private void buttonReset_Click(object sender, EventArgs e)
        {
            SmartPoE.GIE_ResetTriggerCount((ushort)m_Number);
        }

        private void TriggerStatecheckBox_CheckedChanged(object sender, EventArgs e)
        {
            if (TriggerStatecheckBox.Checked == true)
            {
                groupBox4.Enabled = false;
                SmartPoE.GIE_SetTriggerMode((ushort)m_Number, 1);
            }
            else
            {
                groupBox4.Enabled = true;
                SmartPoE.GIE_SetTriggerMode((ushort)m_Number, 0);
            }
        }

        private void radioButtonSoft_CheckedChanged(object sender, EventArgs e)
        {
            groupBoxSoftCMD.Enabled = true;
            SmartPoE.GIE_SetTriggerSource((ushort)m_Number, 0);
        }

        private void radioButtonExternal_CheckedChanged(object sender, EventArgs e)
        {
            groupBoxSoftCMD.Enabled = false;
            SmartPoE.GIE_SetTriggerSource((ushort)m_Number, 1);
        }

        private void StartAllTriggerButton_Click(object sender, EventArgs e)
        {
            SmartPoE.GIE_Send_AllSoftwareActionCommand((ushort)m_Number);
        }
    }
}