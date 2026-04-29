using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Text;
using System.Windows.Forms;

namespace SmartPoESample
{
    public partial class Form1 : Form
    {
        short m_Number = -1;

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
    }
}